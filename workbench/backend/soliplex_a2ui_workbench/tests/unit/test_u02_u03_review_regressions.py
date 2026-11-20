"""Security and integration regressions from the independent U02/U03 review."""

import json
from pathlib import Path

import pytest

from soliplex_a2ui_workbench.workbench_publication import build_publication
from soliplex_a2ui_workbench.workbench_repository import SQLiteWorkbenchRepository, WorkbenchScope


FIXTURES = Path(__file__).parents[1] / "fixtures/workbench"


def _registered_repo(tmp_path, component="PlaceForm"):
    repo = SQLiteWorkbenchRepository(tmp_path / "review.sqlite")
    scope = WorkbenchScope("alice", "server", "agui", "thread-1")
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    layout["nodes"][2]["children"] = ["panel_chart"]
    layout["nodes"].extend([
        {"id": "panel_chart", "parentId": "r_left", "children": ["surface_chart"], "kind": "panel", "title": "Content", "size": "medium", "visibility": "open", "payload": {}},
        {"id": "surface_chart", "parentId": "panel_chart", "children": [], "kind": "surface", "title": "Content", "size": "medium", "visibility": "open", "payload": {"activityMessageId": "activity-1", "surfaceId": "surface-1"}},
    ])
    record = json.loads((FIXTURES / "content_v1.json").read_text())
    record.update(activityMessageId="activity-1", surfaceId="surface-1", component=component)
    if component == "PlaceForm":
        record.update(catalogId="urn:soliplex:catalog:workbench:1", title="Intake", template="intake")
        record.pop("spec", None)
    else:
        record.update(catalogId="urn:soliplex:catalog:lab:1", source="print('idle')")
        record.pop("spec", None)
    repo.publish(scope, "initial", 0, layout, [record], registered_program_surfaces=set(), registered_mounts={("activity-1", "surface-1")})
    return repo, scope, record


def test_publication_commit_requires_catalog_validator(tmp_path):
    repo, scope, record = _registered_repo(tmp_path)
    before = repo.load_snapshot(scope)
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    invalid = record | {"catalogId": "not-a-catalog", "component": "Unknown", "spec": {"invalid": True}}
    with pytest.raises((TypeError, ValueError)):
        repo.publish(scope, "invalid-catalog", 1, layout | {"layoutRevision": 2}, [invalid], registered_program_surfaces=set(), registered_mounts=set())
    assert repo.load_snapshot(scope) == before
    assert repo.get_receipt(scope, "invalid-catalog") is None


def test_repository_commit_receipt_contains_stable_content_then_layout_emissions(tmp_path):
    repo, scope, _ = _registered_repo(tmp_path)
    result = repo.load_receipt(scope, "initial") if hasattr(repo, "load_receipt") else repo.get_receipt(scope, "initial")
    events = result.events
    assert [event["kind"] for event in events] == ["content", "layout"]
    assert events[0]["event"]["messageId"] == "activity-1"
    assert events[1]["event"]["messageId"].startswith("wb-layout-")
    assert all(event["event"]["replace"] is True for event in events)
    assert [event["event"]["content"]["workbenchCommit"]["index"] for event in events] == [0, 1]


def test_publication_emits_content_then_layout_wire_events():
    record = json.loads((FIXTURES / "content_v1.json").read_text())
    class Validator:
        def validate(self, records, manifests):
            assert records[0]["catalogId"] in manifests
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    from soliplex_a2ui_workbench.workbench_publication import BASIC_CATALOG
    plan = build_publication([record], Validator(), {record["catalogId"]: {"Chart"}, BASIC_CATALOG: {"Text"}}, layout=layout)
    events = plan["events"]
    assert [event["kind"] for event in events] == ["content", "layout"]
    assert events[0]["event"]["content"]["a2ui_operations"]
    assert events[0]["event"]["messageId"] == record["activityMessageId"]
