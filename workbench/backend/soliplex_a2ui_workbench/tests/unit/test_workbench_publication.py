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
    record["spec"] = {"bad": "shape"}
    with pytest.raises(ValueError, match="invalid graphics:2 Chart spec"):
        build_publication([record], WorkbenchCatalogValidator(), {record["catalogId"]: {"Chart"}}, layout=json.loads((FIXTURES / "layout_tree_v1.json").read_text()))
