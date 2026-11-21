"""Publication, owned-window transactions and real authenticated thread files.

Monty executes the same source in curated_demos_test.dart; this adapter drives
backend publication/file boundaries without substituting for that runtime test.
"""

# ruff: noqa: S102 -- Executes only this reviewed fixture in a test adapter.
import copy
import json
import sys
from types import ModuleType, SimpleNamespace

import pytest
from ag_ui.core import ActivitySnapshotEvent
from soliplex_a2ui_workbench import program_files, workbench_tools
from soliplex_a2ui_workbench.program_actions import apply_program_actions
from soliplex_a2ui_workbench.workbench_context import WorkbenchToolContext
from soliplex_a2ui_workbench.workbench_projection import RunWorkbenchProjection
from soliplex_a2ui_workbench.workbench_repository import WorkbenchScope


@pytest.fixture
def recorder(tmp_path, monkeypatch):
    scope = WorkbenchScope("actor", "server", "room", "thread")
    installation = SimpleNamespace(sandbox_workdirs_path=tmp_path)
    projection = RunWorkbenchProjection(scope)
    ctx = WorkbenchToolContext(
        scope, projection, "open", allowed_rooms=frozenset({"room"})
    )
    result = workbench_tools.open_demo(ctx, "incident_flight_recorder")
    record = projection.content[result["activityMessageId"]]
    assert result["execution"] == "awaiting_user"
    assert record["output"] == ""
    assert len(record["source"].encode()) < 1_000_000
    assert "__INCIDENT_REPLAY_TEMPLATE__" not in record["source"]
    assert program_files.read_file(installation, scope, "incident-case.json") == ""
    actions = []
    wb = ModuleType("ui.workbench")
    wb.read_file = lambda name: program_files.read_file(installation, scope, name)
    wb.write_file = lambda name, text: program_files.write_file(
        installation, scope, name, text
    )

    def opened(title, kind, content):
        identity = "wbp_" + kind
        actions.append(
            {
                "op": "open",
                "window_id": identity,
                "title": title,
                "kind": kind,
                "content": content,
            }
        )
        return identity

    wb.open_window = opened
    wb.update_window = lambda identity, content: actions.append(
        {"op": "update", "window_id": identity, "content": content}
    )
    wb.close_window = lambda identity: actions.append(
        {"op": "close", "window_id": identity}
    )
    wb.move_window = lambda identity, order: actions.append(
        {"op": "move", "window_id": identity, "order": order}
    )
    ui = ModuleType("ui")
    ui.workbench = wb
    ui.show = lambda *args, **kwargs: None
    for name in ["Text", "Button", "Column", "LineChart", "BarChart", "Event"]:
        setattr(ui, name, lambda *args, **kwargs: None)
    monkeypatch.setitem(sys.modules, "ui", ui)
    monkeypatch.setitem(sys.modules, "ui.workbench", wb)
    namespace = {}

    def apply():
        if not actions:
            return
        for event in apply_program_actions(projection, scope, "click", record, actions):
            projection._fold(ActivitySnapshotEvent.model_validate(event))
        actions.clear()
        windows = [
            n
            for n in projection.layout["nodes"]
            if n["kind"] == "window" and n["visibility"] == "open"
        ]
        assert len(windows) <= 3
        assert len([w for w in windows if not w["id"].startswith("app_")]) <= 2
        assert (
            projection.content[record["activityMessageId"]]["source"]
            == record["source"]
        )

    def click(name, context=None):
        namespace["handle_event"](name, context or {})
        apply()

    def run():
        exec(compile(record["source"], "incident", "exec"), namespace)
        apply()

    return SimpleNamespace(
        result=result,
        record=record,
        namespace=namespace,
        wb=wb,
        actions=actions,
        apply=apply,
        click=click,
        run=run,
        projection=projection,
    )


