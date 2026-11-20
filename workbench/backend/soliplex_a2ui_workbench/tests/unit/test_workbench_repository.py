from soliplex_a2ui_workbench.workbench_repository import default_layout
"""Durable workbench snapshot storage tests."""

import json
import threading

import pytest

from soliplex_a2ui_workbench.workbench_repository import (
    PublicationConflict,
    SQLiteWorkbenchRepository,
    WorkbenchScope,
)

FIXTURES = __import__("pathlib").Path(__file__).parents[1] / "fixtures/workbench"


class FixtureCatalogValidator:
    def validate(self, records, manifests):
        for record in records:
            if record.get("catalogId") not in manifests or record.get("component") not in manifests[record["catalogId"]]:
                raise ValueError("unknown fixture catalog component")


def fixture_repo(path):
    from soliplex_a2ui_workbench.workbench_publication import BASIC_CATALOG

    return SQLiteWorkbenchRepository(
        path,
        catalog_validator=FixtureCatalogValidator(),
        negotiated_manifests={"fixture": {"Fixture"}, BASIC_CATALOG: {"Text"}},
    )


def snapshot():
    value = json.loads((FIXTURES / "nested_tree_v1.json").read_text())
    value["layoutRevision"] = 1
    return value


def snapshot_at(revision):
    value = snapshot()
    value["layoutRevision"] = revision
    return value


def mounts():
    return {(item["activityMessageId"], item["surfaceId"]) for item in content()}


def content():
    records = []
    for node in snapshot()["nodes"]:
        if node["kind"] == "surface":
            records.append({"activityMessageId": node["payload"]["activityMessageId"], "surfaceId": node["payload"]["surfaceId"], "catalogId": "fixture", "component": "Fixture", "data": {}})
    return records


def test_restart_preserves_records_layout_and_duplicate_receipt(tmp_path):
    scope = WorkbenchScope(actor_id="actor_a", server_id="server_a", room_id="room_a", thread_id="thread_a")
    repo = fixture_repo(tmp_path / "workbench.sqlite")
    result = repo.publish(scope, "pub_1", 0, snapshot(), content(), registered_program_surfaces={"surface_python"}, registered_mounts=mounts())
    repo.close()

    reopened = fixture_repo(tmp_path / "workbench.sqlite")
    assert reopened.load(scope) == result.snapshot
    assert reopened.get_receipt(scope, "pub_1") == result
    assert reopened.publish(scope, "pub_1", 0, snapshot(), content(), registered_program_surfaces={"surface_python"}, registered_mounts=mounts()) == result
    loaded_content = reopened.load_content(scope)
    assert [item | {"surfaceRevision": 1, "workbenchCommit": loaded_content[index]["workbenchCommit"]} for index, item in enumerate(content())] == loaded_content
    reopened.close()


def test_stale_revision_and_changed_duplicate_do_not_write(tmp_path):
    scope = WorkbenchScope(actor_id="a", server_id="s", room_id="r", thread_id="t")
    repo = fixture_repo(tmp_path / "db.sqlite")
    repo.publish(scope, "one", 0, snapshot(), content(), registered_program_surfaces={"surface_python"}, registered_mounts=mounts())
    with pytest.raises(PublicationConflict):
        repo.publish(scope, "two", 0, snapshot(), content(), registered_program_surfaces={"surface_python"}, registered_mounts=mounts())
    changed = snapshot()
    changed["layoutRevision"] += 1
    with pytest.raises(PublicationConflict):
        repo.publish(scope, "one", 1, changed, content(), registered_program_surfaces={"surface_python"}, registered_mounts=mounts())
    assert repo.load(scope)["layoutRevision"] == 1
    repo.close()


def test_surface_revision_regression_leaves_snapshot_and_receipts_unchanged(tmp_path):
    scope = WorkbenchScope("actor", "server", "room", "thread")
    repo = fixture_repo(tmp_path / "surface-revision.sqlite")
    first_layout = snapshot()
    first_content = [record | {"surfaceRevision": 5} for record in content()]
    first = repo.publish(scope, "surface-five", 0, first_layout, first_content, registered_program_surfaces={"surface_python"}, registered_mounts=mounts())
    before_snapshot = repo.load_snapshot(scope)
    before_receipt = repo.get_receipt(scope, "surface-five")
    regressed = [record | {"surfaceRevision": 1} for record in content()]
    next_layout = snapshot_at(2)
    with pytest.raises(PublicationConflict, match="surface revision"):
        repo.publish(scope, "surface-one", 1, next_layout, regressed, registered_program_surfaces={"surface_python"}, registered_mounts=mounts())
    assert repo.load_snapshot(scope) == before_snapshot
    assert repo.get_receipt(scope, "surface-five") == before_receipt == first
    assert repo.get_receipt(scope, "surface-one") is None
    repo.close()


