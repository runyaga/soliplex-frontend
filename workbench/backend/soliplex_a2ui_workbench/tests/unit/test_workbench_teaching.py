"""The room guide covers the exact callable table and validated tool arguments."""

import inspect
import json
from pathlib import Path

from soliplex_a2ui_workbench import workbench_agent_tools
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
