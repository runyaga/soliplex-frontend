"""Cross-language workbench fixtures and closed contract checks."""

import hashlib
import json
from copy import deepcopy
from pathlib import Path

import pytest
from pydantic import ValidationError

from soliplex_a2ui_workbench.workbench_schemas import (
    ActionEnvelope,
    ClosePanel,
    CreateContainer,
    ExportChart,
    GetWorkbench,
    InterpreterStatePointer,
    LayoutSnapshot,
    MovePanel,
    OpenPanel,
    PlaceForm,
    Point,
    RepairProgram,
    RunPythonClient,
    RunPythonServer,
    RunResult,
    ServerPythonNotEnabled,
    ShowChart,
    is_effectively_closed,
    validate_pointer_owner,
    validate_registered_mounts,
)

FIXTURES = Path(__file__).parents[1] / "fixtures" / "workbench"
EXPECTED = {
    "content_v1.json": "cdafd25c553cf668cf02e7f91fbe1e8c61d3af9dc99c4385d3729478610e90eb",
    "export_action_v1.json": "a855f678939f4c955576a19be3a7902df45bc70e7ae9e4460ecc47a9f2452606",
    "handoff_pointer_v1.json": "55af7cbec8b43f29617badd55b12d9cd72a148c55daca78e689c1bfc220b12eb",
    "intake_action_v1.json": "4158e1b2110a938b8678189f36594607c4ddb7bac1eb0ccffde4fad72c5e42c1",
    "layout_rejections_v1.json": "66a696c0f7424657c09bc2ab922a1f4946a6d2dd8b541b716c33e1dc29a69238",
    "layout_tree_v1.json": "9534b4f57e922c55b288070ed84856fcff33af7f72907f34bebb7f82f4e6e696",
    "nested_tree_v1.json": "c9f314806e63ad08debdfaf961ae054c7c26e0001e79fa320000454cdffe9e0c",
    "python_sides_v1.json": "59059d1915a408804c714f7e4fd58f8d8c3d3f78acbe96bae67faefdee37107e",
}


def fixture(name: str) -> dict[str, object]:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def test_fixture_digests_match_expected_contract() -> None:
    assert set(EXPECTED) == {path.name for path in FIXTURES.glob("*.json")}
    for name, expected in EXPECTED.items():
        digest = hashlib.sha256((FIXTURES / name).read_bytes()).hexdigest()
        assert digest == expected


@pytest.mark.parametrize("name", ["layout_tree_v1.json", "nested_tree_v1.json"])
def test_layout_fixtures_round_trip(name: str) -> None:
    snapshot = LayoutSnapshot.model_validate(fixture(name))
    assert LayoutSnapshot.model_validate_json(snapshot.model_dump_json()) == snapshot
    assert isinstance(snapshot.layoutRevision, int)


def test_nested_fixture_carries_required_surfaces() -> None:
    snapshot = LayoutSnapshot.model_validate(fixture("nested_tree_v1.json"))
    ids = {node.id for node in snapshot.nodes}
    assert {"left_tabs", "chart_surface", "program_surface", "help_surface"} <= ids
    assert _max_depth(snapshot) == 8


def test_rejection_fixture_catalog_records_contract_cases() -> None:
    rejection_fixture = fixture("layout_rejections_v1.json")
    assert rejection_fixture["depth8"] == "accepted"
    assert rejection_fixture["depth9"] == "rejected"
    assert set(rejection_fixture["cases"]) == {
        "cycle", "duplicate_id", "depth_9", "orphan", "inconsistent_children",
        "wrong_parent_kind", "protected_chat_mutation", "duplicate_mount",
        "cross_scope_mount", "point_bool", "point_null", "point_nan",
        "duplicate_point_id", "oversized_utf8",
    }


def _max_depth(snapshot: LayoutSnapshot) -> int:
    nodes = {node.id: node for node in snapshot.nodes}

    def depth(node_id: str) -> int:
        children = nodes[node_id].children
        return 1 + max((depth(child) for child in children), default=0)

    return depth(snapshot.rootId)