def test_surface_revision_bool_is_rejected_and_omission_preserves_effective_revision(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "strict-surface-revision.sqlite")
    scope = WorkbenchScope("actor", "server", "room", "thread")
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    layout["nodes"][2]["children"] = ["panel-form"]
    layout["nodes"].extend([
        {"id": "panel-form", "parentId": "r_left", "children": ["surface-form"], "kind": "panel", "title": "Form", "size": "medium", "visibility": "open", "payload": {}},
        {"id": "surface-form", "parentId": "panel-form", "children": [], "kind": "surface", "title": "Form", "size": "medium", "visibility": "open", "payload": {"activityMessageId": "activity-form", "surfaceId": "surface-form"}},
    ])
    from soliplex_a2ui_workbench.workbench_publication import WORKBENCH_CATALOG
    original = {"activityMessageId": "activity-form", "surfaceId": "surface-form", "catalogId": WORKBENCH_CATALOG, "component": "PlaceForm", "title": "Form", "template": "intake", "surfaceRevision": 5}
    repo.publish(scope, "surface-five", 0, layout, [original], registered_program_surfaces=set(), registered_mounts={("activity-form", "surface-form")})
    before = repo.load_snapshot(scope)
    next_layout = json.loads(json.dumps(layout))
    next_layout["layoutRevision"] = 2
    with pytest.raises(ValueError, match="surfaceRevision"):
        repo.publish(scope, "surface-bool", 1, next_layout, [original | {"surfaceRevision": True}], registered_program_surfaces=set(), registered_mounts={("activity-form", "surface-form")})
    assert repo.load_snapshot(scope) == before
    assert repo.get_receipt(scope, "surface-bool") is None
    omitted = {key: value for key, value in original.items() if key != "surfaceRevision"}
    repo.publish(scope, "surface-omitted", 1, next_layout, [omitted], registered_program_surfaces=set(), registered_mounts={("activity-form", "surface-form")})
    assert repo.load_content(scope)[0]["surfaceRevision"] == 5
    repo.close()


def test_explicit_empty_negotiation_does_not_fall_back_to_builtin_catalogs(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "empty-negotiation.sqlite", negotiated_manifests={})
    scope = WorkbenchScope("actor", "server", "room", "thread")
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    record = json.loads((FIXTURES / "content_v1.json").read_text())
    record["activityMessageId"] = "activity-chart"
    record["surfaceId"] = "surface-chart"
    layout["nodes"][2]["children"] = ["panel-chart"]
    layout["nodes"].extend([
        {"id": "panel-chart", "parentId": "r_left", "children": ["surface-chart"], "kind": "panel", "title": "Chart", "size": "medium", "visibility": "open", "payload": {}},
        {"id": "surface-chart", "parentId": "panel-chart", "children": [], "kind": "surface", "title": "Chart", "size": "medium", "visibility": "open", "payload": {"activityMessageId": "activity-chart", "surfaceId": "surface-chart"}},
    ])
    with pytest.raises(ValueError, match="negotiated"):
        repo.publish(scope, "empty-negotiation", 0, layout, [record], registered_program_surfaces=set(), registered_mounts={("activity-chart", "surface-chart")})
    assert repo.load_snapshot(scope)["layout"] == default_layout()
    assert repo.get_receipt(scope, "empty-negotiation") is None
    repo.close()


def test_validation_and_transaction_failure_leave_previous_snapshot(tmp_path):
    scope = WorkbenchScope(actor_id="a", server_id="s", room_id="r", thread_id="t")
    repo = fixture_repo(tmp_path / "db.sqlite")
    original = repo.publish(scope, "one", 0, snapshot(), content(), registered_program_surfaces={"surface_python"}, registered_mounts=mounts())
    invalid = snapshot()
    invalid["nodes"].pop()
    with pytest.raises(ValueError):
        repo.publish(scope, "bad", 1, invalid, content(), registered_program_surfaces={"surface_python"}, registered_mounts=mounts())
    with pytest.raises(RuntimeError):
        repo.publish(scope, "fail", 1, snapshot_at(2), content(), registered_program_surfaces={"surface_python"}, registered_mounts=mounts(), before_commit=lambda: (_ for _ in ()).throw(RuntimeError("injected")))
    assert repo.load(scope) == original.snapshot
    assert repo.get_receipt(scope, "fail") is None
    repo.close()


def test_scopes_are_isolated(tmp_path):
    repo = fixture_repo(tmp_path / "db.sqlite")
    one = WorkbenchScope(actor_id="a", server_id="s", room_id="r", thread_id="t1")
    two = WorkbenchScope(actor_id="a", server_id="s", room_id="r", thread_id="t2")
    published = repo.publish(one, "one", 0, snapshot(), content(), registered_program_surfaces={"surface_python"}, registered_mounts=mounts())
    assert repo.load(one) == published.snapshot
    loaded = repo.load_content(one)
    assert [record["activityMessageId"] for record in loaded] == [record["activityMessageId"] for record in content()]
    assert all(record["workbenchCommit"]["recordId"] == "one" and record["workbenchCommit"]["sequence"] == 1 for record in loaded)
    assert repo.load(two) is None
    repo.close()


