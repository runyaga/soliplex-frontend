"""Authenticated room/thread snapshot and workbench action API."""

from __future__ import annotations

from typing import Callable
import os
import json
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict

from .workbench_actions import WorkbenchActionService
from .workbench_repository import SQLiteWorkbenchRepository, WorkbenchScope, PublicationConflict


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


def build_router(*, repository: SQLiteWorkbenchRepository | None = None, authorize: Callable | None = None) -> APIRouter:
    """Build a router; ``authorize`` is a small override seam for TestClient."""
    router = APIRouter()
    def get_repository(request: Request) -> SQLiteWorkbenchRepository:
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
    if authorize is None:
        from soliplex import agui, authz, installation, views

        async def scope_dependencies(room_id: str, thread_id: str, request: Request,
                                     the_installation=installation.depend_the_installation,
                                     the_threads=agui.depend_the_threads,
                                     policy=views.depend_the_room_authz_policy,
                                     claims=views.depend_the_user_claims):
            username = claims.get("preferred_username")
            if not username:
                raise HTTPException(401, "authenticated user required")
            permission = authz.Permission.WRITE if request.method == "POST" else authz.Permission.READ
            allowed = await policy.check_room_access(room_id, claims, permission=permission)
            if not allowed:
                raise HTTPException(403, "room access denied")
            try:
                await the_threads.get_thread(user_name=username, room_id=room_id, thread_id=thread_id)
            except Exception as exc:
                raise HTTPException(404, "thread not found") from exc
            server = getattr(the_installation, "server_id", None) or getattr(the_installation, "name", None) or "default"
            return WorkbenchScope(str(username), str(server), room_id, thread_id)
    else:
        async def scope_dependencies(room_id: str, thread_id: str, request: Request):
            permission = "write" if request.method == "POST" else "read"
            try:
                allowed = authorize(room_id, thread_id, permission)
                if hasattr(allowed, "__await__"):
                    allowed = await allowed
            except TypeError:
                allowed = authorize(room_id=room_id, thread_id=thread_id, permission=permission)
                if hasattr(allowed, "__await__"):
                    allowed = await allowed
            if not allowed:
                raise HTTPException(403, "room/thread access denied")
            return WorkbenchScope("test-actor", "test-server", room_id, thread_id)

    @router.get("/rooms/{room_id}/threads/{thread_id}/workbench")
    async def snapshot(room_id: str, thread_id: str, request: Request, scope=Depends(scope_dependencies)):
        data = get_repository(request).load_snapshot(scope)
        return {"revision": data["revision"], "layout": data["layout"], "content": data["content"],
                "registrations": [{"activityMessageId": item.get("activityMessageId"),
                                   "surfaceId": item.get("surfaceId"), "catalogId": item.get("catalogId"),
                                   "component": item.get("component")} for item in data["content"]]}

    @router.post("/rooms/{room_id}/threads/{thread_id}/workbench/actions")
    async def action(room_id: str, thread_id: str, request: Request, body: ActionBody, scope=Depends(scope_dependencies)):
        try:
            receipt = WorkbenchActionService(get_repository(request)).accept(scope, body.model_dump(mode="json"))
        except PublicationConflict as exc:
            raise HTTPException(409, str(exc)) from exc
        except (ValueError, Exception) as exc:
            # Pydantic validation errors are input errors; repository failures remain server errors.
            from pydantic import ValidationError
            if isinstance(exc, (ValueError, ValidationError)):
                raise HTTPException(422, "invalid workbench action") from exc
            raise
        return receipt

    @router.post("/rooms/{room_id}/threads/{thread_id}/workbench/actions/restore")
    async def restore(room_id: str, thread_id: str, request: Request, body: RestoreBody, scope=Depends(scope_dependencies)):
        try:
            return get_repository(request).restore_node(scope, body.nodeId)
        except ValueError as exc:
            raise HTTPException(422, "invalid workbench restore target") from exc

    return router


