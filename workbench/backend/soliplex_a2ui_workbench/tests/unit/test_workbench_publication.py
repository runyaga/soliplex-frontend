"""Publication validation and stable part metadata tests."""

import json
from pathlib import Path

import pytest

from soliplex_a2ui_workbench.workbench_publication import (
    CatalogValidator,
    ContentPublication,
    build_publication,
)

FIXTURES = Path(__file__).parents[1] / "fixtures/workbench"


class FixtureValidator:
    def validate(self, records, negotiated_manifests):
        assert negotiated_manifests
        if any(record["component"] == "Unknown" for record in records):
            raise ValueError("unsupported fixture component")


def test_publication_uses_injected_validator_and_ordered_parts():
    contents = [json.loads((FIXTURES / "content_v1.json").read_text())]
    built = build_publication(contents, FixtureValidator(), {"graphics:2": {"Chart"}})
    assert isinstance(FixtureValidator(), CatalogValidator)
    assert built == [ContentPublication(record_id="activity_chart", activity_message_id="activity_chart", surface_id="surface_chart", sequence=1, part_index=0, part_count=1, record=contents[0])]


def test_validator_failure_happens_before_publication_is_built():
    record = {"activityMessageId": "a", "surfaceId": "s", "catalogId": "x", "component": "Unknown", "spec": {}}
    with pytest.raises(ValueError, match="unsupported fixture"):
        build_publication([record], FixtureValidator(), {"x": {"Chart"}})


def test_missing_validator_is_not_silently_accepted():
    with pytest.raises(TypeError):
        build_publication([], None, {})
