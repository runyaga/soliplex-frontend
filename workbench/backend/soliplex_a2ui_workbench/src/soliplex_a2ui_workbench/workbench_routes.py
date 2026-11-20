"""Authenticated room/thread workbench routes and guarded AG-UI dispatch."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Callable

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, ValidationError
from ag_ui.core import Message
from pydantic import TypeAdapter

from .a2ui_action import user_action, with_user_action
from .strict_json import DuplicateJSONKey, parse_json_no_duplicates
from .workbench_actions import WORKBENCH_INTAKE_TOOL_NAME, WorkbenchActionService, synthetic_intake_messages
from .workbench_repository import PublicationConflict, SQLiteWorkbenchRepository, WorkbenchScope


class ActionBody(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    v: int
    submissionId: str
    activityMessageId: str
    surfaceRevision: int
    actionSchemaVersion: str
    userAction: dict[str, object]


class RestoreBody(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    nodeId: str


def _repository_for(request: Request, repository: SQLiteWorkbenchRepository | None) -> SQLiteWorkbenchRepository:
    if repository is not None:
        return repository
    configured = getattr(request.app.state, "workbench_repository", None)
    if configured is not None:
        return configured
    path = Path(os.environ.get("SOLIPLEX_WORKBENCH_DB", "/data/workbench/workbench.sqlite3"))
    path.parent.mkdir(parents=True, exist_ok=True)
    configured = SQLiteWorkbenchRepository(path)
    request.app.state.workbench_repository = configured
    return configured


def _reject_client_workbench_intake_tool(payload: dict[str, object]) -> None:
    """Keep the synthetic workbench tool name server-owned and non-callable."""
    tools = payload.get("tools")
    if isinstance(tools, list):
        for tool in tools:
            if not isinstance(tool, dict):
                continue
            function = tool.get("function")
            if tool.get("name") == WORKBENCH_INTAKE_TOOL_NAME or (isinstance(function, dict) and function.get("name") == WORKBENCH_INTAKE_TOOL_NAME):
                raise HTTPException(422, "workbench_intake is a reserved synthetic tool")


def _reject_client_workbench_fields(payload: dict[str, object]) -> None:
    state = payload.get("state")
    if isinstance(state, dict) and "workbenchAction" in state:
        raise HTTPException(422, "workbenchAction is server-owned")
    _reject_client_workbench_intake_tool(payload)
    messages = payload.get("messages")
    if not isinstance(messages, list):
        return
    for message in messages:
        if not isinstance(message, dict):
            continue
        calls = message.get("toolCalls", message.get("tool_calls"))
        if message.get("name") == WORKBENCH_INTAKE_TOOL_NAME or (
            isinstance(calls, list)
            and any(
                isinstance(call, dict)
                and isinstance(call.get("function"), dict)
                and call["function"].get("name") == WORKBENCH_INTAKE_TOOL_NAME
                for call in calls
            )
        ) or (
            message.get("role") == "tool"
            and isinstance(message.get("toolCallId", message.get("tool_call_id")), str)
            and message.get("toolCallId", message.get("tool_call_id")).startswith("workbench-intake-")
        ):
            raise HTTPException(422, "workbench_intake is a reserved synthetic tool")


def _validate_issued_intake_history(payload: dict[str, object], issued: list[dict[str, object]]) -> None:
    messages = payload.get("messages")
    if not isinstance(messages, list):
        raise HTTPException(422, "AG-UI messages must be an array")
    try:
        adapter = TypeAdapter(Message)
        normalized = [adapter.validate_python(item).model_dump(mode="json", by_alias=True, exclude_none=True) for item in messages]
        issued_pairs = []
        for envelope in issued:
            pair = synthetic_intake_messages(envelope)
            issued_pairs.append([
                adapter.validate_python(item).model_dump(mode="json", by_alias=True, exclude_none=True)
                for item in pair
            ])
    except (TypeError, ValueError, ValidationError) as exc:
        raise HTTPException(422, "invalid AG-UI message history") from exc
    message_ids = [message.get("id") for message in normalized if isinstance(message.get("id"), str)]
    if len(message_ids) != len(set(message_ids)):
        raise HTTPException(422, "AG-UI message IDs must be unique")
    tool_call_ids = []
    for message in normalized:
        calls = message.get("toolCalls", [])
        if isinstance(calls, list):
            tool_call_ids.extend(call.get("id") for call in calls if isinstance(call, dict) and isinstance(call.get("id"), str))
    if len(tool_call_ids) != len(set(tool_call_ids)):
        raise HTTPException(422, "AG-UI tool-call IDs must be unique")
    index = 0
    while index < len(normalized):
        message = normalized[index]
        calls = message.get("toolCalls", [])
        reserved_call = isinstance(calls, list) and any(
            isinstance(call, dict)
            and isinstance(call.get("function"), dict)
            and call["function"].get("name") == WORKBENCH_INTAKE_TOOL_NAME
            for call in calls
        )
        reserved_result = message.get("role") == "tool" and (
            message.get("name") == WORKBENCH_INTAKE_TOOL_NAME
            or (isinstance(message.get("toolCallId"), str) and message["toolCallId"].startswith("workbench-intake-"))
        )
        if reserved_call or reserved_result:
            match_index = next((pair_index for pair_index, pair in enumerate(issued_pairs) if normalized[index:index + 2] == pair), None)
            if match_index is None:
                raise HTTPException(422, "client-supplied workbench_intake messages are forbidden")
            issued_pairs.pop(match_index)
            index += 2
        else:
            index += 1


async def _validate_full_agui_request(request: Request) -> None:
    """Parse the complete run body before any reservation state can change."""
    try:
        from pydantic_ai import Agent
        from pydantic_ai.models.test import TestModel
        from pydantic_ai.ui.ag_ui import AGUIAdapter

        await AGUIAdapter.from_request(request, agent=Agent(TestModel()))
    except Exception as exc:
        raise HTTPException(422, "invalid AG-UI run input") from exc


async def _read_request_json(request: Request) -> dict[str, object]:
    try:
        raw = await request.body()
        value = parse_json_no_duplicates(raw)
    except DuplicateJSONKey as exc:
        raise HTTPException(400, "duplicate JSON object key") from exc
    except (ValueError, UnicodeDecodeError) as exc:
        raise HTTPException(400, "invalid JSON request body") from exc
    if not isinstance(value, dict):
        raise HTTPException(400, "JSON request body must be an object")
    return value


def _normalize_agui_aliases(payload: dict[str, object]) -> dict[str, object]:
    """Normalize accepted AG-UI snake/camel aliases before guard inspection."""
    changed = False

    def normalize(mapping: dict[str, object], camel: str, snake: str) -> None:
        nonlocal changed
        if camel in mapping and snake in mapping:
            raise HTTPException(400, f"conflicting AG-UI fields: {camel} and {snake}")
        if snake in mapping:
            mapping[camel] = mapping.pop(snake)
            changed = True

    for camel, snake in (
        ("threadId", "thread_id"),
        ("runId", "run_id"),
        ("parentRunId", "parent_run_id"),
        ("forwardedProps", "forwarded_props"),
    ):
        normalize(payload, camel, snake)
    messages = payload.get("messages")
    if isinstance(messages, list):
        for message in messages:
            if not isinstance(message, dict):
                continue
            normalize(message, "toolCalls", "tool_calls")
            normalize(message, "toolCallId", "tool_call_id")
            calls = message.get("toolCalls")
            if isinstance(calls, list):
                for call in calls:
                    if isinstance(call, dict):
                        normalize(call, "encryptedValue", "encrypted_value")
            normalize(message, "encryptedValue", "encrypted_value")
    return payload


async def _read_agui_json(request: Request) -> dict[str, object]:
    return _normalize_agui_aliases(await _read_request_json(request))


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
        server_id = (
            getattr(the_installation, "server_id", None)
            or the_installation.get_environment("SOLIPLEX_WORKBENCH_SERVER_ID")
            or "default"
        )
        return WorkbenchScope(str(username), str(server_id), room_id, thread_id)

    @router.get("/rooms/{room_id}/threads/{thread_id}/workbench")
    async def snapshot(room_id: str, thread_id: str, request: Request, scope=Depends(scope_dependencies)):
        data = _repository_for(request, repository).load_snapshot(scope)
        return {
            "revision": data["revision"],
            "layout": data["layout"],
            "content": data["content"],
            "registrations": [
                {
                    "activityMessageId": item.get("activityMessageId"),
                    "surfaceId": item.get("surfaceId"),
                    "catalogId": item.get("catalogId"),
                    "component": item.get("component"),
                }
                for item in data["content"]
            ],
        }

    @router.post("/rooms/{room_id}/threads/{thread_id}/workbench/actions")
    async def action(room_id: str, thread_id: str, request: Request, scope=Depends(scope_dependencies)):
        raw_payload = await _read_request_json(request)
        try:
            body = ActionBody.model_validate(raw_payload)
            service = WorkbenchActionService(
                _repository_for(request, repository),
                trace_sink=trace_sink or getattr(request.app.state, "workbench_trace_sink", None),
            )
            return service.accept(scope, body.model_dump(mode="json"))
        except PublicationConflict as exc:
            raise HTTPException(409, str(exc)) from exc
        except (ValidationError, ValueError) as exc:
            raise HTTPException(422, "invalid workbench action") from exc

    @router.post("/rooms/{room_id}/threads/{thread_id}/workbench/actions/restore")
    async def restore(room_id: str, thread_id: str, request: Request, scope=Depends(scope_dependencies)):
        try:
            body = RestoreBody.model_validate(await _read_request_json(request))
            return _repository_for(request, repository).restore_node(scope, body.nodeId)
        except ValidationError as exc:
            raise HTTPException(422, "invalid workbench restore target") from exc
        except ValueError as exc:
            raise HTTPException(422, "invalid workbench restore target") from exc

    return router


def create_guarded_agui_router(agui_router=None, *, scope_provider: Callable | None = None, workbench_rooms: set[str] | None = None, lab_rooms: set[str] | None = None):
    """Guard only configured workbench execution runs; pass all other routes through."""
    from soliplex import agui, authz, installation, views
    from soliplex.views import agui as agui_views
    from soliplex.views.agui import router as default_agui_router

    upstream_router = agui_router or default_agui_router
    if workbench_rooms is None:
        configured = os.environ.get("SOLIPLEX_WORKBENCH_ROOMS", "")
        workbench_rooms = {room.strip() for room in configured.split(",") if room.strip()}
        if scope_provider is not None:
            # Explicit test seam: the supplied scope identifies the configured room.
            scope_value = scope_provider if isinstance(scope_provider, WorkbenchScope) else None
            if scope_value is None and hasattr(scope_provider, "room_id"):
                scope_value = scope_provider
            if scope_value is not None:
                workbench_rooms.add(scope_value.room_id)
    if lab_rooms is None:
        configured_labs = os.environ.get("SOLIPLEX_A2UI_LAB_ROOMS", "a2ui-lab,a2ui-lab-e4b")
        lab_rooms = {room.strip() for room in configured_labs.split(",") if room.strip()}

    def is_workbench_run(request: Request) -> bool:
        route = request.scope.get("route")
        route_path = getattr(route, "path", "")
        return (
            request.method == "POST"
            and request.path_params.get("room_id") in workbench_rooms
            and "thread_id" in request.path_params
            and "run_id" in request.path_params
            and route_path.endswith("/{run_id}")
        )

    def is_execution_run(request: Request) -> bool:
        route = request.scope.get("route")
        return (
            request.method == "POST"
            and "room_id" in request.path_params
            and "thread_id" in request.path_params
            and "run_id" in request.path_params
            and getattr(route, "path", "").endswith("/{run_id}")
        )

    async def authenticated_scope(
        request: Request,
        the_installation=installation.depend_the_installation,
        the_threads=agui.depend_the_threads,
        policy=views.depend_the_room_authz_policy,
        claims=views.depend_the_user_claims,
    ):
        if not is_workbench_run(request):
            return None
        room_id = request.path_params["room_id"]
        thread_id = request.path_params.get("thread_id")
        run_id = request.path_params.get("run_id")
        if thread_id is None:
            return None
        username = claims.get("preferred_username")
        if not username:
            raise HTTPException(401, "authenticated user required")
        parsed_replay = agui_views.parse_last_event_id(request.headers.get("last-event-id"))
        replay = parsed_replay is not None
        if replay:
            if run_id is None or parsed_replay[0] != run_id or parsed_replay[1] < 0:
                raise HTTPException(400, "Last-Event-ID does not identify this run")
        permission = authz.Permission.WRITE
        if not await policy.check_room_access(room_id, claims, permission=permission):
            raise HTTPException(403, "room access denied")
        try:
            await the_threads.get_thread(user_name=username, room_id=room_id, thread_id=thread_id)
            if replay:
                await the_threads.get_run(username, room_id, thread_id, run_id)
        except Exception as exc:
            raise HTTPException(404, "thread or run not found") from exc
        if replay:
            request.state.workbench_replay_authorized = True
        server_id = (
            getattr(the_installation, "server_id", None)
            or the_installation.get_environment("SOLIPLEX_WORKBENCH_SERVER_ID")
            or "default"
        )
        return WorkbenchScope(str(username), str(server_id), room_id, thread_id)

    async def test_scope(request: Request):
        if callable(scope_provider):
            value = scope_provider(request)
            if hasattr(value, "__await__"):
                value = await value
            return value
        return scope_provider

    scope_dependency = authenticated_scope if scope_provider is None else test_scope
    guarded = APIRouter()

    async def _validate_before_dispatch(request: Request, scope):
        if not is_execution_run(request):
            return
        if not is_workbench_run(request):
            room_id = request.path_params.get("room_id")
            legacy_payload = await _read_agui_json(request)
            _reject_client_workbench_fields(legacy_payload)
            forwarded_props = legacy_payload.get("forwardedProps")
            action_envelope = forwarded_props.get("a2uiAction") if isinstance(forwarded_props, dict) else None
            workbench_schemas = {"intake.submit@1", "workbench.program.export_chart@1", "workbench.program.run_result@1"}
            if action_envelope is not None and (
                room_id not in lab_rooms
                or (isinstance(action_envelope, dict) and action_envelope.get("actionSchemaVersion") in workbench_schemas)
            ):
                raise HTTPException(503, "workbench room is not configured in SOLIPLEX_WORKBENCH_ROOMS")
            if room_id not in lab_rooms:
                return
            if user_action(forwarded_props) is None:
                return
            messages = legacy_payload.get("messages")
            if not isinstance(messages, list):
                return
            try:
                message_adapter = TypeAdapter(Message)
                parsed_messages = [message_adapter.validate_python(item) for item in messages]
                projected_messages = with_user_action(parsed_messages, forwarded_props)
            except (TypeError, ValueError, ValidationError):
                return
            if len(projected_messages) != len(parsed_messages) or any(a != b for a, b in zip(projected_messages, parsed_messages)):
                legacy_payload["messages"] = [message.model_dump(mode="json", by_alias=True, exclude_none=True) for message in projected_messages]
                request._body = json.dumps(legacy_payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
            return
        header = request.headers.get("last-event-id")
        parsed_replay = agui_views.parse_last_event_id(header)
        if parsed_replay is not None:
            if (
                parsed_replay[1] < 0
                or parsed_replay[0] != request.path_params.get("run_id")
                or not getattr(request.state, "workbench_replay_authorized", scope_provider is not None)
            ):
                raise HTTPException(404, "replay run is not authorized")
            payload = await _read_agui_json(request)
            _reject_client_workbench_intake_tool(payload)
            if payload.get("threadId") != request.path_params.get("thread_id") or payload.get("runId") != request.path_params.get("run_id"):
                raise HTTPException(400, "AG-UI URL and body identifiers do not match")
            state = payload.get("state")
            props = payload.get("forwardedProps")
            if (isinstance(state, dict) and "workbenchAction" in state) or (isinstance(props, dict) and "a2uiAction" in props):
                raise HTTPException(422, "reconnect cannot carry a workbench action")
            if scope is None:
                raise HTTPException(403, "authenticated workbench scope required")
            await _validate_full_agui_request(request)
            _validate_issued_intake_history(payload, _repository_for(request, None).issued_intake_submissions(scope))
            return
        payload = await _read_agui_json(request)
        path_thread_id = request.path_params.get("thread_id")
        path_run_id = request.path_params.get("run_id")
        if payload.get("threadId") != path_thread_id or payload.get("runId") != path_run_id:
            raise HTTPException(400, "AG-UI URL and body identifiers do not match")
        state = payload.get("state")
        if state is not None and not isinstance(state, dict):
            raise HTTPException(422, "AG-UI state must be an object")
        if isinstance(state, dict) and "workbenchAction" in state:
            raise HTTPException(422, "workbenchAction is server-owned")
        if scope is None:
            raise HTTPException(403, "authenticated workbench scope required")
        _reject_client_workbench_intake_tool(payload)
        await _validate_full_agui_request(request)
        repository = _repository_for(request, None)
        _validate_issued_intake_history(payload, repository.issued_intake_submissions(scope))
        props = payload.get("forwardedProps")
        if not isinstance(props, dict) or "a2uiAction" not in props:
            return
        if not isinstance(props["a2uiAction"], dict) or "actionSchemaVersion" not in props["a2uiAction"]:
            raise HTTPException(422, "workbench rooms require a reserved workbench action envelope")
        messages = payload.get("messages")
        if not isinstance(messages, list):
            raise HTTPException(422, "AG-UI messages must be an array")
        context = WorkbenchActionService(repository).consume_dispatch(scope, {"forwardedProps": props})
        if context is None:
            raise HTTPException(409, "workbench action is not reserved or is not dispatchable")
        messages.extend(synthetic_intake_messages(context))
        # Soliplex 0.93's AGUIAdapter.from_request consumes Request.body().
        # Starlette Request caches those bytes after the strict JSON parse.
        request._body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        request.state.workbench_pending_submission_id = str(context.get("submissionId", ""))

    async def validate_before_dispatch(request: Request, scope=Depends(scope_dependency)):
        """Issue consumed reservations only after the stock handler returns successfully."""
        await _validate_before_dispatch(request, scope)
        try:
            yield
        except BaseException:
            # FastAPI sends endpoint and validation failures through dependency teardown.
            # Keep dispatching reservations unresolved when downstream did not accept them.
            raise
        else:
            submission_id = getattr(request.state, "workbench_pending_submission_id", None)
            if submission_id:
                repository = _repository_for(request, None)
                if not repository.mark_action_issued(scope, submission_id):
                    raise HTTPException(409, "workbench action handoff could not be recorded")

    guarded.include_router(upstream_router, dependencies=[Depends(validate_before_dispatch, scope="function")])
    return guarded


try:
    guarded_router = create_guarded_agui_router()
except ModuleNotFoundError as exc:
    if exc.name != "soliplex":
        raise
    guarded_router = APIRouter()