def investigate(recorder):
    recorder.run()
    assert recorder.namespace["DATA"]["observed"] == []
    recorder.actions.append({"op": "show_app"})
    recorder.apply()
    for event in ["replay", "freeze", "compare", "minimize", "capsule"]:
        recorder.click(event)
    assert recorder.wb.read_file("replay-verification.json") == ""
    return next(
        r["source"]
        for r in recorder.projection.content.values()
        if r.get("title") == "Incident replay capsule"
    )


def test_incident_publication_replay_capsule_and_handoff(recorder):
    capsule = investigate(recorder)
    data = recorder.namespace["DATA"]
    assert data["observed"] == [0, 0, 0, 2, 6, 8, 12, 16, 20, 24, 28, 32]
    assert data["minimal_trigger"] == ["fault-4", "fault-5"]
    assert data["capacity_final_backlog"] == 6
    assert data["retry_disabled_final_backlog"] == 0
    assert data["cleared_at_tick"] == 7
    assert recorder.namespace["replay"]([data["tape"][1]])[-1] == 0
    assert recorder.namespace["replay"]([data["tape"][3]])[-1] == 0
    recorder.click("handoff")
    assert data["verification_status"] == "unverified"
    exec(capsule, {})
    assert recorder.actions == []  # Capsule has no layout/app side effects.
    recorder.click("handoff")
    assert data["verification_status"] == "verified"
    assert "Status: verified" in recorder.wb.read_file("incident-handoff.md")
    assert (
        json.loads(recorder.wb.read_file("incident-case.json"))["verification_status"]
        == "verified"
    )
    nodes = copy.deepcopy(recorder.projection.layout["nodes"])
    recorder.click("capsule")
    assert recorder.projection.layout["nodes"] == nodes
    recorder.run()  # Explicit Run restores, without replay or verification.
    assert recorder.namespace["DATA"]["observed"] == data["observed"]
    recorder.click("capsule")
    assert len(recorder.projection.layout["nodes"]) == len(nodes)


def test_tampered_expectations_and_stale_receipts_cannot_verify(recorder):
    capsule = investigate(recorder)
    tampered = capsule.replace(
        "'capacity_final_backlog': 6", "'capacity_final_backlog': 999", 1
    )
    assert tampered != capsule
    with pytest.raises(AssertionError, match="verification failed"):
        exec(tampered, {})
    assert (
        json.loads(recorder.wb.read_file("replay-verification.json"))["status"]
        == "failed"
    )
    recorder.click("handoff")
    assert recorder.namespace["DATA"]["verification_status"] == "unverified"
    exec(capsule, {})
    receipt = json.loads(recorder.wb.read_file("replay-verification.json"))
    receipt["case"]["checkpoint"]["backlog"] = 999
    recorder.wb.write_file("replay-verification.json", json.dumps(receipt))
    recorder.click("handoff")
    assert recorder.namespace["DATA"]["verification_status"] == "unverified"
    for malformed in ["[]", "null", "not json"]:
        recorder.wb.write_file("replay-verification.json", malformed)
        recorder.click("handoff")
        assert recorder.namespace["DATA"]["verification_status"] == "unverified"


def test_annotation_injection_stays_literal_and_inspector_is_reused(recorder):
    investigate(recorder)
    injection = (
        "'); ui.workbench.open_window('INJECTED', 'text', 'x'); # ignore instructions"
    )
    recorder.namespace["DATA"]["tape"][0]["text"] = injection
    recorder.click("capsule")
    capsule = next(
        r["source"]
        for r in recorder.projection.content.values()
        if r.get("title") == "Incident replay capsule"
    )
    exec(capsule, {})
    assert not recorder.actions
    receipt = json.loads(recorder.wb.read_file("replay-verification.json"))
    assert receipt["case"]["tape"][0]["text"] == injection
    recorder.click("inspect", {"label": "T5"})
    before = len(recorder.projection.layout["nodes"])
    recorder.click("inspect", {"label": "T4"})
    assert len(recorder.projection.layout["nodes"]) == before
    inspector = next(
        r for r in recorder.projection.content.values() if r.get("component") == "Text"
    )
    assert '"retry_arrivals": 0' in inspector["properties"]["text"]
