"""Security and integration regressions from the independent U02/U03 review."""

import json
from pathlib import Path

import pytest
from fastapi import APIRouter, FastAPI, Request
from fastapi.testclient import TestClient
from pydantic_ai import Agent
from pydantic_ai.models.test import TestModel
from pydantic_ai.ui.ag_ui import AGUIAdapter

from soliplex_a2ui_workbench.workbench_actions import WorkbenchActionService
from soliplex_a2ui_workbench.workbench_publication import build_publication
from soliplex_a2ui_workbench.workbench_repository import SQLiteWorkbenchRepository, WorkbenchScope
from soliplex_a2ui_workbench.workbench_routes import create_guarded_agui_router


FIXTURES = Path(__file__).parents[1] / "fixtures/workbench"


def _registered_repo(tmp_path, component="PlaceForm"):
    repo = SQLiteWorkbenchRepository(tmp_path / "review.sqlite")
    scope = WorkbenchScope("alice", "server", "agui", "thread-1")
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    layout["nodes"][2]["children"] = ["panel_chart"]
    layout["nodes"].extend([
        {"id": "panel_chart", "parentId": "r_left", "children": ["surface_chart"], "kind": "panel", "title": "Content", "size": "medium", "visibility": "open", "payload": {}},
        {"id": "surface_chart", "parentId": "panel_chart", "children": [], "kind": "surface", "title": "Content", "size": "medium", "visibility": "open", "payload": {"activityMessageId": "activity-1", "surfaceId": "surface-1"}},
    ])
    record = json.loads((FIXTURES / "content_v1.json").read_text())
    record.update(activityMessageId="activity-1", surfaceId="surface-1", component=component)
    if component == "PlaceForm":
        record.update(catalogId="urn:soliplex:catalog:workbench:1", title="Intake", template="intake")
        record.pop("spec", None)
    else:
        record.update(catalogId="urn:soliplex:catalog:lab:1", source="print('idle')")
        record.pop("spec", None)
    repo.publish(scope, "initial", 0, layout, [record], registered_program_surfaces=set(), registered_mounts={("activity-1", "surface-1")})
    return repo, scope, record


def _envelope(schema="intake.submit@1", submission="submit-1", user_action=None):
    return {
        "v": 1,
        "submissionId": submission,
        "activityMessageId": "activity-1",
        "surfaceRevision": 1,
        "actionSchemaVersion": schema,
        "userAction": user_action or {"question": "Compare these", "districts": ["north"], "acknowledged": True},
    }


def _guard_app(repo, scope):
    upstream = APIRouter()
    handler_calls = []

    @upstream.post("/v1/rooms/{room_id}/agui/{thread_id}/{run_id}")
    async def downstream(request: Request):
        handler_calls.append("entered")
        adapter = await AGUIAdapter.from_request(request, agent=Agent(TestModel()))
        return {"state": adapter.run_input.state, "message_count": len(adapter.run_input.messages), "messages": [message.model_dump(mode="json", by_alias=True) for message in adapter.run_input.messages]}

    app = FastAPI()
    app.state.workbench_repository = repo
    app.include_router(create_guarded_agui_router(upstream, scope_provider=scope))
    return TestClient(app), handler_calls


def test_malformed_last_event_id_does_not_skip_unreserved_action_guard(tmp_path):
    repo, scope, _ = _registered_repo(tmp_path)
    client, calls = _guard_app(repo, scope)
    payload = {"threadId": scope.thread_id, "runId": "run-1", "forwardedProps": {"a2uiAction": _envelope()}}
    response = client.post("/v1/rooms/agui/agui/thread-1/run-1", json=payload, headers={"Last-Event-ID": "garbage"})
    assert response.status_code in {409, 422}
    assert calls == []


def test_run_result_reservation_cannot_dispatch_to_model(tmp_path):
    repo, scope, _ = _registered_repo(tmp_path, "PythonRepl")
    class TraceCapture:
        def emit(self, _event):
            pass
    service = WorkbenchActionService(repo, trace_sink=TraceCapture())
    result = {"side": "client", "engine": "monty-1.3.0", "invocationId": "inv-1", "chainId": "chain-1", "outcome": "success", "output": "ok"}
    envelope = _envelope("workbench.program.run_result@1", "result-1", result)
    service.accept(scope, envelope)
    client, calls = _guard_app(repo, scope)
    response = client.post(
        "/v1/rooms/agui/agui/thread-1/run-2",
        json={"threadId": scope.thread_id, "runId": "run-2", "forwardedProps": {"a2uiAction": envelope}},
    )
    assert response.status_code in {409, 422}
    assert calls == []


def test_action_schema_version_rejects_context_from_another_variant(tmp_path):
    repo, scope, _ = _registered_repo(tmp_path, "PlaceForm")
    result = {"side": "client", "engine": "monty-1.3.0", "invocationId": "inv-1", "chainId": "chain-1", "outcome": "success", "output": "ok"}
    with pytest.raises(ValueError):
        WorkbenchActionService(repo).accept(scope, _envelope("intake.submit@1", user_action=result))


