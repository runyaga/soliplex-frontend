"""Real Soliplex tool adapters publish activities, independent of REST snapshots."""
import asyncio
import itertools
import json
from pathlib import Path
from unittest.mock import patch

import pytest
from ag_ui.core import ActivitySnapshotEvent
from pydantic_ai import RunContext, ToolReturn
from pydantic_ai.usage import RunUsage
from soliplex.agents import AgentDependencies, make_ai_tool
from soliplex.config.tools import ToolConfig

from soliplex_a2ui_workbench import workbench_agent_tools, workbench_tools
from soliplex_a2ui_workbench.workbench_projection import RunWorkbenchProjection
from soliplex_a2ui_workbench.workbench_schemas import MINIMUM_ROOM_TOOL_MANIFEST

MODULE = "soliplex_a2ui_workbench.workbench_agent_tools"


def _tool(name):
    return make_ai_tool(ToolConfig(tool_name=f"{MODULE}.{name}"))


def _context(run_id="run-1", engine=None):
    class Installation:
        server_id = "server-a"
    class User:
        preferred_username = "alice"
    deps = AgentDependencies(Installation(), thread_persistence_engine=engine, state={}, room_id="room", thread_id="thread", run_id=run_id, user=User())
    return RunContext(deps=deps, model=None, usage=RunUsage())


def test_soliplex_config_builds_each_manifest_schema():
    for name, model in MINIMUM_ROOM_TOOL_MANIFEST.items():
        tool = _tool(name)
        assert tool.name == name
        assert set(tool.function_schema.json_schema["properties"]) == set(model.model_fields)
        assert tool.function_schema.json_schema.get("additionalProperties") is False


async def publication_fixture():
    """Return reproducible events from the actual ToolReturn boundary."""
    context = _context()
    counter = itertools.count(1)
    with patch.dict("os.environ", {"SOLIPLEX_WORKBENCH_ROOMS": "room"}), patch.object(workbench_tools, "_identity", side_effect=lambda prefix: f"{prefix}_{next(counter)}"):
        form = await _tool("place_form").function(context, template="intake", title="Intake", parent_id="r_left")
        chart = await _tool("show_chart").function(context, title="Counts", kind="bar", points=[{"id": "north", "label": "North", "value": 80}], parent_id="r_canvas")
        window = await _tool("create_container").function(context, parent_id="r_canvas", kind="window", title="Python")
        program = await _tool("run_python_client").function(context, title="Demo", source="print(1)", parent_id=window.return_value["nodeId"])
    return context, form, chart, window, program


def test_form_chart_and_move_publish_actual_activity_events(monkeypatch):
    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")
    # No SQLite factory may be touched, even when legacy snapshot data exists.
    monkeypatch.setattr("soliplex_a2ui_workbench.workbench_repository.shared_repository", lambda: pytest.fail("legacy repository accessed"))
    context, form, chart, window, program = asyncio.run(publication_fixture())
    layout_ids = set()
    for result in [form, chart, window, program]:
        assert isinstance(result, ToolReturn)
        assert all(isinstance(event, ActivitySnapshotEvent) for event in result.metadata)
        assert "events" not in result.return_value
        assert len(json.dumps(result.return_value)) < 400
        layout = result.metadata[-1]
        assert layout.content["workbenchPublication"]["role"] == "layout"
        layout_ids.add(layout.message_id)
        assert layout.content["a2ui_operations"][1]["updateDataModel"]["value"]["workbench"]["layoutRevision"] == result.return_value["layoutRevision"]
        assert all("workbenchCommit" not in event.content for event in result.metadata)
    assert len(layout_ids) == 1
    for result, expected_component in [(form, "Column"), (chart, "Chart"), (program, "PythonRepl")]:
        assert len(result.metadata) == 2  # only new content, then referring layout
        event = result.metadata[0]
        assert event.message_id == result.return_value["activityMessageId"]
        operations = event.content["a2ui_operations"]
        assert operations[0]["createSurface"]["surfaceId"] == result.return_value["surfaceId"]
        assert operations[2]["updateComponents"]["components"][0]["component"] == expected_component
    assert len(window.metadata) == 1
    before = context.deps._workbench_context.snapshot()
    leaf = next(node for node in before["layout"]["nodes"] if node["id"] == form.return_value["nodeId"])
    async def move_and_disable():
        moved = await _tool("move_panel").function(context, node_id=leaf["parentId"], parent_id="r_right", order=0, size="large")
        disabled = await _tool("run_python_server").function(context, surface_id=program.return_value["surfaceId"], source="print(2)")
        return moved, disabled
    moved, disabled = asyncio.run(move_and_disable())
    assert len(moved.metadata) == 1
    assert moved.metadata[0].content["workbenchPublication"]["role"] == "layout"
    assert disabled["execution"] == "disabled"
    python_root = program.metadata[0].content["a2ui_operations"][2]["updateComponents"]["components"][0]
    assert python_root["outputPath"] == "/output" and "output" not in python_root
    assert program.return_value["execution"] == "awaiting_user"


