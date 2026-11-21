"""Real Soliplex tool adapters publish activities, independent of REST snapshots."""

import asyncio
import itertools
import json
from pathlib import Path
from unittest.mock import patch

import pytest
from ag_ui.core import ActivitySnapshotEvent
from pydantic_ai import Agent, ModelRetry, RunContext, ToolReturn
from pydantic_ai.usage import RunUsage
from soliplex.agents import AgentDependencies, make_ai_tool
from soliplex.config.tools import ToolConfig
from soliplex_a2ui_workbench import workbench_tools
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

    deps = AgentDependencies(
        Installation(),
        thread_persistence_engine=engine,
        state={},
        room_id="room",
        thread_id="thread",
        run_id=run_id,
        user=User(),
    )
    return RunContext(deps=deps, model=None, usage=RunUsage())


def test_soliplex_config_builds_each_manifest_schema():
    for name, model in MINIMUM_ROOM_TOOL_MANIFEST.items():
        tool = _tool(name)
        assert tool.name == name
        assert set(tool.function_schema.json_schema["properties"]) == set(
            model.model_fields
        )
        assert tool.function_schema.json_schema.get("additionalProperties") is False


async def publication_fixture():
    """Return reproducible events from the actual ToolReturn boundary."""
    context = _context()
    counter = itertools.count(1)
    with (
        patch.dict("os.environ", {"SOLIPLEX_WORKBENCH_ROOMS": "room"}),
        patch.object(
            workbench_tools,
            "_identity",
            side_effect=lambda prefix: f"{prefix}_{next(counter)}",
        ),
    ):
        form = await _tool("place_form").function(
            context, template="intake", title="Intake", parent_id="r_left"
        )
        chart = await _tool("show_chart").function(
            context,
            title="Counts",
            kind="bar",
            points=[{"id": "north", "label": "North", "value": 80}],
            parent_id="r_canvas",
        )
        window = await _tool("create_container").function(
            context, parent_id="r_canvas", kind="window", title="Python"
        )
        program = await _tool("run_python_client").function(
            context,
            title="Demo",
            source="print(1)",
            parent_id=window.return_value["nodeId"],
        )
    return context, form, chart, window, program


def test_form_chart_and_move_publish_actual_activity_events(monkeypatch):
    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")
    # No SQLite factory may be touched, even when legacy snapshot data exists.
    monkeypatch.setattr(
        "soliplex_a2ui_workbench.workbench_repository.shared_repository",
        lambda: pytest.fail("legacy repository accessed"),
    )
    context, form, chart, window, program = asyncio.run(publication_fixture())
    layout_ids = set()
    for result in [form, chart, window, program]:
        assert isinstance(result, ToolReturn)
        assert all(
            isinstance(event, ActivitySnapshotEvent) for event in result.metadata
        )
        assert "events" not in result.return_value
        assert len(json.dumps(result.return_value)) < 400
        layout = result.metadata[-1]
        assert layout.content["workbenchPublication"]["role"] == "layout"
        layout_ids.add(layout.message_id)
        assert (
            layout.content["a2ui_operations"][1]["updateDataModel"]["value"][
                "workbench"
            ]["layoutRevision"]
            == result.return_value["layoutRevision"]
        )
        assert all("workbenchCommit" not in event.content for event in result.metadata)
    assert len(layout_ids) == 1
    for result, expected_component in [
        (form, "Column"),
        (chart, "Chart"),
        (program, "PythonRepl"),
    ]:
        assert len(result.metadata) == 2  # only new content, then referring layout
        event = result.metadata[0]
        assert event.message_id == result.return_value["activityMessageId"]
        operations = event.content["a2ui_operations"]
        assert (
            operations[0]["createSurface"]["surfaceId"]
            == result.return_value["surfaceId"]
        )
        assert (
            operations[2]["updateComponents"]["components"][0]["component"]
            == expected_component
        )
    assert len(window.metadata) == 1
    before = context.deps._workbench_context.snapshot()
    leaf = next(
        node
        for node in before["layout"]["nodes"]
        if node["id"] == form.return_value["nodeId"]
    )

    async def move_and_disable():
        moved = await _tool("move_panel").function(
            context,
            node_id=leaf["parentId"],
            parent_id="r_right",
            order=0,
            size="large",
        )
        disabled = await _tool("run_python_server").function(
            context, surface_id=program.return_value["surfaceId"], source="print(2)"
        )
        return moved, disabled

    moved, disabled = asyncio.run(move_and_disable())
    assert len(moved.metadata) == 1
    assert moved.metadata[0].content["workbenchPublication"]["role"] == "layout"
    assert disabled["execution"] == "disabled"
    python_root = program.metadata[0].content["a2ui_operations"][2]["updateComponents"][
        "components"
    ][0]
    assert python_root["outputPath"] == "/output" and "output" not in python_root
    assert program.return_value["execution"] == "awaiting_user"


