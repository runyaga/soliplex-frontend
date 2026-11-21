"""Curated demo publication uses the real wrapper and stays declarative."""

import asyncio
import copy
import itertools
import json
from pathlib import Path
from unittest.mock import patch

import pytest
from ag_ui.core import ActivitySnapshotEvent
from pydantic_ai import ModelRetry, ToolReturn
from soliplex_a2ui_workbench import workbench_tools
from soliplex_a2ui_workbench.program_actions import apply_program_actions
from soliplex_a2ui_workbench.workbench_schemas import MINIMUM_ROOM_TOOL_MANIFEST
from soliplex_a2ui_workbench.workbench_teaching import ROOM_SUGGESTIONS, room_skill
from test_workbench_agent_tools import _context, _tool

FIXTURE = (
    Path(__file__).parents[5] / "packages/soliplex_monty/test/fixtures/monty_demo.json"
)
SOURCE = Path(workbench_tools.__file__).with_name("monty_gui_demo.py").read_text()


async def publication():
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
        result = await _tool("open_demo").function(context, name="monty_gui")
    return context, result


def fixture_operations(result):
    """Freeze the wire shape; source is read from its one canonical file."""
    operations = copy.deepcopy(result.metadata[0].content["a2ui_operations"])
    data = next(op["updateDataModel"] for op in operations if "updateDataModel" in op)
    assert data["value"]["source"] == SOURCE
    data["value"]["source"] = "__CURATED_SOURCE__"
    return operations


def test_open_demo_publishes_once_through_client_path_without_execution():
    with patch.object(
        workbench_tools, "run_python_client", wraps=workbench_tools.run_python_client
    ) as publish:
        context, result = asyncio.run(publication())
    publish.assert_called_once_with(
        context.deps._workbench_context, "Monty GUI demo", SOURCE, "r_canvas"
    )
    assert isinstance(result, ToolReturn)
    assert result.return_value["execution"] == "awaiting_user"
    assert result.return_value["side"] == "client"
    assert result.return_value["layoutRevision"] == 1
    assert len(result.metadata) == 2
    snapshot = context.deps._workbench_context.snapshot()
    assert len(snapshot["content"]) == 1
    assert snapshot["content"][0]["source"] == SOURCE
    assert snapshot["content"][0]["output"] == ""
    windows = [n for n in snapshot["layout"]["nodes"] if n["kind"] == "window"]
    assert len(windows) == 1
    assert windows[0]["title"] == "Monty GUI demo"
    assert windows[0]["parentId"] == "r_canvas"
    # Importing the source would fail on CPython: ui/chart exist only in Monty.
    assert json.loads(FIXTURE.read_text()) == fixture_operations(result)


def test_unknown_demo_is_corrective_and_publishes_nothing(monkeypatch):
    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")
    context = _context()

    async def exercise():
        await _tool("get_workbench").function(context)
        before = context.deps._workbench_context.snapshot()
        with pytest.raises(ModelRetry, match="open_demo.*monty_gui"):
            await _tool("open_demo").function(context, name="unknown")
        assert context.deps._workbench_context.snapshot() == before

    asyncio.run(exercise())


def test_demo_tool_accepts_only_a_name_and_suggestion_teaches_exact_call():
    assert set(MINIMUM_ROOM_TOOL_MANIFEST["open_demo"].model_fields) == {"name"}
    assert "Explore a Python app with buttons and charts." in ROOM_SUGGESTIONS
    teaching = room_skill("workbench")
    assert 'call open_demo("monty_gui")' in teaching
    assert "reply with only its confirmation field, one sentence" in teaching
    assert "keep its curated source unchanged" in teaching


def test_demo_log_batches_obey_two_window_limit_and_preserve_program():
    context, _ = asyncio.run(publication())
    working = context.deps._workbench_context
    projection = working.repository
    record = working.snapshot()["content"][0]

    def apply(actions):
        events = apply_program_actions(
            projection, working.scope, "gesture", record, actions
        )
        for event in events:
            projection._fold(ActivitySnapshotEvent.model_validate(event))
        windows = [
            n
            for n in projection.layout["nodes"]
            if n["kind"] == "window" and n["visibility"] == "open"
        ]
        assert len(windows) <= 2
        assert projection.content[record["activityMessageId"]]["source"] == SOURCE
        return windows

    def opened(window_id, text):
        return {
            "op": "open",
            "window_id": window_id,
            "title": "Monty event log",
            "kind": "text",
            "content": text,
        }

    assert (
        len(
            apply(
                [
                    opened("wbp_first", "last event: run, count 0"),
                    {"op": "move", "window_id": "wbp_first", "order": 1},
                ]
            )
        )
        == 2
    )
    assert (
        len(
            apply(
                [
                    {"op": "close", "window_id": "wbp_first"},
                    opened("wbp_second", "last event: open_log, count 2"),
                    {"op": "move", "window_id": "wbp_second", "order": 1},
                ]
            )
        )
        == 2
    )
    assert len(apply([{"op": "close", "window_id": "wbp_second"}])) == 1
