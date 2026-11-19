"""Durable workbench snapshot storage tests."""

import json

import pytest

from soliplex_a2ui_workbench.workbench_repository import (
    PublicationConflict,
    SQLiteWorkbenchRepository,
    WorkbenchScope,
)

FIXTURES = __import__("pathlib").Path(__file__).parents[1] / "fixtures/workbench"


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
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    result = repo.publish(scope, "pub_1", 0, snapshot(), content(), registered_program_surfaces={"surface_python"}, registered_mounts=mounts())
    repo.close()

    reopened = SQLiteWorkbenchRepository(tmp_path / "workbench.sqlite")
    assert reopened.load(scope) == result.snapshot
    assert reopened.get_receipt(scope, "pub_1") == result
    assert reopened.publish(scope, "pub_1", 0, snapshot(), content(), registered_program_surfaces={"surface_python"}, registered_mounts=mounts()) == result
    assert reopened.load_content(scope) == content()
    reopened.close()


def test_stale_revision_and_changed_duplicate_do_not_write(tmp_path):
    scope = WorkbenchScope(actor_id="a", server_id="s", room_id="r", thread_id="t")
    repo = SQLiteWorkbenchRepository(tmp_path / "db.sqlite")
    repo.publish(scope, "one", 0, snapshot(), content(), registered_program_surfaces={"surface_python"}, registered_mounts=mounts())
    with pytest.raises(PublicationConflict):
        repo.publish(scope, "two", 0, snapshot(), content(), registered_program_surfaces={"surface_python"}, registered_mounts=mounts())
    changed = snapshot()
    changed["layoutRevision"] += 1
    with pytest.raises(PublicationConflict):
        repo.publish(scope, "one", 1, changed, content(), registered_program_surfaces={"surface_python"}, registered_mounts=mounts())
    assert repo.load(scope)["layoutRevision"] == 1
    repo.close()


def test_validation_and_transaction_failure_leave_previous_snapshot(tmp_path):
    scope = WorkbenchScope(actor_id="a", server_id="s", room_id="r", thread_id="t")
    repo = SQLiteWorkbenchRepository(tmp_path / "db.sqlite")
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
    repo = SQLiteWorkbenchRepository(tmp_path / "db.sqlite")
    one = WorkbenchScope(actor_id="a", server_id="s", room_id="r", thread_id="t1")
    two = WorkbenchScope(actor_id="a", server_id="s", room_id="r", thread_id="t2")
    repo.publish(one, "one", 0, snapshot(), content(), registered_program_surfaces={"surface_python"}, registered_mounts=mounts())
    assert repo.load(two) is None
    repo.close()


def test_unregistered_mount_rejects_before_writing(tmp_path):
    scope = WorkbenchScope(actor_id="a", server_id="s", room_id="r", thread_id="t")
    repo = SQLiteWorkbenchRepository(tmp_path / "db.sqlite")
    with pytest.raises(ValueError, match="not registered"):
        repo.publish(scope, "one", 0, snapshot(), content(), registered_program_surfaces={"surface_python"}, registered_mounts=set())
    assert repo.load(scope) is None
    repo.close()
