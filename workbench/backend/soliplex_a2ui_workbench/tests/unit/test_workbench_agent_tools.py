"""Exercise the actual Soliplex tool config and authenticated tool adapters."""
import asyncio
import json
from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient
from ag_ui.core import ActivitySnapshotEvent
from pydantic_ai import RunContext, ToolReturn
from pydantic_ai.usage import RunUsage
from soliplex.agents import AgentDependencies, make_ai_tool
from soliplex.config.tools import ToolConfig

from soliplex_a2ui_workbench.workbench_repository import WorkbenchScope, shared_repository
from soliplex_a2ui_workbench.workbench_routes import build_router
from soliplex_a2ui_workbench.workbench_schemas import MINIMUM_ROOM_TOOL_MANIFEST
from soliplex_a2ui_workbench import workbench_agent_tools

FIXTURES = Path(__file__).parents[1] / "fixtures/workbench"
MODULE = "soliplex_a2ui_workbench.workbench_agent_tools"


def _tool(name):
    return make_ai_tool(ToolConfig(tool_name=f"{MODULE}.{name}"))


def test_soliplex_config_builds_each_manifest_schema():
    for name, model in MINIMUM_ROOM_TOOL_MANIFEST.items():
        tool = _tool(name)
        assert tool.name == name
        assert set(tool.function_schema.json_schema["properties"]) == set(model.model_fields)
        assert tool.function_schema.json_schema.get("additionalProperties") is False


def test_agent_tools_share_scope_and_repository_with_snapshot_route(tmp_path, monkeypatch):
    db_path = tmp_path / "shared.sqlite3"
    monkeypatch.setenv("SOLIPLEX_WORKBENCH_DB", str(db_path))
    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")
    repository = shared_repository()
    scope = WorkbenchScope("alice", "server-a", "room", "thread")
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    repository.publish(scope, "seed", 0, layout, [], registered_program_surfaces=set(), registered_mounts=set())

    class Installation:
        server_id = "server-a"
        def get_environment(self, _key):
            return "wrong-fallback"

    class User:
        preferred_username = "alice"

    deps = AgentDependencies(Installation(), state={}, room_id="room", thread_id="thread", run_id="run-1", user=User())
    context = RunContext(deps=deps, model=None, usage=RunUsage())
    app = FastAPI()
    app.include_router(build_router(workbench_rooms={"room"}))
    app.dependency_overrides.update({})
    from soliplex import agui, installation as installation_module, views

    class Policy:
        async def check_room_access(self, room_id, claims, *, permission):
            return room_id == "room" and claims["preferred_username"] == "alice"

    class Threads:
        async def get_thread(self, *, user_name, room_id, thread_id):
            return {"thread_id": thread_id}

    app.dependency_overrides[installation_module.depend_the_installation.dependency] = lambda: Installation()
    app.dependency_overrides[agui.depend_the_threads.dependency] = lambda: Threads()
    app.dependency_overrides[views.depend_the_room_authz_policy.dependency] = lambda: Policy()
    app.dependency_overrides[views.depend_the_user_claims.dependency] = lambda: {"preferred_username": "alice"}
    client = TestClient(app)

    async def invoke(name, **kwargs):
        tool = _tool(name)
        result = await tool.function(context, **kwargs)
        if name in {"open_panel", "place_form", "show_chart", "run_python_client", "create_container", "move_panel", "close_panel"}:
            assert isinstance(result, ToolReturn), name
            assert result.metadata and all(isinstance(event, ActivitySnapshotEvent) for event in result.metadata)
            assert all(event.activity_type == "a2ui-surface" for event in result.metadata)
            publication_id = result.metadata[0].content["workbenchCommit"]["recordId"]
            receipt = repository.get_receipt(scope, publication_id)
            assert [event.model_dump(mode="json", by_alias=True, exclude_none=True) for event in result.metadata] == [part["event"] for part in receipt.events]
            assert result.metadata[-1].content["a2ui_operations"][1]["updateDataModel"]["value"]["workbench"]["layoutRevision"] == result.return_value["layoutRevision"]
            if "activityMessageId" in result.return_value:
                event = next(event for event in result.metadata if event.message_id == result.return_value["activityMessageId"])
                assert event.content["a2ui_operations"][0]["createSurface"]["surfaceId"] == result.return_value["surfaceId"]
            return result.return_value
        return result

    async def exercise():
        await invoke("get_workbench")
        opened = await invoke("open_panel", title="Opening", text="Visible", parent_id="r_left")
        assert opened["status"] == "published"
        form = await invoke("place_form", template="intake", title="Intake", parent_id="r_left")
        chart = await invoke("show_chart", title="Counts", kind="bar", points=[{"id": "a", "label": "A", "value": 1}], parent_id="r_canvas")
        window = await invoke("create_container", parent_id="r_canvas", kind="window", title="Python")
        program = await invoke("run_python_client", title="Demo", source="print(1)", parent_id=window["nodeId"])
        await invoke("run_python_server", surface_id=program["surfaceId"], source="print(1)")
        container = await invoke("create_container", parent_id="r_canvas", kind="panel", title="Container")
        await invoke("move_panel", node_id=container["nodeId"], parent_id="r_left", order=0, size="large")
        await invoke("repair_program", node_id=program["nodeId"], source="print(2)")
        await invoke("close_panel", node_id=container["nodeId"])
        return form, chart, program

    form, chart, program = asyncio.run(exercise())
    response = client.get("/v1/rooms/room/threads/thread/workbench")
    assert response.status_code == 200, response.text
    assert app.state.workbench_repository is repository
    snapshot = response.json()
    assert snapshot["revision"] == 9
    parts = [record["content"] for record in snapshot["records"]]
    assert all(part["a2ui_operations"] for part in parts)
    assert {part["component"] for part in parts} >= {"Text", "PlaceForm", "Chart", "PythonRepl"}
    assert all(value["status"] == "published" for value in (form, chart, program))
    # Repeated calls in one (scope, run_id) share a single context and publication sequence.
    assert workbench_agent_tools._contexts[(*scope.key(), "run-1")] is not None
