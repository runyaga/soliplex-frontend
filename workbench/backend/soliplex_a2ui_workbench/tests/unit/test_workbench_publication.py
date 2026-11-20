"""Publication validation and stable part metadata tests."""

import json
from pathlib import Path

import pytest

from soliplex_a2ui_workbench.workbench_publication import (
    CatalogValidator,
    ContentPublication,
    build_publication,
    WorkbenchCatalogValidator,
)

FIXTURES = Path(__file__).parents[1] / "fixtures/workbench"


class FixtureValidator:
    def validate(self, records, negotiated_manifests):
        assert negotiated_manifests
        if any(record["component"] == "Unknown" for record in records):
            raise ValueError("unsupported fixture component")


def test_publication_uses_injected_validator_and_ordered_parts():
    contents = [json.loads((FIXTURES / "content_v1.json").read_text())]
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    built = build_publication(contents, FixtureValidator(), {contents[0]["catalogId"]: {"Chart"}}, layout=layout)
    assert isinstance(FixtureValidator(), CatalogValidator)
    assert [event["kind"] for event in built["events"]] == ["content", "layout"]
    assert built["content_records"][0]["workbenchCommit"] == {"recordId": "workbench-publication", "sequence": 1, "index": 0, "count": 2}
    assert built["events"][0]["event"]["content"]["a2ui_operations"][0]["createSurface"]["catalogId"] == "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"


def test_validator_failure_happens_before_publication_is_built():
    record = {"activityMessageId": "a", "surfaceId": "s", "catalogId": "x", "component": "Unknown", "spec": {}}
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    with pytest.raises(ValueError, match="unsupported fixture"):
        build_publication([record], FixtureValidator(), {"x": {"Chart"}}, layout=layout)


def test_missing_validator_is_not_silently_accepted():
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    with pytest.raises(TypeError):
        build_publication([], None, {}, layout=layout)


def test_builtin_validator_rejects_unknown_catalog_and_invalid_chart():
    record = json.loads((FIXTURES / "content_v1.json").read_text())
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    validator = WorkbenchCatalogValidator()
    built = build_publication([record], validator, {record["catalogId"]: {"Chart"}}, layout=layout)
    assert built["events"][0]["event"]["content"]["a2ui_operations"]
    record["spec"] = {"bad": "shape"}
    with pytest.raises(ValueError, match="invalid graphics:2 Chart spec"):
        build_publication([record], validator, {record["catalogId"]: {"Chart"}}, layout=layout)
    unknown = record | {"catalogId": "urn:unknown", "spec": {}}
    with pytest.raises(ValueError, match="catalog has no package validator"):
        build_publication([unknown], validator, {"urn:unknown": {"Chart"}}, layout=layout)


def test_builtin_validator_accepts_valid_basic_button_and_rejects_invalid_emitted_action():
    validator = WorkbenchCatalogValidator()
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    basic = "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
    record = {"activityMessageId": "a", "surfaceId": "s", "catalogId": basic, "component": "Button", "properties": {"label": "Go", "action": {"name": "submit"}}}
    built = build_publication([record], validator, {basic: {"Button"}}, layout=layout)
    assert built["events"][0]["event"]["content"]["a2ui_operations"][2]["updateComponents"]["components"][0]["action"] == {"name": "submit"}
    invalid = record | {"properties": {"label": "Go", "action": 123}}
    with pytest.raises(ValueError):
        build_publication([invalid], validator, {basic: {"Button"}}, layout=layout)


def test_emitted_component_validator_rejects_invalid_wire_action_even_if_record_validation_is_stubbed(monkeypatch):
    validator = WorkbenchCatalogValidator()
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    basic = "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
    record = {"activityMessageId": "a", "surfaceId": "s", "catalogId": basic, "component": "Button", "properties": {"label": "Go", "action": 123}}
    monkeypatch.setattr(WorkbenchCatalogValidator, "_validate_record", staticmethod(lambda *_args: None))
    with pytest.raises(ValueError, match="Button action"):
        build_publication([record], validator, {basic: {"Button"}}, layout=layout)


