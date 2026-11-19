"""Authenticated room/thread workbench routes and guarded AG-UI dispatch."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Callable

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, ValidationError

from .strict_json import DuplicateJSONKey, parse_json_no_duplicates
from .workbench_actions import WorkbenchActionService
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


def build_router(*, repository: SQLiteWorkbenchRepository | None = None, trace_sink=None) -> APIRouter:
    """Build routes with the installed Soliplex 0.93 public dependencies."""
    from soliplex import agui, authz, installation, views

    router = APIRouter()

    async def scope_dependencies(
        room_id: str,
        thread_id: str,
        request: Request,
        the_installation=installation.depend_the_installation,
        the_threads=agui.depend_the_threads,
        policy=views.depend_the_room_authz_policy,
        claims=views.depend_the_user_claims,
    ) -> WorkbenchScope:
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


def create_guarded_agui_router(agui_router=None, *, scope_provider: Callable | None = None):
    """Mount existing AG-UI endpoints behind authenticated request validation."""
    from soliplex import agui, authz, installation, views
    from soliplex.views import agui as agui_views
    from soliplex.views.agui import router as default_agui_router

    upstream_router = agui_router or default_agui_router

    async def authenticated_scope(
        request: Request,
        the_installation=installation.depend_the_installation,
        the_threads=agui.depend_the_threads,
        policy=views.depend_the_room_authz_policy,
        claims=views.depend_the_user_claims,
    ):
        if request.method != "POST" or "room_id" not in request.path_params:
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
        permission = authz.Permission.READ if replay else authz.Permission.WRITE
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

    async def validate_before_dispatch(request: Request, scope=Depends(scope_dependency)):
        if request.method != "POST" or "room_id" not in request.path_params:
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
            return
        payload = await _read_request_json(request)
        path_thread_id = request.path_params.get("thread_id")
        path_run_id = request.path_params.get("run_id")
        if payload.get("threadId") != path_thread_id or payload.get("runId") != path_run_id:
            raise HTTPException(400, "AG-UI URL and body identifiers do not match")
        state = payload.get("state")
        if state is not None and not isinstance(state, dict):
            raise HTTPException(422, "AG-UI state must be an object")
        if isinstance(state, dict) and "workbenchAction" in state:
            raise HTTPException(422, "workbenchAction is server-owned")
        props = payload.get("forwardedProps")
        if not isinstance(props, dict) or "a2uiAction" not in props:
            return
        if scope is None:
            raise HTTPException(403, "authenticated workbench scope required")
        if not isinstance(props["a2uiAction"], dict):
            raise HTTPException(422, "invalid workbench action")
        repository = _repository_for(request, None)
        context = WorkbenchActionService(repository).consume_dispatch(scope, {"forwardedProps": props})
        if context is None:
            raise HTTPException(409, "workbench action is not reserved or is not dispatchable")
        run_state = dict(state or {})
        run_state["workbenchAction"] = context
        payload["state"] = run_state
        # Soliplex 0.93's AGUIAdapter.from_request consumes Request.body().
        # Starlette Request caches those bytes after the strict JSON parse.
        request._body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")

    guarded.include_router(upstream_router, dependencies=[Depends(validate_before_dispatch)])
    return guarded


try:
    guarded_router = create_guarded_agui_router()
except ModuleNotFoundError as exc:
    if exc.name != "soliplex":
        raise
    guarded_router = APIRouter()