def test_fresh_run_reconstructs_published_activities_without_client_state(monkeypatch):
    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")
    context, form, chart, window, program = asyncio.run(publication_fixture())
    events = [
        event for result in [form, chart, window, program] for event in result.metadata
    ]
    previous = context.deps._workbench_context
    fresh = RunWorkbenchProjection(previous.scope, events)
    assert fresh.load_snapshot(previous.scope) == previous.snapshot()
    # A durable layout without its preceding content retains the prior tree.
    partial = RunWorkbenchProjection(
        previous.scope, [*form.metadata, chart.metadata[-1]]
    )
    assert partial.layout["layoutRevision"] == form.return_value["layoutRevision"]
    # Named activities and client-supplied trees cannot grant a role.
    bogus = ActivitySnapshotEvent(
        messageId="layout",
        activityType="a2ui-surface",
        content={"a2ui_operations": [], "workbench": previous.snapshot()["layout"]},
    )
    assert RunWorkbenchProjection(previous.scope, [bogus]).layout["layoutRevision"] == 0
    with pytest.raises(ValueError):
        workbench_tools.move_panel(
            previous,
            node_id=form.return_value["nodeId"],
            parent_id="r_canvas",
            order=0,
            size="invalid",
        )


def test_dart_fixture_is_exact_tool_metadata():
    _, form, chart, window, program = asyncio.run(publication_fixture())
    fixture = Path(__file__).parents[5] / "test/fixtures/workbench_activity_events.dart"
    strings = fixture.read_text().split("'''")
    expected = [
        [
            event.model_dump(mode="json", by_alias=True, exclude_none=True)
            for result in results
            for event in result.metadata
        ]
        for results in [[form, chart], [window, program]]
    ]
    assert [json.loads(value.split("'''", 1)[0]) for value in strings[1::2]] == expected


def test_adapter_rebuilds_from_authenticated_thread_storage(monkeypatch):
    from soliplex.agui.persistence import ThreadStorage
    from soliplex.agui.schema import Base
    from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")

    async def exercise():
        engine = create_async_engine("sqlite+aiosqlite:///:memory:")
        try:
            async with engine.begin() as connection:
                await connection.run_sync(Base.metadata.create_all)
            context, form, chart, window, program = await publication_fixture()
            async with AsyncSession(engine, expire_on_commit=False) as session:
                storage = ThreadStorage(session)
                thread = await storage.new_thread(
                    user_name="alice",
                    email="@".join(("alice", "example.test")),
                    room_id="room",
                )
                thread.thread_id = "thread"
                await session.flush()
                run = (await thread.list_runs())[0]
                for result in [form, chart, window, program]:
                    for event in result.metadata:
                        await storage.save_single_event(
                            user_name="alice",
                            room_id="room",
                            thread_id="thread",
                            run_id=run.run_id,
                            event=event,
                        )
                await session.commit()
            fresh_context = _context("run-next", engine)
            # AG-UI client state is deliberately not authoritative.
            fresh_context.deps.state = {"workbench": {"layoutRevision": 999}}
            summary = await _tool("get_workbench").function(fresh_context)
            assert summary["layoutRevision"] == 4
            assert (
                fresh_context.deps._workbench_context.snapshot()
                == context.deps._workbench_context.snapshot()
            )
            panel = next(
                node
                for node in summary["nodes"]
                if node["id"] == form.return_value["nodeId"]
            )["parentId"]
            moved = await _tool("move_panel").function(
                fresh_context, node_id=panel, parent_id="r_right", order=0, size="large"
            )
            assert moved.return_value["layoutRevision"] == 5
            assert len(moved.metadata) == 1
        finally:
            await engine.dispose()

    asyncio.run(exercise())