def test_basic_emitter_rejects_top_level_properties_it_does_not_copy():
    validator = WorkbenchCatalogValidator()
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    basic = "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
    record = {"activityMessageId": "a", "surfaceId": "s", "catalogId": basic, "component": "Text", "text": "Hello"}
    with pytest.raises(ValueError):
        build_publication([record], validator, {basic: {"Text"}}, layout=layout)


def test_place_form_emits_bound_intake_controls_and_submit_context():
    from soliplex_a2ui_workbench.workbench_publication import BASIC_CATALOG, BASIC_COMPONENTS, WORKBENCH_CATALOG

    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    record = {"activityMessageId": "activity_form", "surfaceId": "surface_form", "catalogId": WORKBENCH_CATALOG, "component": "PlaceForm", "title": "Intake", "template": "intake"}
    plan = build_publication(
        [record], WorkbenchCatalogValidator(),
        {BASIC_CATALOG: BASIC_COMPONENTS, WORKBENCH_CATALOG: {"PlaceForm"}}, layout=layout,
    )
    operations = plan["events"][0]["event"]["content"]["a2ui_operations"]
    data = operations[1]["updateDataModel"]["value"]
    components = operations[2]["updateComponents"]["components"]
    by_id = {item["id"]: item for item in components}
    assert data == {"title": "Intake", "question": "", "districts": [], "acknowledged": False}
    assert by_id["question"] == {"id": "question", "component": "TextField", "label": "Question", "value": {"@path": "/question"}}
    assert by_id["districts"] == {"id": "districts", "component": "ChoicePicker", "label": "Districts", "variant": "multipleSelection", "options": [{"value": "north", "label": "North"}, {"value": "south", "label": "South"}], "value": {"@path": "/districts"}, "displayStyle": "chips"}
    assert by_id["acknowledged"]["value"] == {"@path": "/acknowledged"}
    assert by_id["submit"]["action"]["context"] == {
        "question": {"@path": "/question"},
        "districts": {"@path": "/districts"},
        "acknowledged": {"@path": "/acknowledged"},
    }


def test_basic_choice_picker_requires_renderer_option_objects():
    from soliplex_a2ui_workbench.workbench_publication import BASIC_CATALOG

    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    validator = WorkbenchCatalogValidator()
    options = [{"value": "north", "label": "North"}, {"value": "south", "label": "South"}]
    valid = {"activityMessageId": "choices", "surfaceId": "choices_surface", "catalogId": BASIC_CATALOG, "component": "ChoicePicker", "properties": {"label": "Districts", "variant": "multipleSelection", "options": options, "value": {"@path": "/districts"}, "displayStyle": "chips"}}
    built = build_publication([valid], validator, {BASIC_CATALOG: {"ChoicePicker"}}, layout=layout)
    emitted = built["events"][0]["event"]["content"]["a2ui_operations"][2]["updateComponents"]["components"][0]
    assert emitted["options"] == options
    invalid = valid | {"properties": valid["properties"] | {"options": ["north", "south"]}}
    with pytest.raises(ValueError, match="ChoicePicker"):
        build_publication([invalid], validator, {BASIC_CATALOG: {"ChoicePicker"}}, layout=layout)


def test_basic_container_cannot_reference_unemitted_component():
    from soliplex_a2ui_workbench.workbench_publication import BASIC_CATALOG

    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    record = {"activityMessageId": "card", "surfaceId": "card_surface", "catalogId": BASIC_CATALOG, "component": "Card", "properties": {"children": ["missing-child"]}}
    with pytest.raises(ValueError, match="component reference"):
        build_publication([record], WorkbenchCatalogValidator(), {BASIC_CATALOG: {"Card"}}, layout=layout)


@pytest.mark.parametrize("mutate", [
    lambda spec: spec["series"][0].update(id={"bad": "id"}),
    lambda spec: spec["series"][0]["points"][0].update(label={"bad": "label"}),
])
def test_chart_validator_rejects_object_ids_and_labels(mutate):
    record = json.loads((FIXTURES / "content_v1.json").read_text())
    mutate(record["spec"])
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    with pytest.raises(ValueError):
        build_publication([record], WorkbenchCatalogValidator(), {record["catalogId"]: {"Chart"}}, layout=layout)
