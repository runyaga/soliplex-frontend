"""The room guide covers the exact callable table and validated tool arguments."""

import inspect
import json
from pathlib import Path

from soliplex_a2ui_workbench import workbench_agent_tools, workbench_tools
from soliplex_a2ui_workbench.workbench_context import WorkbenchToolContext
from soliplex_a2ui_workbench.workbench_projection import RunWorkbenchProjection
from soliplex_a2ui_workbench.workbench_repository import WorkbenchScope
from soliplex_a2ui_workbench.workbench_schemas import MINIMUM_ROOM_TOOL_MANIFEST
from soliplex_a2ui_workbench.workbench_teaching import TOOL_EXAMPLES, room_skill


def test_every_registered_tool_has_one_valid_example_and_real_signature():
    assert set(TOOL_EXAMPLES) == set(MINIMUM_ROOM_TOOL_MANIFEST)
    for name, schema in MINIMUM_ROOM_TOOL_MANIFEST.items():
        arguments = schema.model_validate(TOOL_EXAMPLES[name]).model_dump()
        inspect.signature(getattr(workbench_agent_tools, name)).bind(None, **arguments)
    text = room_skill("workbench")
    for name in MINIMUM_ROOM_TOOL_MANIFEST:
        assert f"`{name}(" in text
    assert "ui.Text(" in text and "ui.workbench.open_window(" in text
    assert "repair_program" in text and "replace=true" in text
    assert "creates a window titled with title" in text
    assert "one layout revision" in text
    assert "show_chart needs no window" in text
    assert "repair_program also accepts parent_id and title" in text
    assert TOOL_EXAMPLES["run_python_client"]["parent_id"] == "r_canvas"
    assert "a2ui_agent-0.4.0" in text
    assert "def handle_event(name, context)" in text
    assert "Valid Text variants from the registered catalog: caption, body." in text


def test_generated_catalog_contains_actual_component_schemas():
    from soliplex_a2ui_workbench import workbench_teaching

    generated = json.loads(
        Path(workbench_teaching.__file__).with_name("catalog_teaching.json").read_text()
    )
    assert generated["generator"] == "a2ui_agent-0.4.0"
    names = {
        name for catalog in generated["catalogs"] for name in catalog["components"]
    }
    assert {"Text", "Button", "PythonRepl", "Chart"} <= names


def test_generated_teaching_routes_static_content_to_panels():
    text = room_skill("workbench")
    assert (
        "Static text, tables and forms go through open_panel / place_form / show_chart."
        in text
    )
    assert (
        "Use run_python_client only for content that computes or reacts to clicks."
        in text
    )
    assert 'then open_panel(text="Hello") inside it' in text
    assert TOOL_EXAMPLES["run_python_client"]["source"] == "print(sum([2, 3, 5]))"


def test_generated_move_close_teaching_matches_executable_content_id_rules():
    text = room_skill("workbench")
    for phrase in (
        "accept a panel id, a window id, or a content leaf",
        "nearest enclosing panel or",
        "return the affected container's nodeId",
        "publish one layout revision",
        "Nested panels use the nearest",
        "surfaceId and activityMessageId are not node ids",
        "Splits and tabs can also be moved or closed by their own ids",
        "Closing\ndoes not free the total limit of 64 nodes",
    ):
        assert phrase in text
    for name in ("move_panel", "close_panel"):
        assert TOOL_EXAMPLES[name]["node_id"] == "CONTENT_NODE_ID"
        assert "nearest enclosing panel/window" in inspect.getdoc(
            getattr(workbench_agent_tools, name)
        )

    scope = WorkbenchScope("actor", "server", "room", "thread")
    ctx = WorkbenchToolContext(
        scope, RunWorkbenchProjection(scope), "run", allowed_rooms=frozenset({"room"})
    )
    chart = workbench_tools.show_chart(ctx, **TOOL_EXAMPLES["show_chart"])
    leaf = next(
        n for n in ctx.snapshot()["layout"]["nodes"] if n["id"] == chart["nodeId"]
    )
    owner = leaf["parentId"]
    before = ctx.snapshot()
    for name in ("move_panel", "close_panel"):
        arguments = {**TOOL_EXAMPLES[name], "node_id": chart["nodeId"]}
        result = getattr(workbench_tools, name)(ctx, **arguments)
        assert result["nodeId"] == owner
        assert result["layoutRevision"] == before["revision"] + 1
        assert len(result["events"]) == 1
        after = ctx.snapshot()
        assert after["content"] == before["content"]
        before = after
    nodes = {node["id"]: node for node in after["layout"]["nodes"]}
    assert nodes[owner]["parentId"] == "r_right"
    assert nodes[owner]["visibility"] == "closed"
    assert nodes[chart["nodeId"]]["parentId"] == owner