def test_layout_failure_is_a_model_retry_with_corrective_text(monkeypatch):
    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")
    context = _context()

    async def exercise():
        with pytest.raises(ModelRetry) as failure:
            await _tool("run_python_client").function(
                context, title="Tally", source="print(1)", parent_id="r_left"
            )
        error = json.loads(failure.value.message)["error"]
        assert "program windows require canvas ancestry" in error
        assert "create_container(kind='window', parent_id='r_canvas'" in error
        assert "or pass a window id" in error
        assert context.deps._workbench_context.snapshot()["revision"] == 0

    asyncio.run(exercise())


def test_layout_retry_reaches_the_model_and_agui_as_an_error(monkeypatch):
    from ag_ui.core import ToolCallResultEvent
    from pydantic_ai.messages import FunctionToolResultEvent, ToolReturnPart
    from pydantic_ai.models.function import DeltaToolCall, FunctionModel
    from pydantic_ai.ui.ag_ui import AGUIEventStream

    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")
    retries = []
    streamed = []

    async def model(messages, info):
        returns = [
            part
            for message in messages
            for part in message.parts
            if isinstance(part, ToolReturnPart)
        ]
        if returns:
            retries.extend(returns)
            yield "I must correct the placement."
            return
        yield {
            0: DeltaToolCall(
                name="run_python_client",
                json_args=json.dumps(
                    {"title": "Tally", "source": "print(1)", "parent_id": "r_left"}
                ),
                tool_call_id="failed-call",
            )
        }

    async def events(ctx, event_stream):
        stream = AGUIEventStream()
        async for event in event_stream:
            if isinstance(event, FunctionToolResultEvent):
                streamed.extend(
                    [item async for item in stream.handle_function_tool_result(event)]
                )

    async def exercise():
        agent = Agent(
            FunctionModel(stream_function=model), tools=[_tool("run_python_client")]
        )
        await agent.run(
            "Create a tally", deps=_context().deps, event_stream_handler=events
        )

    asyncio.run(exercise())
    assert len(retries) == 1 and retries[0].outcome == "retried"
    result = next(e for e in streamed if isinstance(e, ToolCallResultEvent))
    assert result.tool_call_id == "failed-call"
    assert (
        json.loads(result.content)["error"] == json.loads(retries[0].content)["error"]
    )
    assert "or pass a window id" in result.content


def test_argument_validation_retry_does_not_echo_source(monkeypatch):
    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")

    async def exercise():
        with pytest.raises(ModelRetry) as failure:
            await _tool("run_python_client").function(
                _context(),
                title="Tally",
                source="private_source" + "x" * 1_000_000,
                parent_id="r_canvas",
            )
        assert "private_source" not in failure.value.message
        assert "source" in failure.value.message and "retry" in failure.value.message

    asyncio.run(exercise())


def test_tree_validation_retry_keeps_the_previous_snapshot(monkeypatch):
    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")
    context = _context()

    async def exercise():
        program = await _tool("run_python_client").function(
            context, title="Tally", source="print(1)", parent_id="r_canvas"
        )
        before = context.deps._workbench_context.snapshot()
        window = next(
            n
            for n in before["layout"]["nodes"]
            if program.return_value["nodeId"] in n["children"]
        )
        with pytest.raises(ModelRetry) as failure:
            await _tool("move_panel").function(
                context,
                node_id=window["id"],
                parent_id="r_left",
                order=0,
                size="medium",
            )
        error = json.loads(failure.value.message)["error"]
        assert "windows require canvas ancestry" in error
        assert "under r_canvas (region)" in error
        assert context.deps._workbench_context.snapshot() == before

    asyncio.run(exercise())


