"""Small, closed schemas exposed by minimum workbench tools."""
from soliplex_a2ui_workbench.workbench_schemas import MINIMUM_ROOM_TOOL_MANIFEST
def test_manifest_schemas_are_closed_and_have_no_more_than_five_fields():
    for model in MINIMUM_ROOM_TOOL_MANIFEST.values():
        schema = model.model_json_schema()
        assert schema["additionalProperties"] is False
        assert len(schema.get("properties", {})) <= 5
        assert all(child.get("additionalProperties") is False for child in schema.get("$defs", {}).values() if isinstance(child, dict))
def test_manifest_is_the_minimum_room_callable_surface():
    assert set(MINIMUM_ROOM_TOOL_MANIFEST) == {"get_workbench", "open_panel", "place_form", "show_chart", "run_python_client", "run_python_server", "create_container", "move_panel", "close_panel", "repair_program", "read_form_results", "open_demo"}
    assert "show_table" not in MINIMUM_ROOM_TOOL_MANIFEST


def test_chart_and_program_schemas_reject_bad_values():
    import pytest
    from pydantic import ValidationError
    from soliplex_a2ui_workbench.workbench_schemas import RunPythonClient, ShowChart
    with pytest.raises(ValidationError):
        ShowChart.model_validate({"title":"Counts", "kind":"bar", "parent_id":"r_canvas", "points":[{"id":"x", "label":"X", "value":True}]})
    with pytest.raises(ValidationError):
        ShowChart.model_validate({"title":"Counts", "kind":"bar", "parent_id":"r_canvas", "points":[{"id":"x", "label":"X", "value":1}, {"id":"x", "label":"Duplicate", "value":2}]})
    with pytest.raises(ValidationError):
        RunPythonClient.model_validate({"title":"Program", "parent_id":"p", "source":"é" * 7000})
