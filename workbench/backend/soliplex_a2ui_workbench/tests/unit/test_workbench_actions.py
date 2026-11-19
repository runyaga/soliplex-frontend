from soliplex_a2ui_workbench.workbench_actions import WorkbenchActionService
from soliplex_a2ui_workbench.workbench_repository import SQLiteWorkbenchRepository, WorkbenchScope, PublicationConflict
import pytest
import json
from pathlib import Path
from fastapi import APIRouter, FastAPI, Request
from fastapi.testclient import TestClient
from soliplex_a2ui_workbench.workbench_routes import create_guarded_agui_router


def _register(repo, scope, component="PlaceForm"):
    fixture = Path(__file__).parents[1] / "fixtures/workbench"
    layout = json.loads((fixture / "layout_tree_v1.json").read_text())
    layout["nodes"][2]["children"] = ["panel_chart"]
    layout["nodes"].extend([
        {"id": "panel_chart", "parentId": "r_left", "children": ["surface_chart"], "kind": "panel", "title": "Chart", "size": "medium", "visibility": "open", "payload": {}},
        {"id": "surface_chart", "parentId": "panel_chart", "children": [], "kind": "surface", "title": "Chart", "size": "medium", "visibility": "open", "payload": {"activityMessageId": "activity-1", "surfaceId": "surface-1"}},
    ])
    content = json.loads((fixture / "content_v1.json").read_text())
    content.update({"activityMessageId": "activity-1", "surfaceId": "surface-1"})
    content["component"] = component
    repo.publish(scope, "initial", 0, layout, [content], registered_program_surfaces=set(), registered_mounts={("activity-1", "surface-1")})


def test_intake_reservation_is_idempotent_and_model_free(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    scope = WorkbenchScope("alice", "server", "room", "thread")
    _register(repo, scope)
    service = WorkbenchActionService(repo)
    payload = {
        "v": 1, "submissionId": "submission-1", "activityMessageId": "activity-1",
        "surfaceRevision": 1, "actionSchemaVersion": "intake-submit@1",
        "userAction": {"question": "Compare north and south", "districts": ["north", "south"], "acknowledged": True},
    }
    first = service.accept(scope, payload)
    second = service.accept(scope, payload)
    assert first == second
    assert first["status"] == "reserved"


def test_changed_duplicate_conflicts_and_unreserved_dispatch_rejects(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    service = WorkbenchActionService(repo)
    scope = WorkbenchScope("alice", "server", "room", "thread")
    assert service.consume_dispatch(scope, {"submissionId": "missing"}) is None


def test_dispatch_consumes_exact_reserved_envelope_once(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    scope = WorkbenchScope("alice", "server", "room", "thread")
    _register(repo, scope)
    service = WorkbenchActionService(repo)
    payload = {
        "v": 1, "submissionId": "submission-2", "activityMessageId": "activity-1",
        "surfaceRevision": 1, "actionSchemaVersion": "intake-submit@1",
        "userAction": {"question": "Compare these", "districts": ["north"], "acknowledged": True},
    }
    service.accept(scope, payload)
    run_input = {"forwardedProps": {"a2uiAction": payload}}
    assert service.consume_dispatch(scope, run_input) == payload
    assert service.consume_dispatch(scope, run_input) is None
    with pytest.raises(PublicationConflict):
        service.accept(scope, payload | {"surfaceRevision": 2})


def test_guarded_agui_route_replays_without_consuming_and_injects_typed_state(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    scope = WorkbenchScope("alice", "server", "room", "thread")
    _register(repo, scope)
    payload = {
        "v": 1, "submissionId": "submission-guard", "activityMessageId": "activity-1",
        "surfaceRevision": 1, "actionSchemaVersion": "intake-submit@1",
        "userAction": {"question": "Compare values", "districts": ["north"], "acknowledged": True},
    }
    WorkbenchActionService(repo).accept(scope, payload)
    upstream = APIRouter()

    @upstream.post("/v1/rooms/{room_id}/agui/{thread_id}/{run_id}")
    async def existing_agui(request: Request):
        # Soliplex's AGUIAdapter consumes Request.body() after the Depends guard.
        # This locks in the body-cache handoff used for the typed run state.
        return json.loads(await request.body())

    app = FastAPI()
    app.state.workbench_repository = repo
    app.include_router(create_guarded_agui_router(upstream, scope_provider=scope))
    client = TestClient(app)
    run_input = {"threadId": "thread", "runId": "run", "forwardedProps": {"a2uiAction": payload}}
    replay = client.post("/v1/rooms/room/agui/thread/run", json=run_input, headers={"Last-Event-ID": "run:0"})
    assert replay.status_code == 200
    assert "workbenchAction" not in replay.json().get("state", {})
    accepted = client.post("/v1/rooms/room/agui/thread/run", json=run_input)
    assert accepted.status_code == 200
    assert accepted.json()["state"]["workbenchAction"] == payload
    duplicate = client.post("/v1/rooms/room/agui/thread/run", json=run_input)
    assert duplicate.status_code == 409


def test_run_result_persists_client_trace_tags_without_model(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    scope = WorkbenchScope("alice", "server", "room", "thread")
    _register(repo, scope, "PythonRepl")
    service = WorkbenchActionService(repo)
    payload = {
        "v": 1, "submissionId": "result-submit-1", "activityMessageId": "activity-1",
        "surfaceRevision": 1, "actionSchemaVersion": "python-run-result@1",
        "userAction": {"side": "client", "engine": "monty-1.3.0", "invocationId": "invocation-1",
                        "chainId": "chain-1", "outcome": "success", "output": "125"},
    }
    receipt = service.accept(scope, payload)
    assert receipt["trace"] == {
        "python.side": "client", "python.engine": "monty-1.3.0", "room": "room",
        "thread": "thread", "surface": "surface-1", "chain_id": "chain-1",
        "invocation_id": "invocation-1",
    }
    duplicate = service.accept(scope, payload | {"submissionId": "result-submit-2"})
    assert duplicate == receipt
    changed = payload | {"submissionId": "result-submit-3", "userAction": payload["userAction"] | {"output": "forged"}}
    with pytest.raises(PublicationConflict):
        service.accept(scope, changed)