def test_client_cannot_supply_workbench_action_in_agui_state(tmp_path):
    repo, scope, _ = _registered_repo(tmp_path)
    client, _ = _guard_app(repo, scope)
    response = client.post(
        "/v1/rooms/agui/agui/thread-1/run-3",
        json={"threadId": scope.thread_id, "runId": "run-3", "state": {"workbenchAction": {"forged": True}}},
    )
    assert response.status_code == 422


def test_matched_path_parameters_allow_room_named_agui(tmp_path):
    repo, scope, _ = _registered_repo(tmp_path)
    envelope = _envelope()
    WorkbenchActionService(repo).accept(scope, envelope)
    client, _ = _guard_app(repo, scope)
    response = client.post(
        "/v1/rooms/agui/agui/thread-1/run-4",
        json={"threadId": scope.thread_id, "runId": "run-4", "state": {}, "messages": [], "tools": [], "context": [], "forwardedProps": {"a2uiAction": envelope}},
    )
    assert response.status_code == 200
    assert [message["role"] for message in response.json()["messages"]] == ["assistant", "tool"]
    assert response.json()["messages"][0]["toolCalls"][0]["function"]["name"] == "workbench_intake"
    assert response.json()["messages"][0]["toolCalls"][0]["id"] == response.json()["messages"][1]["toolCallId"]


def test_raw_action_json_rejects_duplicate_keys(tmp_path):
    repo, scope, _ = _registered_repo(tmp_path)
    client = TestClient(FastAPI())
    app = client.app
    from soliplex_a2ui_workbench.workbench_routes import build_router
    app.include_router(build_router(repository=repo))
    # Override only backend resources; the production scope dependency remains installed.
    from soliplex import agui, installation, views
    class Policy:
        async def check_room_access(self, room, claims, *, permission): return True
    class Threads:
        async def get_thread(self, *, user_name, room_id, thread_id): return object()
    app.dependency_overrides[installation.depend_the_installation.dependency] = lambda: type("Install", (), {"get_environment": lambda self, key: "server"})()
    app.dependency_overrides[agui.depend_the_threads.dependency] = lambda: Threads()
    app.dependency_overrides[views.depend_the_room_authz_policy.dependency] = lambda: Policy()
    app.dependency_overrides[views.depend_the_user_claims.dependency] = lambda: {"preferred_username": "alice"}
    payload = '{"v":1,"submissionId":"first","submissionId":"second","activityMessageId":"activity-1","surfaceRevision":1,"actionSchemaVersion":"intake.submit@1","userAction":{"question":"Q","districts":["north"],"acknowledged":true}}'
    response = client.post(f"/rooms/{scope.room_id}/threads/{scope.thread_id}/workbench/actions", content=payload, headers={"content-type": "application/json"})
    assert response.status_code == 400


def test_publication_commit_requires_catalog_validator(tmp_path):
    repo, scope, record = _registered_repo(tmp_path)
    before = repo.load_snapshot(scope)
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    invalid = record | {"catalogId": "not-a-catalog", "component": "Unknown", "spec": {"invalid": True}}
    with pytest.raises((TypeError, ValueError)):
        repo.publish(scope, "invalid-catalog", 1, layout | {"layoutRevision": 2}, [invalid], registered_program_surfaces=set(), registered_mounts=set())
    assert repo.load_snapshot(scope) == before
    assert repo.get_receipt(scope, "invalid-catalog") is None


def test_repository_commit_receipt_contains_stable_content_then_layout_emissions(tmp_path):
    repo, scope, _ = _registered_repo(tmp_path)
    result = repo.load_receipt(scope, "initial") if hasattr(repo, "load_receipt") else repo.get_receipt(scope, "initial")
    events = result.events
    assert [event["kind"] for event in events] == ["content", "layout"]
    assert events[0]["event"]["messageId"] == "activity-1"
    assert events[1]["event"]["messageId"].startswith("wb-layout-")
    assert all(event["event"]["replace"] is True for event in events)
    assert [event["event"]["content"]["workbenchCommit"]["index"] for event in events] == [0, 1]


def test_publication_emits_content_then_layout_wire_events():
    record = json.loads((FIXTURES / "content_v1.json").read_text())
    class Validator:
        def validate(self, records, manifests):
            assert records[0]["catalogId"] in manifests
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    plan = build_publication([record], Validator(), {record["catalogId"]: {"Chart"}}, layout=layout)
    events = plan["events"]
    assert [event["kind"] for event in events] == ["content", "layout"]
    assert events[0]["event"]["content"]["a2ui_operations"]
    assert events[0]["event"]["messageId"] == record["activityMessageId"]


def test_run_result_emits_one_server_trace_for_duplicate_invocation(tmp_path):
    repo, scope, _ = _registered_repo(tmp_path, "PythonRepl")
    class Sink:
        def __init__(self):
            self.events = []
        def emit(self, event):
            self.events.append(event)
    sink = Sink()
    service = WorkbenchActionService(repo, trace_sink=sink)
    result = {"side": "client", "engine": "monty-1.3.0", "invocationId": "inv-1", "chainId": "chain-1", "outcome": "success", "output": "ok"}
    service.accept(scope, _envelope("workbench.program.run_result@1", "result-1", result))
    service.accept(scope, _envelope("workbench.program.run_result@1", "result-2", result))
    assert len(sink.events) == 1
    assert sink.events[0]["python.side"] == "client"
    assert sink.events[0]["python.engine"] == "monty-1.3.0"
