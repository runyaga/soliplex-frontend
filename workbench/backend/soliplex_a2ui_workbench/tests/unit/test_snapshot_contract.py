"""The snapshot route emits exactly the frozen client contract."""
import json
import pathlib

import pytest

pytest.importorskip("soliplex")

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

FIXTURES = pathlib.Path(__file__).parents[1] / "fixtures/workbench"


def _client(tmp_path):
    from soliplex import agui, installation, views
    from soliplex_a2ui_workbench.workbench_repository import SQLiteWorkbenchRepository
    from soliplex_a2ui_workbench.workbench_routes import build_router

    repo = SQLiteWorkbenchRepository(tmp_path / "wb.sqlite3")
    app = FastAPI()
    app.include_router(build_router(repository=repo, workbench_rooms={"workbench"}))

    class Policy:
        async def check_room_access(self, room, claims, *, permission):
            return True

    class Threads:
        async def get_thread(self, *, user_name, room_id, thread_id):
            return object()

    app.dependency_overrides[installation.depend_the_installation.dependency] = lambda: type(
        "I", (), {"get_environment": lambda self, key: "server"})()
    app.dependency_overrides[agui.depend_the_threads.dependency] = lambda: Threads()
    app.dependency_overrides[views.depend_the_room_authz_policy.dependency] = lambda: Policy()
    app.dependency_overrides[views.depend_the_user_claims.dependency] = lambda: {"preferred_username": "alice"}
    return TestClient(app), repo


def test_fresh_thread_snapshot_equals_fixture(tmp_path) -> None:
    client, _ = _client(tmp_path)
    response = client.get("/v1/rooms/workbench/threads/t1/workbench")
    assert response.status_code == 200
    assert response.json() == json.loads((FIXTURES / "snapshot_fresh_v1.json").read_text())


def test_content_snapshot_has_the_fixture_shape_and_consistent_parts(tmp_path) -> None:
    from soliplex_a2ui_workbench.workbench_context import WorkbenchToolContext
    from soliplex_a2ui_workbench.workbench_repository import WorkbenchScope
    from soliplex_a2ui_workbench.workbench_templates import MINIMUM_ROOM_TOOLS

    client, repo = _client(tmp_path)
    ctx = WorkbenchToolContext(WorkbenchScope("alice", "server", "workbench", "t1"), repo, "run-1",
                               allowed_rooms=frozenset({"workbench"}))
    MINIMUM_ROOM_TOOLS["place_form"].function(ctx, title="Intake", template="intake", parent_id="r_left")
    MINIMUM_ROOM_TOOLS["show_chart"].function(ctx, title="Counts", kind="bar",
                                              points=[{"id": "north", "label": "North", "value": 80}],
                                              parent_id="r_canvas")
    body = client.get("/v1/rooms/workbench/threads/t1/workbench").json()
    fixture = json.loads((FIXTURES / "snapshot_content_v1.json").read_text())
    assert set(body) == set(fixture) == {"revision", "layout", "registrations", "records"}
    assert [r["role"] for r in body["registrations"]] == [r["role"] for r in fixture["registrations"]]
    for record_id in {r["recordId"] for r in body["records"]}:
        parts = [r for r in body["records"] if r["recordId"] == record_id]
        assert sorted(p["partIndex"] for p in parts) == list(range(parts[0]["partCount"]))
        assert len({p["sequence"] for p in parts}) == 1
