"""Test production scope dependencies with small in-memory Soliplex seams."""

import json
from pathlib import Path

from fastapi import APIRouter, FastAPI, HTTPException, Request
from fastapi.testclient import TestClient
from pydantic_ai import Agent
from pydantic_ai.models.test import TestModel
from pydantic_ai.ui.ag_ui import AGUIAdapter
from soliplex import agui, authz, installation, views

from soliplex_a2ui_workbench.workbench_actions import WorkbenchActionService
from soliplex_a2ui_workbench.workbench_repository import SQLiteWorkbenchRepository, WorkbenchScope
from soliplex_a2ui_workbench.workbench_routes import build_router, create_guarded_agui_router


class MemoryRoomPolicy:
    def __init__(self, permissions):
        self.permissions = permissions
        self.checks = []

    async def check_room_access(self, room_id, claims, *, permission):
        self.checks.append((room_id, claims["preferred_username"], permission))
        return (room_id, claims["preferred_username"], permission) in self.permissions


class MemoryThreadStorage:
    def __init__(self, owned=(), existing_runs=()):
        self.owned = set(owned)
        self.existing_runs = set(existing_runs)
        self.thread_checks = []
        self.run_checks = []

    async def get_thread(self, *, user_name, room_id, thread_id):
        key = (user_name, room_id, thread_id)
        self.thread_checks.append(key)
        if key not in self.owned:
            raise LookupError("thread owner mismatch")
        return {"thread_id": thread_id}

    async def get_run(self, user_name, room_id, thread_id, run_id):
        key = (user_name, room_id, thread_id, run_id)
        self.run_checks.append(key)
        if key not in self.existing_runs:
            raise LookupError("run not found")
        return {"run_id": run_id}


class MemoryInstallation:
    def get_environment(self, _key):
        return "server-a"


def _test_client(app, repo, policy, threads):
    app.state.workbench_repository = repo
    app.dependency_overrides[installation.depend_the_installation.dependency] = lambda: MemoryInstallation()
    app.dependency_overrides[agui.depend_the_threads.dependency] = lambda: threads
    app.dependency_overrides[views.depend_the_room_authz_policy.dependency] = lambda: policy
    app.dependency_overrides[views.depend_the_user_claims.dependency] = lambda: {"preferred_username": "alice"}
    return TestClient(app)