def test_closed_models_reject_extra_fields_and_invalid_points() -> None:
    with pytest.raises(ValidationError):
        Point.model_validate({"id": "x", "label": "X", "value": True})
    with pytest.raises(ValidationError):
        PlaceForm.model_validate({"template": "filters", "title": "F", "parent_id": "r_left"})
    with pytest.raises(ValidationError):
        ShowChart.model_validate({"title": "C", "kind": "bar", "points": [{"id": "x", "label": "X", "value": 1}], "parent_id": "r_canvas", "selection_group": "g"})
    for value in (None, float("nan"), float("inf")):
        with pytest.raises(ValidationError):
            Point.model_validate({"id": "x", "label": "X", "value": value})
    with pytest.raises(ValidationError):
        ShowChart.model_validate({"title": "C", "kind": "bar", "parent_id": "r_canvas", "points": [{"id": "x", "label": "X", "value": 1}, {"id": "x", "label": "Again", "value": 2}]})


def test_layout_rejects_duplicate_ids_or_broken_edges() -> None:
    source = fixture("layout_tree_v1.json")
    duplicate = deepcopy(source)
    duplicate["nodes"].append(deepcopy(duplicate["nodes"][-1]))
    broken_edge = deepcopy(source)
    broken_edge["nodes"][0]["children"].pop()
    orphan = deepcopy(source)
    orphan["nodes"].append({"id": "orphan", "parentId": None, "children": [], "kind": "panel", "title": "Orphan", "size": "medium", "visibility": "open", "payload": {}})
    oversized = deepcopy(source)
    oversized["shared"] = {"large": "é" * 33_000}
    for candidate in (duplicate, broken_edge, orphan, oversized):
        with pytest.raises(ValidationError):
            LayoutSnapshot.model_validate(candidate)


def test_layout_rejects_cycle_protected_chat_and_duplicate_mount() -> None:
    source = fixture("nested_tree_v1.json")
    cycle = deepcopy(source)
    by_id = {node["id"]: node for node in cycle["nodes"]}
    by_id["r_left"]["children"] = []
    by_id["left_panel"]["parentId"] = "left_tabs"
    by_id["left_panel"]["children"] = ["left_tabs"]
    by_id["left_tabs"]["parentId"] = "left_panel"
    by_id["left_tabs"]["children"] = ["left_panel"]
    protected_chat = deepcopy(source)
    protected_by_id = {node["id"]: node for node in protected_chat["nodes"]}
    protected_by_id["r_chat"]["children"] = ["chat_panel"]
    protected_chat["nodes"].append({"id": "chat_panel", "parentId": "r_chat", "children": [], "kind": "panel", "title": "Illegal", "size": "medium", "visibility": "open", "payload": {}})
    duplicate_mount = deepcopy(source)
    duplicate_by_id = {node["id"]: node for node in duplicate_mount["nodes"]}
    duplicate_by_id["chart_surface"]["payload"] = duplicate_by_id["form_surface"]["payload"]
    for candidate in (cycle, protected_chat, duplicate_mount):
        with pytest.raises(ValidationError):
            LayoutSnapshot.model_validate(candidate)


def test_authenticated_registration_rejects_cross_scope_mount() -> None:
    snapshot = LayoutSnapshot.model_validate(fixture("nested_tree_v1.json"))
    scoped_mounts = {
        (str(node.payload["activityMessageId"]), str(node.payload["surfaceId"]))
        for node in snapshot.nodes
        if node.kind == "surface"
    }
    validate_registered_mounts(snapshot, scoped_mounts)
    with pytest.raises(ValueError, match="not registered in this scope"):
        validate_registered_mounts(snapshot, scoped_mounts - {("activity_form", "surface_form")})


def test_parent_move_preserves_ids_and_close_preserves_descendant_visibility() -> None:
    source = fixture("nested_tree_v1.json")
    original = LayoutSnapshot.model_validate(source)
    moved = deepcopy(source)
    by_id = {node["id"]: node for node in moved["nodes"]}
    by_id["r_left"]["children"].remove("left_panel")
    by_id["r_right"]["children"].append("left_panel")
    by_id["left_panel"]["parentId"] = "r_right"
    moved_tree = LayoutSnapshot.model_validate(moved)
    assert {node.id for node in original.nodes} == {node.id for node in moved_tree.nodes}
    closed = deepcopy(moved)
    closed_by_id = {node["id"]: node for node in closed["nodes"]}
    closed_by_id["left_panel"]["visibility"] = "closed"
    closed_tree = LayoutSnapshot.model_validate(closed)
    surface = next(node for node in closed_tree.nodes if node.id == "form_surface")
    assert surface.visibility == "open"
    assert is_effectively_closed(closed_tree, surface.id)