@pytest.mark.parametrize("content_kind", ["form", "chart", "program"])
def test_content_node_moves_and_closes_owner_at_real_tool_boundary(
    content_kind, monkeypatch
):
    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")
    context, form, chart, _window, program = asyncio.run(publication_fixture())
    target = {"form": form, "chart": chart, "program": program}[
        content_kind
    ].return_value["nodeId"]
    working = context.deps._workbench_context
    before = working.snapshot()
    owner = next(n["parentId"] for n in before["layout"]["nodes"] if n["id"] == target)

    async def exercise():
        destination = "r_right"
        if content_kind == "program":
            container = await _tool("create_container").function(
                context, parent_id="r_canvas", kind="tabs", title="Destination"
            )
            destination = container.return_value["nodeId"]
        previous = working.snapshot()
        moved = await _tool("move_panel").function(
            context, node_id=target, parent_id=destination, order=0, size="medium"
        )
        assert moved.return_value["nodeId"] == owner
        assert moved.return_value["layoutRevision"] == previous["revision"] + 1
        assert len(moved.metadata) == 1
        nodes = {n["id"]: n for n in working.snapshot()["layout"]["nodes"]}
        assert nodes[owner]["parentId"] == destination
        assert nodes[target]["parentId"] == owner
        closed = await _tool("close_panel").function(context, node_id=target)
        assert closed.return_value["nodeId"] == owner
        assert (
            closed.return_value["layoutRevision"]
            == moved.return_value["layoutRevision"] + 1
        )
        assert len(closed.metadata) == 1
        after = working.snapshot()
        assert (
            next(n for n in after["layout"]["nodes"] if n["id"] == owner)["visibility"]
            == "closed"
        )
        assert after["content"] == before["content"]

    asyncio.run(exercise())


@pytest.mark.parametrize(
    "failure_kind",
    ["unknown", "reserved", "wrong_parent", "capacity", "depth", "window"],
)
def test_layout_retry_retains_specific_node_kinds_and_corrective_action(
    failure_kind, monkeypatch
):
    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")
    context = _context()

    async def exercise():
        await _tool("get_workbench").function(context)
        working = context.deps._workbench_context
        target = workbench_tools.create_container(working, "r_left", "panel", "Panel")[
            "nodeId"
        ]
        parent = "r_right"
        expected = []
        if failure_kind == "unknown":
            parent = "missing"
            expected = ["missing", "kind unknown", "returned node id"]
        elif failure_kind == "reserved":
            target = "r_chat"
            expected = ["r_chat (region)", "protected", "authored panel/window"]
        elif failure_kind == "wrong_parent":
            parent = workbench_tools.open_panel(working, "Note", "Text", "r_right")[
                "nodeId"
            ]
            expected = [
                f"{target} (panel)",
                f"{parent} (surface)",
                "wrong parent kind",
                "use r_left",
            ]
        elif failure_kind == "capacity":
            parent = workbench_tools.create_container(
                working, "r_right", "split", "Full"
            )["nodeId"]
            for _ in range(3):
                workbench_tools.create_container(working, parent, "panel", "Child")
            expected = [
                f"{parent} (split)",
                f"{target} (panel)",
                "maximum 3",
                "move a child",
            ]
        elif failure_kind == "depth":
            parent = "r_right"
            for _ in range(6):
                parent = workbench_tools.create_container(
                    working, parent, "split", "Deep"
                )["nodeId"]
            expected = [
                f"{target} (panel)",
                f"{parent} (split)",
                "maximum 8",
                "shallower parent",
            ]
        elif failure_kind == "window":
            target = workbench_tools.create_container(
                working, "r_canvas", "window", "Window"
            )["nodeId"]
            expected = [
                f"{target} (window)",
                "r_right (region)",
                "under r_canvas (region)",
            ]
        before = working.snapshot()
        with pytest.raises(ModelRetry) as failure:
            await _tool("move_panel").function(
                context, node_id=target, parent_id=parent, order=0, size="medium"
            )
        error = json.loads(failure.value.message)["error"]
        assert error.startswith("move_panel:")
        for detail in expected:
            assert detail in error
        assert working.snapshot() == before

    asyncio.run(exercise())
