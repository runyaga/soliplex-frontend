from soliplex_a2ui_workbench.workbench_actions import WorkbenchActionService, synthetic_intake_messages
from soliplex_a2ui_workbench.workbench_repository import SQLiteWorkbenchRepository, WorkbenchScope, PublicationConflict
import pytest
import json
from pathlib import Path
from fastapi import APIRouter, FastAPI, Request
from fastapi.testclient import TestClient
from soliplex_a2ui_workbench.workbench_routes import create_guarded_agui_router
from pydantic_ai import Agent
from pydantic_ai.models.test import TestModel
from pydantic_ai.ui.ag_ui import AGUIAdapter


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
    if component == "PlaceForm":
        content.update({"catalogId": "urn:soliplex:catalog:workbench:1", "title": "Intake", "template": "intake"})
        content.pop("spec", None)
    else:
        content.update({"catalogId": "urn:soliplex:catalog:lab:1", "source": "print('idle')"})
        content.pop("spec", None)
    repo.publish(scope, "initial", 0, layout, [content], registered_program_surfaces=set(), registered_mounts={("activity-1", "surface-1")})


def test_intake_reservation_is_idempotent_and_model_free(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    scope = WorkbenchScope("alice", "server", "room", "thread")
    _register(repo, scope)
    service = WorkbenchActionService(repo)
    payload = {
        "v": 1, "submissionId": "submission-1", "activityMessageId": "activity-1",
        "surfaceRevision": 1, "actionSchemaVersion": "intake.submit@1",
        "userAction": {"question": "Compare north and south", "districts": ["north", "south"], "acknowledged": True},
    }
    first = service.accept(scope, payload)
    second = service.accept(scope, payload)
    assert first == second
    assert first["status"] == "reserved"


def test_synthetic_intake_tool_pair_ids_are_stable_for_reservation():
    envelope = {
        "submissionId": "stable-submit-1",
        "actionSchemaVersion": "intake.submit@1",
        "userAction": {"question": "Q", "districts": ["north"], "acknowledged": True},
    }
    first = synthetic_intake_messages(envelope)
    second = synthetic_intake_messages(envelope)
    assert first == second
    assert first[0]["toolCalls"][0]["id"] == first[1]["toolCallId"]
    changed = synthetic_intake_messages(envelope | {
        "submissionId": "stable-submit-2",
        "userAction": envelope["userAction"] | {"question": "Different question"},
    })
    assert changed[0]["toolCalls"][0]["id"] != first[0]["toolCalls"][0]["id"]
    assert changed[1]["id"] != first[1]["id"]
    assert changed[1]["content"] != first[1]["content"]
    assert "Different question" in changed[1]["content"]


def test_changed_duplicate_conflicts_and_unreserved_dispatch_rejects(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    service = WorkbenchActionService(repo)
    scope = WorkbenchScope("alice", "server", "room", "thread")
    assert service.consume_dispatch(scope, {"forwardedProps": {"a2uiAction": {"submissionId": "missing", "actionSchemaVersion": "intake.submit@1"}}}) is None
    _register(repo, scope)
    payload = {
        "v": 1, "submissionId": "changed-1", "activityMessageId": "activity-1",
        "surfaceRevision": 1, "actionSchemaVersion": "intake.submit@1",
        "userAction": {"question": "Compare", "districts": ["north"], "acknowledged": True},
    }
    service.accept(scope, payload)
    with pytest.raises(PublicationConflict):
        service.accept(scope, payload | {"userAction": {"question": "Changed", "districts": ["north"], "acknowledged": True}})


def test_dispatch_consumes_exact_reserved_envelope_once(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    scope = WorkbenchScope("alice", "server", "room", "thread")
    _register(repo, scope)
    service = WorkbenchActionService(repo)
    payload = {
        "v": 1, "submissionId": "submission-2", "activityMessageId": "activity-1",
        "surfaceRevision": 1, "actionSchemaVersion": "intake.submit@1",
        "userAction": {"question": "Compare these", "districts": ["north"], "acknowledged": True},
    }
    service.accept(scope, payload)
    run_input = {"forwardedProps": {"a2uiAction": payload}}
    assert service.consume_dispatch(scope, run_input) == payload
    assert service.consume_dispatch(scope, run_input) is None
    with pytest.raises(PublicationConflict):
        service.accept(scope, payload | {"surfaceRevision": 2})


def test_guarded_agui_route_replays_without_consuming_and_adds_synthetic_tool_pair(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    scope = WorkbenchScope("alice", "server", "room", "thread")
    _register(repo, scope)
    payload = {
        "v": 1, "submissionId": "submission-guard", "activityMessageId": "activity-1",
        "surfaceRevision": 1, "actionSchemaVersion": "intake.submit@1",
        "userAction": {"question": "Compare values", "districts": ["north"], "acknowledged": True},
    }
    WorkbenchActionService(repo).accept(scope, payload)
    upstream = APIRouter()

    @upstream.post("/v1/rooms/{room_id}/agui/{thread_id}/{run_id}")
    async def existing_agui(request: Request):
        # Exercise the installed adapter path that Soliplex 0.93 actually uses.
        adapter = await AGUIAdapter.from_request(request, agent=Agent(TestModel()))
        return adapter.run_input.model_dump(mode="json", by_alias=True)

    app = FastAPI()
    app.state.workbench_repository = repo
    app.include_router(create_guarded_agui_router(upstream, scope_provider=scope))
    client = TestClient(app)
    run_input = {"threadId": "thread", "runId": "run", "state": {}, "messages": [], "tools": [], "context": [], "forwardedProps": {"a2uiAction": payload}}
    replay_payload = run_input | {"forwardedProps": {}}
    replay = client.post("/v1/rooms/room/agui/thread/run", json=replay_payload, headers={"Last-Event-ID": "run:0"})
    assert replay.status_code == 200
    assert "workbenchAction" not in replay.json().get("state", {})
    accepted = client.post("/v1/rooms/room/agui/thread/run", json=run_input)
    assert accepted.status_code == 200
    messages = accepted.json()["messages"]
    assert [message["role"] for message in messages] == ["assistant", "tool"]
    assert messages[0]["toolCalls"][0]["function"]["name"] == "workbench_intake"
    assert messages[0]["toolCalls"][0]["id"] == messages[1]["toolCallId"]
    reconnect = client.post("/v1/rooms/room/agui/thread/run", json=replay_payload, headers={"Last-Event-ID": "run:1"})
    assert reconnect.status_code == 200
    assert reconnect.json()["messages"] == []
    duplicate = client.post("/v1/rooms/room/agui/thread/run", json=run_input)
    assert duplicate.status_code == 409


def test_nested_duplicate_json_keys_are_rejected_before_agui_adapter(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    scope = WorkbenchScope("alice", "server", "room", "thread")
    upstream = APIRouter()

    @upstream.post("/v1/rooms/{room_id}/agui/{thread_id}/{run_id}")
    async def handler(request: Request):
        return await request.body()

    app = FastAPI()
    app.state.workbench_repository = repo
    app.include_router(create_guarded_agui_router(upstream, scope_provider=scope))
    raw = b'{"threadId":"thread","runId":"run","state":{"x":1,"x":2},"messages":[],"tools":[],"context":[],"forwardedProps":{}}'
    response = TestClient(app).post("/v1/rooms/room/agui/thread/run", content=raw, headers={"content-type": "application/json"})
    assert response.status_code == 400


def test_workbench_reconnect_rejects_client_workbench_fields(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    scope = WorkbenchScope("alice", "server", "room", "thread")
    upstream = APIRouter()

    @upstream.post("/v1/rooms/{room_id}/agui/{thread_id}/{run_id}")
    async def handler(request: Request):
        return {"ok": True}

    app = FastAPI()
    app.state.workbench_repository = repo
    app.include_router(create_guarded_agui_router(upstream, scope_provider=scope))
    payload = {"threadId": "thread", "runId": "run", "state": {"workbenchAction": {"forged": True}}, "messages": [], "tools": [], "context": [], "forwardedProps": {}}
    response = TestClient(app).post("/v1/rooms/room/agui/thread/run", json=payload, headers={"Last-Event-ID": "run:0"})
    assert response.status_code == 422


def test_run_result_persists_client_trace_tags_without_model(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    scope = WorkbenchScope("alice", "server", "room", "thread")
    _register(repo, scope, "PythonRepl")
    class TraceCapture:
        def __init__(self):
            self.events = []
        def emit(self, event):
            self.events.append(event)
    sink = TraceCapture()
    service = WorkbenchActionService(repo, trace_sink=sink)
    payload = {
        "v": 1, "submissionId": "result-submit-1", "activityMessageId": "activity-1",
        "surfaceRevision": 1, "actionSchemaVersion": "workbench.program.run_result@1",
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
    assert duplicate["status"] == receipt["status"]
    assert duplicate["trace"] == receipt["trace"]
    assert len(sink.events) == 1
    assert sink.events[0]["python.side"] == "client"
    assert sink.events[0]["python.engine"] == "monty-1.3.0"
    changed = payload | {"submissionId": "result-submit-3", "userAction": payload["userAction"] | {"output": "forged"}}
    with pytest.raises(PublicationConflict):
        service.accept(scope, changed)


def test_run_result_invocation_id_is_bound_to_originating_surface(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "invocation-origin.sqlite")
    scope = WorkbenchScope("alice", "server", "room", "thread")
    _register(repo, scope, "PythonRepl")
    current = repo.load_snapshot(scope)
    layout = current["layout"]
    layout["layoutRevision"] = 2
    second_panel = {"id": "panel_chart_2", "parentId": "r_right", "children": ["surface-chart-2"], "kind": "panel", "title": "Second program", "size": "medium", "visibility": "open", "payload": {}}
    next(node for node in layout["nodes"] if node["id"] == "r_right")["children"].append("panel_chart_2")
    layout["nodes"].append(second_panel)
    layout["nodes"].append({"id": "surface-chart-2", "parentId": "panel_chart_2", "children": [], "kind": "surface", "title": "Second program", "size": "medium", "visibility": "open", "payload": {"activityMessageId": "activity-2", "surfaceId": "surface-2"}})
    first_record = {key: value for key, value in current["content"][0].items() if key != "workbenchCommit"} | {"surfaceRevision": 2}
    second_record = first_record | {"activityMessageId": "activity-2", "surfaceId": "surface-2"}
    repo.publish(scope, "add-second-program", 1, layout, [first_record, second_record], registered_program_surfaces=set(), registered_mounts={("activity-1", "surface-1"), ("activity-2", "surface-2")})
    service = WorkbenchActionService(repo, trace_sink=type("Sink", (), {"emit": lambda self, event: None})())
    common = {"v": 1, "surfaceRevision": 2, "actionSchemaVersion": "workbench.program.run_result@1", "userAction": {"side": "client", "engine": "monty-1.3.0", "invocationId": "shared-invocation", "chainId": "chain-1", "outcome": "success", "output": "125"}}
    service.accept(scope, common | {"submissionId": "origin-one", "activityMessageId": "activity-1"})
    with pytest.raises(PublicationConflict, match="invocation ID reused"):
        service.accept(scope, common | {"submissionId": "origin-two", "activityMessageId": "activity-2"})


def test_restore_does_not_invalidate_pending_intake_reservation(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    scope = WorkbenchScope("alice", "server", "room", "thread")
    _register(repo, scope)
    layout = repo.load(scope)
    layout["nodes"][2]["children"].append("panel-closed")
    layout["nodes"].append({"id": "panel-closed", "parentId": "r_left", "children": [], "kind": "panel", "title": "Closed", "size": "small", "visibility": "closed", "payload": {}})
    records = [{key: value for key, value in record.items() if key != "workbenchCommit"} for record in repo.load_content(scope)]
    repo.publish(scope, "close-panel", 1, layout | {"layoutRevision": 2}, records, registered_program_surfaces=set(), registered_mounts={("activity-1", "surface-1")})
    service = WorkbenchActionService(repo)
    envelope = {"v": 1, "submissionId": "pending-before-restore", "activityMessageId": "activity-1", "surfaceRevision": 1, "actionSchemaVersion": "intake.submit@1", "userAction": {"question": "Q", "districts": ["north"], "acknowledged": True}}
    service.accept(scope, envelope)
    before = repo.load_snapshot(scope)
    assert next(node for node in before["layout"]["nodes"] if node["id"] == "panel-closed")["visibility"] == "closed"
    restored = repo.restore_node(scope, "panel-closed")
    after = repo.load_snapshot(scope)
    assert restored == {"status": "restored", "nodeId": "panel-closed", "revision": 3, "sequence": 3}
    assert next(node for node in after["layout"]["nodes"] if node["id"] == "panel-closed")["visibility"] == "open"
    assert after["revision"] == before["revision"] + 1
    assert after["sequence"] == before["sequence"] + 1
    assert service.consume_dispatch(scope, {"forwardedProps": {"a2uiAction": envelope}}) == envelope