def test_production_scope_checks_room_write_permission(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    threads = MemoryThreadStorage({("alice", "room-a", "thread-a")})
    policy = MemoryRoomPolicy({("room-a", "alice", authz.Permission.READ)})
    app = FastAPI()
    app.include_router(build_router(repository=repo))
    response = _test_client(app, repo, policy, threads).post(
        "/rooms/room-a/threads/thread-a/workbench/actions/restore", json={"nodeId": "panel-a"}
    )
    assert response.status_code == 403
    assert policy.checks == [("room-a", "alice", authz.Permission.WRITE)]
    assert threads.thread_checks == []


def test_production_scope_checks_thread_ownership(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    threads = MemoryThreadStorage()  # Alice does not own this thread.
    policy = MemoryRoomPolicy({("room-a", "alice", authz.Permission.READ)})
    app = FastAPI()
    app.include_router(build_router(repository=repo))
    response = _test_client(app, repo, policy, threads).get("/rooms/room-a/threads/foreign-thread/workbench")
    assert response.status_code == 404
    assert policy.checks == [("room-a", "alice", authz.Permission.READ)]
    assert threads.thread_checks == [("alice", "room-a", "foreign-thread")]


def test_snapshot_loads_only_authenticated_actor_room_thread(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    scope = WorkbenchScope("alice", "server-a", "room-a", "thread-a")
    app = FastAPI()
    app.include_router(build_router(repository=repo))
    policy = MemoryRoomPolicy({("room-a", "alice", authz.Permission.READ)})
    threads = MemoryThreadStorage({("alice", "room-a", "thread-a")})
    response = _test_client(app, repo, policy, threads).get("/rooms/room-a/threads/thread-a/workbench")
    assert response.status_code == 200
    assert response.json()["revision"] == 0
    assert threads.thread_checks == [("alice", "room-a", "thread-a")]


def test_guard_runs_real_agui_adapter_only_after_authorized_intake(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    scope = WorkbenchScope("alice", "server-a", "room-a", "thread-a")
    layout = json.loads((Path(__file__).parents[1] / "fixtures/workbench/layout_tree_v1.json").read_text())
    layout["nodes"][2]["children"] = ["panel_form"]
    layout["nodes"].extend([
        {"id": "panel_form", "parentId": "r_left", "children": ["surface_form"], "kind": "panel", "title": "Intake", "size": "medium", "visibility": "open", "payload": {}},
        {"id": "surface_form", "parentId": "panel_form", "children": [], "kind": "surface", "title": "Intake", "size": "medium", "visibility": "open", "payload": {"activityMessageId": "activity-form", "surfaceId": "surface-form"}},
    ])
    record = {"activityMessageId": "activity-form", "surfaceId": "surface-form", "catalogId": "urn:soliplex:catalog:workbench:1", "component": "PlaceForm", "title": "Intake", "template": "intake"}
    repo.publish(scope, "initial", 0, layout, [record], registered_program_surfaces=set(), registered_mounts={("activity-form", "surface-form")})
    envelope = {"v": 1, "submissionId": "sub-1", "activityMessageId": "activity-form", "surfaceRevision": 1, "actionSchemaVersion": "intake.submit@1", "userAction": {"question": "Compare", "districts": ["north"], "acknowledged": True}}
    WorkbenchActionService(repo).accept(scope, envelope)
    handler_entries = []
    upstream = APIRouter()

    @upstream.post("/v1/rooms/{room_id}/agui/{thread_id}/{run_id}")
    async def stock_adapter_boundary(request: Request):
        handler_entries.append("entered")
        adapter = await AGUIAdapter.from_request(request, agent=Agent(TestModel()))
        return {"state": adapter.run_input.state}

    app = FastAPI()
    app.state.workbench_repository = repo
    app.include_router(create_guarded_agui_router(upstream))
    policy = MemoryRoomPolicy({("room-a", "alice", authz.Permission.WRITE)})
    threads = MemoryThreadStorage({("alice", "room-a", "thread-a")})
    client = _test_client(app, repo, policy, threads)
    payload = {"threadId": "thread-a", "runId": "run-a", "state": {}, "messages": [], "tools": [], "context": [], "forwardedProps": {"a2uiAction": envelope}}
    response = client.post("/v1/rooms/room-a/agui/thread-a/run-a", json=payload)
    assert response.status_code == 200
    assert response.json()["state"]["workbenchAction"] == envelope
    assert handler_entries == ["entered"]
    assert policy.checks == [("room-a", "alice", authz.Permission.WRITE)]
    assert threads.thread_checks == [("alice", "room-a", "thread-a")]
    duplicate = client.post("/v1/rooms/room-a/agui/thread-a/run-b", json={**payload, "runId": "run-b"})
    assert duplicate.status_code == 409
    assert handler_entries == ["entered"]


def test_guard_authenticates_valid_reconnect_and_checks_run_exists(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    upstream = APIRouter()

    @upstream.post("/v1/rooms/{room_id}/agui/{thread_id}/{run_id}")
    async def handler(request: Request):
        return {"ok": True}

    app = FastAPI()
    app.state.workbench_repository = repo
    app.include_router(create_guarded_agui_router(upstream))
    policy = MemoryRoomPolicy({("room-a", "alice", authz.Permission.READ)})
    threads = MemoryThreadStorage({("alice", "room-a", "thread-a")}, {("alice", "room-a", "thread-a", "run-a")})
    client = _test_client(app, repo, policy, threads)
    response = client.post("/v1/rooms/room-a/agui/thread-a/run-a", headers={"Last-Event-ID": "run-a:0"})
    assert response.status_code == 200
    assert threads.thread_checks == [("alice", "room-a", "thread-a")]
    assert threads.run_checks == [("alice", "room-a", "thread-a", "run-a")]
    assert policy.checks == [("room-a", "alice", authz.Permission.READ)]
