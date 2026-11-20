"""Workbench compatibility routes and a route-local pre-inference adapter hook."""
from __future__ import annotations

import copy
from functools import cached_property
import os
import types
from typing import Callable

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, ValidationError
from pydantic_ai.ui.ag_ui import AGUIAdapter

from .a2ui_action import with_user_action
from .strict_json import DuplicateJSONKey, parse_json_no_duplicates
from .workbench_actions import (
    WORKBENCH_INTAKE_TOOL_NAME, SubmissionDedup, submission_messages, validate_submission,
)
from .workbench_projection import projection_from_thread
from .workbench_repository import SQLiteWorkbenchRepository, WorkbenchScope, shared_repository


class RestoreBody(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    nodeId: str


def _repository_for(request, repository):
    if repository is not None:
        return repository
    configured = getattr(request.app.state, "workbench_repository", None)
    if configured is None:
        configured = shared_repository()
        request.app.state.workbench_repository = configured
    return configured


def workbench_scope(the_installation, actor_id, room_id, thread_id):
    server_id = (getattr(the_installation, "server_id", None)
                 or the_installation.get_environment("SOLIPLEX_WORKBENCH_SERVER_ID") or "default")
    return WorkbenchScope(str(actor_id), str(server_id), room_id, thread_id)


async def _read_request_json(request):
    try:
        value = parse_json_no_duplicates(await request.body())
    except DuplicateJSONKey as exc:
        raise HTTPException(400, "duplicate JSON object key") from exc
    except (ValueError, UnicodeDecodeError) as exc:
        raise HTTPException(400, "invalid JSON request body") from exc
    if not isinstance(value, dict):
        raise HTTPException(400, "JSON request body must be an object")
    return value


def _validate_history(run_input, trusted_messages):
    """Only server-stored synthetic messages can be echoed in client history."""
    for tool in run_input.tools:
        if tool.name == WORKBENCH_INTAKE_TOOL_NAME:
            raise HTTPException(422, "workbench_intake is a reserved synthetic tool")
    trusted = {message.id: message for message in trusted_messages}
    for message in run_input.messages:
        calls = getattr(message, "tool_calls", None) or []
        reserved = (any(call.function.name == WORKBENCH_INTAKE_TOOL_NAME
                            or call.id.startswith("workbench-intake-") for call in calls)
                    or str(getattr(message, "tool_call_id", "")).startswith("workbench-intake-")
                    or message.id.startswith(("workbench-intake-", "workbench-result-")))
        if reserved and trusted.get(message.id) != message:
            raise HTTPException(422, "client-supplied workbench submission messages are forbidden")
    call_ids = [call.id for message in run_input.messages for call in (getattr(message, "tool_calls", None) or [])]
    if len(call_ids) != len(set(call_ids)):
        raise HTTPException(422, "AG-UI tool-call IDs must be unique")
    ids = [message.id for message in run_input.messages]
    if len(ids) != len(set(ids)):
        raise HTTPException(422, "AG-UI message IDs must be unique")


def _snapshot_records(content: list[dict[str, object]]) -> list[dict[str, object]]:
    """Number the content parts a snapshot ships, per commit record.

    A commit also writes a layout part, which the snapshot carries in its
    layout field, so each record's count and indexes cover content parts only.
    """
    by_record: dict[str, list[dict[str, object]]] = {}
    for item in content:
        by_record.setdefault(str(item["workbenchCommit"]["recordId"]), []).append(item)
    records = []
    for record_id, items in by_record.items():
        items.sort(key=lambda item: item["workbenchCommit"]["index"])
        for index, item in enumerate(items):
            records.append({"recordId": record_id, "sequence": item["workbenchCommit"]["sequence"],
                            "partIndex": index, "partCount": len(items),
                            "content": item})
    return records


def build_router(*, repository: SQLiteWorkbenchRepository | None = None, trace_sink=None, workbench_rooms: set[str] | None = None) -> APIRouter:
    """Build routes with the installed Soliplex 0.93 public dependencies."""
    from soliplex import agui, authz, installation, views

    router = APIRouter()
    allowed_rooms = workbench_rooms
    if allowed_rooms is None:
        allowed_rooms = {room.strip() for room in os.environ.get("SOLIPLEX_WORKBENCH_ROOMS", "").split(",") if room.strip()}

    async def scope_dependencies(
        room_id: str,
        thread_id: str,
        request: Request,
        the_installation=installation.depend_the_installation,
        the_threads=agui.depend_the_threads,
        policy=views.depend_the_room_authz_policy,
        claims=views.depend_the_user_claims,
    ) -> WorkbenchScope:
        if room_id not in allowed_rooms:
            raise HTTPException(503, "workbench room is not configured in SOLIPLEX_WORKBENCH_ROOMS")
        username = claims.get("preferred_username")
        if not username:
            raise HTTPException(401, "authenticated user required")
        permission = authz.Permission.WRITE if request.method == "POST" else authz.Permission.READ
        if not await policy.check_room_access(room_id, claims, permission=permission):
            raise HTTPException(403, "room access denied")
        try:
            await the_threads.get_thread(user_name=username, room_id=room_id, thread_id=thread_id)
        except Exception as exc:
            raise HTTPException(404, "thread not found") from exc
        return workbench_scope(the_installation, str(username), room_id, thread_id)

    @router.get("/v1/rooms/{room_id}/threads/{thread_id}/workbench")
    async def snapshot(room_id: str, thread_id: str, request: Request, scope=Depends(scope_dependencies)):
        data = _repository_for(request, repository).load_snapshot(scope)
        layout_registration = {
            "role": "layout",
            "activityMessageId": f"wb-layout-{__import__('hashlib').sha256('/'.join(scope.key()).encode()).hexdigest()[:24]}",
            "surfaceId": f"wb-control-{__import__('hashlib').sha256('/'.join(scope.key()).encode()).hexdigest()[:24]}",
        }
        content = data["content"]
        registrations = [layout_registration, *[
            {"role": "content", "activityMessageId": item["activityMessageId"], "surfaceId": item["surfaceId"]}
            for item in content
        ]]
        return {
            "revision": data["revision"],
            "layout": data["layout"],
            "registrations": registrations,
            "records": _snapshot_records(content),
        }

    @router.post("/v1/rooms/{room_id}/threads/{thread_id}/workbench/actions/restore")
    async def restore(room_id: str, thread_id: str, request: Request, scope=Depends(scope_dependencies)):
        try:
            body = RestoreBody.model_validate(await _read_request_json(request))
            return _repository_for(request, repository).restore_node(scope, body.nodeId)
        except ValidationError as exc:
            raise HTTPException(422, "invalid workbench restore target") from exc
        except ValueError as exc:
            raise HTTPException(422, "invalid workbench restore target") from exc

    return router


def _endpoint_with_adapter(endpoint, adapter):
    """Soliplex 0.93 compatibility seam, isolated to this router's run handler.

    That release has no adapter factory hook. Bind a private copy of the
    endpoint's globals to our subclass. Never patch pydantic-ai, Soliplex's
    module globals, Request bytes, or unrelated routes. Preserve the stock
    signature, dependencies, authorization, persistence and SSE delivery.
    """
    namespace = dict(endpoint.__globals__)
    if "ai_ag_ui" in namespace:
        namespace["ai_ag_ui"] = types.SimpleNamespace(
            **{**vars(namespace["ai_ag_ui"]), "AGUIAdapter": adapter})
    if "AGUIAdapter" in namespace:
        namespace["AGUIAdapter"] = adapter
    bound = types.FunctionType(endpoint.__code__, namespace, endpoint.__name__,
                               endpoint.__defaults__, endpoint.__closure__)
    bound.__kwdefaults__ = endpoint.__kwdefaults__
    bound.__annotations__ = endpoint.__annotations__
    bound.__dict__.update(endpoint.__dict__)
    return bound


def create_guarded_agui_router(agui_router=None, *, scope_provider: Callable | None = None,
                               projection_provider=None, workbench_rooms=None, lab_rooms=None):
    """Hook only first-connect POST run inference in configured workbench rooms.

    Legacy lab rooms, other endpoints, and reconnects use the stock path.
    scope/projection providers are explicit test seams; production reads
    authenticated identity and server-stored events/run inputs.
    """
    from soliplex import installation, views
    from soliplex.agui import UnknownThread
    from soliplex.views.agui import router as default_router, parse_last_event_id

    upstream = agui_router or default_router
    rooms = set(workbench_rooms) if workbench_rooms is not None else {
        room.strip() for room in os.environ.get("SOLIPLEX_WORKBENCH_ROOMS", "").split(",") if room.strip()}
    if workbench_rooms is None and isinstance(scope_provider, WorkbenchScope):
        rooms.add(scope_provider.room_id)
    labs = set(lab_rooms) if lab_rooms is not None else {
        room.strip() for room in os.environ.get("SOLIPLEX_A2UI_LAB_ROOMS", "a2ui-lab,a2ui-lab-e4b").split(",") if room.strip()}
    dedup = SubmissionDedup()

    class LegacyLabAdapter(AGUIAdapter):
        @cached_property
        def messages(self):
            # Preserve the existing lab's model-facing action reader without
            # touching its wire input or applying workbench validation.
            return self.load_messages(
                with_user_action(self.run_input.messages, self.run_input.forwarded_props),
                preserve_file_data=self.preserve_file_data)

    async def identify(request: Request,
                       the_installation=installation.depend_the_installation,
                       claims=views.depend_the_user_claims):
        # Stock endpoint authorizes the room before calling from_request.
        # ThreadStorage below enforces authenticated ownership of the source.
        if request.path_params.get("room_id") not in rooms or parse_last_event_id(request.headers.get("last-event-id")) is not None:
            return
        actor = claims.get("preferred_username")
        if not actor:
            raise HTTPException(401, "authenticated user required")
        request.state.workbench_scope = workbench_scope(
            the_installation, actor, request.path_params["room_id"], request.path_params["thread_id"])

    async def test_identify(request: Request):
        value = scope_provider(request) if callable(scope_provider) else scope_provider
        request.state.workbench_scope = await value if hasattr(value, "__await__") else value

    class WorkbenchAdapter(AGUIAdapter):
        @classmethod
        async def from_request(cls, request, **kwargs):
            if request.path_params.get("room_id") not in rooms:
                legacy = LegacyLabAdapter if request.path_params.get("room_id") in labs else AGUIAdapter
                return await legacy.from_request(request, **kwargs)
            # The stock endpoint never parses a reconnect body or calls this
            # method for replay. Keep that boundary even for adapter callers.
            if parse_last_event_id(request.headers.get("last-event-id")) is not None:
                return await AGUIAdapter.from_request(request, **kwargs)
            await _read_request_json(request)  # Reject duplicate keys; bytes stay unchanged.
            try:
                adapter = await super().from_request(request, **kwargs)
            except Exception:
                raise HTTPException(422, "invalid AG-UI run input") from None
            run_input = adapter.run_input
            if (run_input.thread_id != request.path_params["thread_id"]
                    or run_input.run_id != request.path_params["run_id"]):
                raise HTTPException(400, "AG-UI URL and body identifiers do not match")
            if isinstance(run_input.state, dict) and "workbenchAction" in run_input.state:
                raise HTTPException(422, "workbenchAction is server-owned")
            scope = getattr(request.state, "workbench_scope", None)
            if scope is None:
                raise HTTPException(403, "authenticated workbench scope required")
            try:
                if projection_provider is not None:
                    projection = projection_provider(request, scope)
                    if hasattr(projection, "__await__"):
                        projection = await projection
                else:
                    projection = await projection_from_thread(types.SimpleNamespace(
                        thread_persistence_engine=request.state.threads_engine), scope)
            except (LookupError, PermissionError, UnknownThread) as exc:
                raise HTTPException(404, "thread not found") from exc
            history = getattr(projection, "submission_history", [])
            trusted = [message for _, messages in history for message in messages]
            _validate_history(run_input, trusted)
            # Reinsert accepted data at its original transcript position on
            # continuation/reload. Never accept a client-authored synthetic pair.
            ids = {message.id for message in run_input.messages}
            for anchor, messages in history:
                missing = [message for message in messages if message.id not in ids]
                index = next((i + 1 for i, message in enumerate(run_input.messages) if message.id == anchor), len(run_input.messages))
                run_input.messages[index:index] = missing
                ids.update(message.id for message in missing)
            props = run_input.forwarded_props
            if not isinstance(props, dict) or "a2uiAction" not in props:
                return adapter
            try:
                submission = validate_submission(props["a2uiAction"], projection)
            except (ValueError, TypeError, ValidationError) as exc:
                # Pydantic errors echo inputs, which may contain credentials.
                # Return fixed diagnostics without logging or echoing values.
                reason = "invalid workbench action: check source, action name and bounded context"
                if isinstance(exc, ValueError) and not isinstance(exc, ValidationError):
                    reason = str(exc)  # Validator's fixed vocabulary only.
                raise HTTPException(422, reason) from None
            try:
                dedup.claim(scope, submission.submissionId, getattr(projection, "submission_ids", set()))
            except ValueError as exc:
                raise HTTPException(409, str(exc)) from exc
            run_input.messages.extend(submission_messages(submission))
            return adapter

    # Copy only execution routes, then let FastAPI rebuild their dependency
    # graph from the unchanged signature. No mutation of upstream routes.
    bound_router = APIRouter()
    for route in upstream.routes:
        if (getattr(route, "path", "").endswith("/{run_id}")
                and "POST" in getattr(route, "methods", ())):
            bound_route = copy.copy(route)
            bound_route.endpoint = _endpoint_with_adapter(route.endpoint, WorkbenchAdapter)
            bound_route.dependencies = [*route.dependencies, Depends(test_identify if scope_provider is not None else identify)]
            bound_router.routes.append(bound_route)
        else:
            bound_router.routes.append(route)
    guarded = APIRouter()
    guarded.include_router(bound_router)
    return guarded


try:
    guarded_router = create_guarded_agui_router()
except ModuleNotFoundError as exc:
    if exc.name != "soliplex":
        raise
    guarded_router = APIRouter()