def create_guarded_agui_router(agui_router=None, *, scope_provider=None):
    """Return the existing AG-UI routes behind request-stage reservation checks."""
    if agui_router is None or scope_provider is None:
        from soliplex import agui, authz, installation, views
        from soliplex.views.agui import router as default_agui_router
        agui_router = agui_router or default_agui_router

        async def authenticated_scope(request: Request,
                                     the_installation=installation.depend_the_installation,
                                     the_threads=agui.depend_the_threads,
                                     policy=views.depend_the_room_authz_policy,
                                     claims=views.depend_the_user_claims):
            if request.headers.get("last-event-id") or request.method != "POST" or "/agui/" not in request.url.path or request.url.path.endswith(("/meta", "/feedback")):
                return None
            parts = [part for part in request.url.path.split("/") if part]
            try:
                room_id = parts[parts.index("rooms") + 1]
                thread_id = parts[parts.index("agui") + 1]
            except (IndexError, ValueError):
                raise HTTPException(400, "invalid AG-UI scope") from None
            username = claims.get("preferred_username")
            if not username:
                raise HTTPException(401, "authenticated user required")
            if not await policy.check_room_access(room_id, claims, permission=authz.Permission.WRITE):
                raise HTTPException(403, "room write access denied")
            try:
                await the_threads.get_thread(user_name=username, room_id=room_id, thread_id=thread_id)
            except Exception as exc:
                raise HTTPException(404, "thread not found") from exc
            server = getattr(the_installation, "server_id", None) or getattr(the_installation, "name", None) or "default"
            return WorkbenchScope(str(username), str(server), room_id, thread_id)
    else:
        async def authenticated_scope():
            return scope_provider

    guarded = APIRouter()

    async def validate_before_dispatch(request: Request, scope=Depends(authenticated_scope)):
        # Reconnect is a pure event replay; it does not consume the reservation.
        if request.headers.get("last-event-id"):
            return
        if request.method != "POST" or "/agui/" not in request.url.path or request.url.path.endswith(("/meta", "/feedback")):
            return
        try:
            payload = await request.json()
        except Exception:
            return
        props = payload.get("forwardedProps") if isinstance(payload, dict) else None
        if not isinstance(props, dict) or "a2uiAction" not in props:
            return
        envelope = props["a2uiAction"]
        if not isinstance(envelope, dict):
            raise HTTPException(422, "invalid workbench action")
        parts = [part for part in request.url.path.split("/") if part]
        try:
            thread_id = parts[parts.index("agui") + 1]
            run_id = parts[parts.index("agui") + 2]
        except (IndexError, ValueError):
            raise HTTPException(400, "invalid AG-UI scope") from None
        if payload.get("threadId") != thread_id or payload.get("runId") != run_id:
            raise HTTPException(400, "AG-UI URL and body identifiers do not match")
        if scope is None:
            raise HTTPException(403, "authenticated workbench scope required")
        repository = getattr(request.app.state, "workbench_repository", None)
        if repository is None:
            path = Path(os.environ.get("SOLIPLEX_WORKBENCH_DB", "/data/workbench/workbench.sqlite3"))
            path.parent.mkdir(parents=True, exist_ok=True)
            repository = SQLiteWorkbenchRepository(path)
            request.app.state.workbench_repository = repository
        run_state = payload.get("state")
        if run_state is None:
            run_state = {}
        if not isinstance(run_state, dict):
            raise HTTPException(422, "AG-UI state must be an object")
        try:
            context = WorkbenchActionService(repository).consume_dispatch(scope, {"forwardedProps": props})
        except (ValueError, PublicationConflict) as exc:
            raise HTTPException(422, "invalid or unresolved workbench action") from exc
        if context is None:
            raise HTTPException(409, "workbench action is not reserved or was already dispatched")
        request.state.workbench_action = context
        # Soliplex 0.93 creates AgentDependencies.state from the AG-UI run
        # input after this dependency returns. Put the accepted typed value in
        # that state; this is not a transcript message and invokes no reader
        # outside this package. The handler's adapter reads Request.body().
        run_state["workbenchAction"] = context
        payload["state"] = run_state
        request._body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")

    guarded.include_router(agui_router, dependencies=[Depends(validate_before_dispatch)])
    return guarded


try:
    guarded_router = create_guarded_agui_router()
except ModuleNotFoundError as exc:
    if exc.name != "soliplex":
        raise
    guarded_router = APIRouter()