def test_layout_rejects_depth_nine_after_nested_reparenting() -> None:
    candidate = fixture("nested_tree_v1.json")
    nodes = candidate["nodes"]
    by_id = {node["id"]: node for node in nodes}
    by_id["depth_split"]["children"] = ["depth_split_2"]
    nodes.extend([
        {"id": "depth_split_2", "parentId": "depth_split", "children": ["depth_panel_2"], "kind": "split", "title": "Nested", "size": "medium", "visibility": "open", "payload": {"axis": "horizontal"}},
        {"id": "depth_panel_2", "parentId": "depth_split_2", "children": ["depth_surface_2"], "kind": "panel", "title": "Too deep", "size": "medium", "visibility": "open", "payload": {}},
        {"id": "depth_surface_2", "parentId": "depth_panel_2", "children": [], "kind": "surface", "title": "Too deep leaf", "size": "medium", "visibility": "open", "payload": {"activityMessageId": "activity_deep", "surfaceId": "surface_deep"}},
    ])
    with pytest.raises(ValidationError):
        LayoutSnapshot.model_validate(candidate)


def test_tool_schemas_are_closed_and_minimum_only() -> None:
    tools = [GetWorkbench, OpenPanel, PlaceForm, ShowChart, RunPythonClient, RunPythonServer, CreateContainer, MovePanel, ClosePanel, RepairProgram]
    for tool in tools:
        schema = tool.model_json_schema()
        assert schema["additionalProperties"] is False
        assert len(schema.get("properties", {})) <= 5
        assert _all_objects_closed(schema)
    assert "show_table" not in {tool.__name__.lower() for tool in tools}
    assert "selection_group" not in ShowChart.model_fields


def _all_objects_closed(value: object) -> bool:
    if isinstance(value, dict):
        is_closed = value.get("type") != "object" or value.get("additionalProperties") is False
        return is_closed and all(_all_objects_closed(item) for item in value.values())
    if isinstance(value, list):
        return all(_all_objects_closed(item) for item in value)
    return True


def test_python_side_and_handoff_fixtures_validate() -> None:
    sides = fixture("python_sides_v1.json")
    assert ServerPythonNotEnabled().model_dump() == sides["disabledServerResult"]
    result = RunResult.model_validate(sides["runResult"])
    assert result.side == "client"
    pointer = InterpreterStatePointer.model_validate(fixture("handoff_pointer_v1.json"))
    assert pointer.hop == 0
    for invalid in ({**pointer.model_dump(), "dump": "../dump"}, {**pointer.model_dump(), "hop": 5}, {**pointer.model_dump(), "sha256": "BAD"}):
        with pytest.raises(ValidationError):
            InterpreterStatePointer.model_validate(invalid)
    with pytest.raises(ValidationError):
        InterpreterStatePointer.model_validate({**pointer.model_dump(), "dump": b"dump bytes"})
    with pytest.raises(ValidationError):
        InterpreterStatePointer.model_validate({**pointer.model_dump(), "engine": "monty"})
    with pytest.raises(ValueError, match="authenticated scope"):
        validate_pointer_owner(pointer, "different_actor_thread")
    assert validate_pointer_owner(pointer, pointer.owner) == pointer


def test_source_and_envelope_bounds_are_utf8_aware() -> None:
    with pytest.raises(ValidationError):
        RunPythonClient.model_validate({"title": "Unicode", "source": "é" * 6001, "parent_id": "panel"})
    action = fixture("intake_action_v1.json")
    action["userAction"]["question"] = "x" * 20_000
    with pytest.raises(ValidationError):
        ActionEnvelope.model_validate(action)


def test_action_fixture_and_all_minimum_model_schemas() -> None:
    envelope = ActionEnvelope.model_validate(fixture("intake_action_v1.json"))
    assert envelope.v == 1
    export_envelope = ActionEnvelope.model_validate(fixture("export_action_v1.json"))
    assert export_envelope.userAction.kind == "bar"
    assert ExportChart.model_fields.keys() == {"title", "kind", "points"}
