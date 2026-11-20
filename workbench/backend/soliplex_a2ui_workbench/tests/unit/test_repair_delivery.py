"""Actual demo and repair ToolReturn payloads used by the canvas widget tests."""

import asyncio
import itertools
import json
from pathlib import Path
from unittest.mock import patch

import pytest

from soliplex_a2ui_workbench import workbench_tools
from soliplex_a2ui_workbench.workbench_teaching import ROOM_SUGGESTIONS, room_skill
from test_workbench_agent_tools import _context, _tool

BASE = Path(workbench_tools.__file__).parent
FIXTURE = (
    Path(__file__).parents[5]
    / "packages/soliplex_monty/test/fixtures/repair_delivery.dart"
)
DEMOS = {
    "syntax_error": (
        "Syntax error example",
        "syntax_error_demo.py.txt",
        "Open the syntax error example.",
    ),
    "name_error": (
        "NameError example",
        "name_error_demo.py",
        "Open the NameError example.",
    ),
    "type_check": (
        "Type check example",
        "type_check_demo.py",
        "Open the type check example.",
    ),
}


async def delivery(name):
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
        initial = await _tool("open_demo").function(context, name=name)
        source = (BASE / DEMOS[name][1]).read_text()
        fixed = {
            "syntax_error": source.rstrip() + ")\n",
            "name_error": source.replace("prnt(", "print("),
            "type_check": source.replace('value + "1"', "value + 1"),
        }[name]
        repair = await _tool("repair_program").function(
            context, node_id=initial.return_value["nodeId"], source=fixed
        )
    return {
        "initial": [
            event.model_dump(mode="json", by_alias=True) for event in initial.metadata
        ],
        "repair": [
            event.model_dump(mode="json", by_alias=True) for event in repair.metadata
        ],
    }


def fixtures():
    return {name: asyncio.run(delivery(name)) for name in DEMOS}


def test_actual_repair_payloads_match_widget_fixture():
    assert json.loads(FIXTURE.read_text().split("'''", 2)[1]) == fixtures()


@pytest.mark.parametrize("name", DEMOS)
def test_demo_source_is_curated_and_preserves_type_preference_on_repair(name):
    result = asyncio.run(delivery(name))
    for stage in ("initial", "repair"):
        program = result[stage][0]["content"]["a2ui_operations"]
        data = program[1]["updateDataModel"]["value"]
        root = program[2]["updateComponents"]["components"][0]
        assert root.get("typeCheck", False) == (name == "type_check")
        assert data["title"] == DEMOS[name][0]
        if stage == "initial":
            assert data["source"] == (BASE / DEMOS[name][1]).read_text()
    assert DEMOS[name][2] in ROOM_SUGGESTIONS
    assert f'open_demo("{name}")' in room_skill("workbench")
    assert (
        "The example is open. Enable AI Fix, then press Run to try the repair."
        in room_skill("workbench")
    )
    assert "Reply: tick AI Fix" not in room_skill("workbench")


@pytest.mark.parametrize(
    "auto_run,closed,changed",
    [
        (False, False, True),
        (True, False, True),
        (True, True, True),
        (True, False, False),
    ],
)
def test_repair_result_reports_requested_execution_without_claiming_success(
    auto_run, closed, changed
):
    async def exercise():
        context = _context()
        with patch.dict("os.environ", {"SOLIPLEX_WORKBENCH_ROOMS": "room"}):
            initial = await _tool("open_demo").function(context, name="name_error")
            context.deps._workbench_context.repair_request = {
                "surfaceId": initial.return_value["surfaceId"],
                "result": {
                    "run": 1,
                    "source": "prnt(1)",
                    "output": "NameError",
                    "error": "NameError",
                    "ok": False,
                    "attempt": 1,
                    "chainId": "chain-test",
                    "aiFix": auto_run,
                    "autoRun": auto_run,
                    "instruction": "Repair the program.",
                },
            }
            if closed:
                await _tool("close_panel").function(
                    context, node_id=initial.return_value["nodeId"]
                )
            source = (
                "print(1)" if changed else (BASE / "name_error_demo.py").read_text()
            )
            repair = await _tool("repair_program").function(
                context, node_id=initial.return_value["nodeId"], source=source
            )
            expected = auto_run and not closed and changed
            assert repair.return_value["autoRun"] is expected
            assert ("will run now" in repair.return_value["instruction"]) == expected
            assert "ran" in repair.return_value["instruction"]

    asyncio.run(exercise())
