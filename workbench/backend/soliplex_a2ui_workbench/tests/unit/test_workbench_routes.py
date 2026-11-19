from fastapi import FastAPI
from fastapi.testclient import TestClient
import json
from pathlib import Path

from soliplex_a2ui_workbench.workbench_repository import SQLiteWorkbenchRepository
from soliplex_a2ui_workbench.workbench_repository import WorkbenchScope
from soliplex_a2ui_workbench.workbench_routes import build_router


def test_snapshot_is_thread_scoped_and_passive(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    calls = []
    app = FastAPI()
    router = build_router(repository=repo, authorize=lambda *args: True)
    route = next(route for route in router.routes if route.path.endswith("/workbench"))
    app.include_router(router)
    client = TestClient(app)
    app.state.model = CapturingModel()
    app.dependency_overrides[route.dependant.dependencies[0].call] = lambda: WorkbenchScope("test-actor", "test-server", "room-a", "thread-a")
    response = client.get("/rooms/room-a/threads/thread-a/workbench")
    assert response.status_code == 200
    assert response.json() == {"revision": 0, "layout": None, "content": [], "registrations": []}
    assert calls == []
    assert app.state.model.calls == 0


def test_snapshot_denies_cross_thread_and_write_requires_permission(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    app = FastAPI()
    app.include_router(build_router(repository=repo, authorize=lambda *args: False))
    client = TestClient(app)
    assert client.get("/rooms/room-a/threads/thread-b/workbench").status_code == 403
    assert client.post("/rooms/room-a/threads/thread-b/workbench/actions", json={}).status_code == 403


def test_restore_route_updates_closed_node_without_model(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    app = FastAPI()
    router = build_router(repository=repo, authorize=lambda *args: True)
    route = next(route for route in router.routes if route.path.endswith("/actions/restore"))
    app.include_router(router)
    fixture = Path(__file__).parents[1] / "fixtures/workbench/layout_tree_v1.json"
    layout = json.loads(fixture.read_text())
    layout["nodes"][2]["children"] = ["panel_hidden"]
    layout["nodes"].append({"id": "panel_hidden", "parentId": "r_left", "children": [], "kind": "panel", "title": "Hidden", "size": "medium", "visibility": "open", "payload": {}})
    scope = WorkbenchScope("test-actor", "test-server", "room-a", "thread-a")
    repo.publish(scope, "initial", 0, layout, [], registered_program_surfaces=set(), registered_mounts=set())
    layout["layoutRevision"] = 2
    layout["nodes"][6]["visibility"] = "closed"
    repo.publish(scope, "close-left", 1, layout, [], registered_program_surfaces=set(), registered_mounts=set())
    app.state.model = CapturingModel()
    app.dependency_overrides[route.dependant.dependencies[0].call] = lambda: scope
    response = TestClient(app).post("/rooms/room-a/threads/thread-a/workbench/actions/restore", json={"nodeId": "panel_hidden"})
    assert response.status_code == 200
    assert repo.load(scope)["nodes"][6]["visibility"] == "open"
    assert app.state.model.calls == 0


class CapturingModel:
    def __init__(self):
        self.calls = 0

    def __call__(self, *_args, **_kwargs):
        self.calls += 1
        raise AssertionError("workbench hydration must not call a model")