def test_unregistered_mount_rejects_before_writing(tmp_path):
    scope = WorkbenchScope(actor_id="a", server_id="s", room_id="r", thread_id="t")
    repo = fixture_repo(tmp_path / "db.sqlite")
    with pytest.raises(ValueError, match="not registered"):
        repo.publish(scope, "one", 0, snapshot(), content(), registered_program_surfaces={"surface_python"}, registered_mounts=set())
    assert repo.load(scope) is None
    repo.close()


@pytest.mark.parametrize("mutate", [
    lambda spec: spec["series"][0].update(id={"bad": "series-id"}),
    lambda spec: spec["series"][0]["points"][0].update(label={"bad": "point-label"}),
])
def test_default_catalog_validator_rejects_malformed_chart_before_commit(tmp_path, mutate):
    scope = WorkbenchScope("actor", "server", "room", "thread")
    repo = SQLiteWorkbenchRepository(tmp_path / "chart.sqlite")
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    layout["nodes"][2]["children"] = ["panel-chart"]
    layout["nodes"].extend([
        {"id": "panel-chart", "parentId": "r_left", "children": ["surface-chart"], "kind": "panel", "title": "Chart", "size": "medium", "visibility": "open", "payload": {}},
        {"id": "surface-chart", "parentId": "panel-chart", "children": [], "kind": "surface", "title": "Chart", "size": "medium", "visibility": "open", "payload": {"activityMessageId": "activity_chart", "surfaceId": "surface_chart"}},
    ])
    record = json.loads((FIXTURES / "content_v1.json").read_text())
    mutate(record["spec"])
    with pytest.raises(ValueError):
        repo.publish(scope, "malformed", 0, layout, [record], registered_program_surfaces=set(), registered_mounts={("activity_chart", "surface_chart")})
    assert repo.load_snapshot(scope)["layout"] == default_layout()
    assert repo.get_receipt(scope, "malformed") is None
    repo.close()


def test_dangling_emitted_component_reference_rejects_before_repository_commit(tmp_path):
    repo = SQLiteWorkbenchRepository(tmp_path / "dangling.sqlite")
    scope = WorkbenchScope("actor", "server", "room", "thread")
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    layout["nodes"][2]["children"] = ["panel-card"]
    layout["nodes"].extend([
        {"id": "panel-card", "parentId": "r_left", "children": ["surface-card"], "kind": "panel", "title": "Card", "size": "medium", "visibility": "open", "payload": {}},
        {"id": "surface-card", "parentId": "panel-card", "children": [], "kind": "surface", "title": "Card", "size": "medium", "visibility": "open", "payload": {"activityMessageId": "card", "surfaceId": "card_surface"}},
    ])
    from soliplex_a2ui_workbench.workbench_publication import BASIC_CATALOG
    record = {"activityMessageId": "card", "surfaceId": "card_surface", "catalogId": BASIC_CATALOG, "component": "Card", "properties": {"children": ["missing-child"]}}
    with pytest.raises(ValueError, match="component reference"):
        repo.publish(scope, "dangling", 0, layout, [record], registered_program_surfaces=set(), registered_mounts={("card", "card_surface")})
    assert repo.load_snapshot(scope)["layout"] == default_layout()
    assert repo.get_receipt(scope, "dangling") is None
    repo.close()


def test_overlapping_repository_transactions_are_serialized(tmp_path):
    repo = fixture_repo(tmp_path / "concurrent.sqlite")
    first = WorkbenchScope("actor", "server", "room", "thread-one")
    second = WorkbenchScope("actor", "server", "room", "thread-two")
    entered_first = threading.Event()
    release_first = threading.Event()
    second_callback_entered = threading.Event()
    errors = []

    def publish(scope, key, callback):
        try:
            repo.publish(scope, key, 0, snapshot(), content(), registered_program_surfaces={"surface_python"}, registered_mounts=mounts(), before_commit=callback)
        except BaseException as exc:
            errors.append(exc)

    def pause_first():
        entered_first.set()
        if not release_first.wait(3):
            raise TimeoutError("first transaction was not released")

    one = threading.Thread(target=publish, args=(first, "one", pause_first))
    two = threading.Thread(target=publish, args=(second, "two", second_callback_entered.set))
    one.start()
    assert entered_first.wait(2)
    two.start()
    assert not second_callback_entered.wait(0.1)
    release_first.set()
    one.join(3)
    two.join(3)
    assert not one.is_alive() and not two.is_alive()
    assert not errors
    assert second_callback_entered.is_set()
    assert repo.load(first) is not None and repo.load(second) is not None
    repo.close()