def test_fresh_run_reconstructs_published_activities_without_client_state(monkeypatch):
    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")
    context, form, chart, window, program = asyncio.run(publication_fixture())
    events = [event for result in [form, chart, window, program] for event in result.metadata]
    previous = context.deps._workbench_context
    fresh = RunWorkbenchProjection(previous.scope, events)
    assert fresh.load_snapshot(previous.scope) == previous.snapshot()
    # A durable layout without its preceding content retains the prior tree.
    partial = RunWorkbenchProjection(previous.scope, [*form.metadata, chart.metadata[-1]])
    assert partial.layout["layoutRevision"] == form.return_value["layoutRevision"]
    # Named activities and client-supplied trees cannot grant a role.
    bogus = ActivitySnapshotEvent(messageId="layout", activityType="a2ui-surface", content={"a2ui_operations": [], "workbench": previous.snapshot()["layout"]})
    assert RunWorkbenchProjection(previous.scope, [bogus]).layout["layoutRevision"] == 0
    with pytest.raises(ValueError):
        workbench_tools.move_panel(previous, node_id=form.return_value["nodeId"], parent_id="r_canvas", order=0, size="invalid")


def test_dart_fixture_is_exact_tool_metadata():
    _, form, chart, window, program = asyncio.run(publication_fixture())
    fixture = Path(__file__).parents[5] / "test/fixtures/workbench_activity_events.dart"
    strings = fixture.read_text().split("'''")
    expected = [[event.model_dump(mode="json", by_alias=True, exclude_none=True) for result in results for event in result.metadata]
                for results in [[form, chart], [window, program]]]
    assert [json.loads(value.split("'''", 1)[0]) for value in strings[1::2]] == expected


def test_adapter_rebuilds_from_authenticated_thread_storage(monkeypatch):
    from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
    from soliplex.agui.persistence import ThreadStorage
    from soliplex.agui.schema import Base

    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")

    async def exercise():
        engine = create_async_engine("sqlite+aiosqlite:///:memory:")
        try:
            async with engine.begin() as connection:
                await connection.run_sync(Base.metadata.create_all)
            context, form, chart, window, program = await publication_fixture()
            async with AsyncSession(engine, expire_on_commit=False) as session:
                storage = ThreadStorage(session)
                thread = await storage.new_thread(user_name="alice", email="@".join(("alice", "example.test")), room_id="room")
                thread.thread_id = "thread"
                await session.flush()
                run = (await thread.list_runs())[0]
                for result in [form, chart, window, program]:
                    for event in result.metadata:
                        await storage.save_single_event(user_name="alice", room_id="room", thread_id="thread", run_id=run.run_id, event=event)
                await session.commit()
            fresh_context = _context("run-next", engine)
            # AG-UI client state is deliberately not authoritative.
            fresh_context.deps.state = {"workbench": {"layoutRevision": 999}}
            summary = await _tool("get_workbench").function(fresh_context)
            assert summary["layoutRevision"] == 4
            assert fresh_context.deps._workbench_context.snapshot() == context.deps._workbench_context.snapshot()
            panel = next(node for node in summary["nodes"] if node["id"] == form.return_value["nodeId"])["parentId"]
            moved = await _tool("move_panel").function(fresh_context, node_id=panel, parent_id="r_right", order=0, size="large")
            assert moved.return_value["layoutRevision"] == 5
            assert len(moved.metadata) == 1
        finally:
            await engine.dispose()
    asyncio.run(exercise())
