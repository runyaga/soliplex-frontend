"""Test production scope dependencies with small in-memory Soliplex seams."""

import json
from pathlib import Path

import pytest
from fastapi import APIRouter, FastAPI, Request
from fastapi.testclient import TestClient
from soliplex import agui, authz, installation, views
from soliplex_a2ui_workbench.workbench_repository import (
    SQLiteWorkbenchRepository,
    WorkbenchScope,
)
from soliplex_a2ui_workbench.workbench_routes import (
    build_router,
    create_guarded_agui_router,
)


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
    app.include_router(build_router(repository=repo, workbench_rooms={"room-a"}))
    response = _test_client(app, repo, policy, threads).post(
        "/v1/rooms/room-a/threads/thread-a/workbench/actions/restore", json={"nodeId": "panel-a"}
    )
    assert response.status_code == 403
    assert policy.checks == [("room-a", "alice", authz.Permission.WRITE)]
    assert threads.thread_checks == []


def test_workbench_routes_fail_closed_when_room_is_not_configured(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    app = FastAPI()
    app.include_router(build_router(repository=repo, workbench_rooms=set()))
    policy = MemoryRoomPolicy(set())
    threads = MemoryThreadStorage()
    response = _test_client(app, repo, policy, threads).get("/v1/rooms/unlisted/threads/thread-a/workbench")
    assert response.status_code == 503
    assert response.json()["detail"] == "workbench room is not configured in SOLIPLEX_WORKBENCH_ROOMS"


def test_production_scope_checks_thread_ownership(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    threads = MemoryThreadStorage()  # Alice does not own this thread.
    policy = MemoryRoomPolicy({("room-a", "alice", authz.Permission.READ)})
    app = FastAPI()
    app.include_router(build_router(repository=repo, workbench_rooms={"room-a"}))
    response = _test_client(app, repo, policy, threads).get("/v1/rooms/room-a/threads/foreign-thread/workbench")
    assert response.status_code == 404
    assert policy.checks == [("room-a", "alice", authz.Permission.READ)]
    assert threads.thread_checks == [("alice", "room-a", "foreign-thread")]


def test_snapshot_loads_only_authenticated_actor_room_thread(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    scope = WorkbenchScope("alice", "server-a", "room-a", "thread-a")
    layout = json.loads((Path(__file__).parents[1] / "fixtures/workbench/layout_tree_v1.json").read_text())
    layout["layoutRevision"] = 1
    record = {"activityMessageId": "only-thread-a", "surfaceId": "surface-a", "catalogId": "urn:soliplex:catalog:lab:1", "component": "PythonRepl", "source": "print('a')"}
    repo.publish(scope, "seed-a", 0, layout, [record], registered_program_surfaces=set(), registered_mounts={("only-thread-a", "surface-a")})
    other_scope = WorkbenchScope("alice", "server-a", "room-a", "thread-b")
    other_record = record | {"activityMessageId": "only-thread-b", "surfaceId": "surface-b"}
    repo.publish(other_scope, "seed-b", 0, layout, [other_record], registered_program_surfaces=set(), registered_mounts={("only-thread-b", "surface-b")})
    app = FastAPI()
    app.include_router(build_router(repository=repo, workbench_rooms={"room-a"}))
    policy = MemoryRoomPolicy({("room-a", "alice", authz.Permission.READ)})
    threads = MemoryThreadStorage({("alice", "room-a", "thread-a")})
    response = _test_client(app, repo, policy, threads).get("/v1/rooms/room-a/threads/thread-a/workbench")
    assert response.status_code == 200
    assert response.json()["revision"] == 1
    assert [item["content"]["activityMessageId"] for item in response.json()["records"]] == ["only-thread-a"]
    assert response.json()["records"][0]["content"]["source"] == "print('a')"
    assert threads.thread_checks == [("alice", "room-a", "thread-a")]


def test_restore_route_restores_owned_closed_layout_node(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    scope = WorkbenchScope("alice", "server-a", "room-a", "thread-a")
    layout = json.loads((Path(__file__).parents[1] / "fixtures/workbench/layout_tree_v1.json").read_text())
    layout["nodes"][2]["children"] = ["panel-closed"]
    layout["nodes"].append({"id": "panel-closed", "parentId": "r_left", "children": [], "kind": "panel", "title": "Closed", "size": "small", "visibility": "closed", "payload": {}})
    repo.publish(scope, "closed", 0, layout, [], registered_program_surfaces=set(), registered_mounts=set())
    app = FastAPI()
    app.include_router(build_router(repository=repo, workbench_rooms={"room-a"}))
    policy = MemoryRoomPolicy({("room-a", "alice", authz.Permission.WRITE)})
    threads = MemoryThreadStorage({("alice", "room-a", "thread-a")})
    response = _test_client(app, repo, policy, threads).post(
        "/v1/rooms/room-a/threads/thread-a/workbench/actions/restore", json={"nodeId": "panel-closed"}
    )
    assert response.status_code == 200
    assert response.json() == {"status": "restored", "nodeId": "panel-closed", "revision": 2, "sequence": 2}
    assert next(node for node in repo.load_snapshot(scope)["layout"]["nodes"] if node["id"] == "panel-closed")["visibility"] == "open"
    assert policy.checks == [("room-a", "alice", authz.Permission.WRITE)]
    assert threads.thread_checks == [("alice", "room-a", "thread-a")]


def test_non_run_stock_agui_routes_and_legacy_room_payload_pass_through_unchanged():
    from soliplex.views.agui import router as stock_router
    class Logger:
        def debug(self, *_args, **_kwargs): pass
        def info(self, *_args, **_kwargs): pass
        def error(self, *_args, **_kwargs): pass

    class StockInstallation(MemoryInstallation):
        async def get_room_config(self, **_kwargs): return object()

    class StockThreads:
        def __init__(self): self.calls = []
        async def update_thread_metadata(self, **kwargs): self.calls.append(("metadata", kwargs))
        async def new_run(self, **kwargs):
            self.calls.append(("new_run", kwargs))
            raise agui.UnknownThread(kwargs["user_name"], kwargs["thread_id"])
        async def set_thread_labels(self, **kwargs):
            self.calls.append(("labels", kwargs))
            raise agui.UnknownThread(kwargs["user_name"], kwargs["thread_id"])

    app = FastAPI()
    app.include_router(create_guarded_agui_router(stock_router, workbench_rooms={"workbench-room"}))
    threads = StockThreads()
    app.dependency_overrides[installation.depend_the_installation.dependency] = lambda: StockInstallation()
    app.dependency_overrides[agui.depend_the_threads.dependency] = lambda: threads
    app.dependency_overrides[views.depend_the_room_authz_policy.dependency] = lambda: object()
    app.dependency_overrides[views.depend_the_user_claims.dependency] = lambda: {"preferred_username": "alice"}
    app.dependency_overrides[views.depend_the_logger.dependency] = lambda: Logger()
    client = TestClient(app)
    thread_id = "11111111-1111-4111-8111-111111111111"
    run = client.post(f"/v1/rooms/workbench-room/agui/{thread_id}", json={})
    metadata = client.post(f"/v1/rooms/workbench-room/agui/{thread_id}/meta", json={})
    labels = client.post(f"/v1/rooms/workbench-room/agui/{thread_id}/labels", json={"label_ids": [1]})
    assert run.status_code == 404
    assert metadata.status_code == 205
    assert labels.status_code == 404
    assert [kind for kind, _ in threads.calls] == ["new_run", "metadata", "labels"]

    legacy = {"threadId": "legacy-thread", "runId": "legacy-run", "state": {}, "messages": [], "tools": [], "context": [], "forwardedProps": {"a2uiAction": {"actionSchemaVersion": "python_failed@1", "afterMessageId": "old-message", "userAction": {"name": "python_failed", "output": "failed"}}}}
    upstream = APIRouter()
    seen = []

    @upstream.post("/v1/rooms/{room_id}/agui/{thread_id}/{run_id}")
    async def downstream(request: Request):
        body = await request.body()
        seen.append(body)
        return {"body": body.decode()}

    legacy_app = FastAPI()
    legacy_app.include_router(create_guarded_agui_router(upstream, scope_provider=lambda _request: None, workbench_rooms={"workbench-room"}))
    raw_legacy = json.dumps(legacy, separators=(",", ":")).encode()
    response = TestClient(legacy_app).post("/v1/rooms/a2ui-lab/agui/legacy-thread/legacy-run", content=raw_legacy, headers={"content-type": "application/json"})
    assert response.status_code == 200
    assert seen == [raw_legacy]


@pytest.mark.parametrize("replay", [False, True])
def test_activity_tool_turn_and_reconnect_never_open_legacy_repository(monkeypatch, replay):
    from soliplex_a2ui_workbench import workbench_routes
    monkeypatch.setattr(workbench_routes, "shared_repository", lambda: pytest.fail("legacy SQLite opened"))
    upstream = APIRouter()
    @upstream.post("/v1/rooms/{room_id}/agui/{thread_id}/{run_id}")
    async def handler():
        return {"ok": True}
    app = FastAPI()
    scope = WorkbenchScope("alice", "server", "room", "thread")
    app.include_router(create_guarded_agui_router(upstream, scope_provider=scope, workbench_rooms={"room"}))
    response = TestClient(app).post(
        "/v1/rooms/room/agui/thread/run",
        json={"threadId": "thread", "runId": "run", "state": {}, "messages": [{"id": "user", "role": "user", "content": "Place a form"}], "tools": [], "context": [], "forwardedProps": {}},
        headers={"Last-Event-ID": "run:0"} if replay else {},
    )
    assert response.status_code == 200, response.text
    assert response.json() == {"ok": True}


def test_program_files_use_authenticated_thread_and_write_permission(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / 'repo.sqlite')
    threads = MemoryThreadStorage({('alice', 'room-a', 'thread-a')})
    policy = MemoryRoomPolicy({('room-a', 'alice', authz.Permission.WRITE), ('room-a', 'alice', authz.Permission.READ)})
    app = FastAPI()
    app.include_router(build_router(repository=repo, workbench_rooms={'room-a'}))
    client = _test_client(app, repo, policy, threads)
    install = MemoryInstallation()
    install.sandbox_workdirs_path = tmp_path / 'files'
    app.dependency_overrides[installation.depend_the_installation.dependency] = lambda: install
    from soliplex_a2ui_workbench.program_files import MAX_BYTES, MAX_REQUEST_BYTES
    base = '/v1/rooms/room-a/threads/thread-a/workbench/files/'
    assert client.post(base + 'write', json={'filename': 'notes.md', 'text': 'saved'}).json() == {'saved': True}
    assert client.post(base + 'read', json={'filename': 'notes.md'}).json() == {'text': 'saved'}
    assert client.post(base + 'write', json={'filename': '../secret.md', 'text': 'bad'}).status_code == 422
    assert client.post(base + 'write', json={'filename': 'notes.md', 'text': 'x' * (MAX_REQUEST_BYTES + 1)}).status_code == 413
    assert client.post(base + 'write', json={'filename': 'notes.md', 'text': 'x' * (MAX_BYTES + 1)}).status_code == 422
    payload = '\0' * MAX_BYTES
    assert client.post(base + 'write', json={'filename': 'full.txt', 'text': payload}).json() == {'saved': True}
    assert client.post(base + 'read', json={'filename': 'full.txt'}).json() == {'text': payload}
    foreign = base.replace('thread-a', 'foreign')
    assert client.post(foreign + 'read', json={'filename': 'notes.md'}).status_code == 404
    policy.permissions = {('room-a', 'alice', authz.Permission.READ)}
    assert client.post(base + 'read', json={'filename': 'notes.md'}).json() == {'text': 'saved'}
    assert client.post(base + 'write', json={'filename': 'notes.md', 'text': 'bad'}).status_code == 403
    def anonymous_claims():
        return {}

    app.dependency_overrides[views.depend_the_user_claims.dependency] = anonymous_claims
    assert client.post(base + 'read', json={'filename': 'notes.md'}).status_code == 401
