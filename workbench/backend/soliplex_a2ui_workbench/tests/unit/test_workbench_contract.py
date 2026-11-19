"""Cross-language workbench fixtures and closed contract checks."""

import hashlib
import json
import re
import signal
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
_EXPECTED_TOOL_NAMES = {
    "get_workbench", "open_panel", "place_form", "show_chart",
    "run_python_client", "run_python_server", "create_container",
    "move_panel", "close_panel", "repair_program",
}
EXPECTED = {
    "content_v1.json": "cdafd25c553cf668cf02e7f91fbe1e8c61d3af9dc99c4385d3729478610e90eb",
    "export_action_v1.json": "a855f678939f4c955576a19be3a7902df45bc70e7ae9e4460ecc47a9f2452606",
    "handoff_pointer_v1.json": "257e670dc3261bce37ececea2ed2744a5bdef4ef052014907e37ac4b95659936",
    "intake_action_v1.json": "4158e1b2110a938b8678189f36594607c4ddb7bac1eb0ccffde4fad72c5e42c1",
    "layout_rejections_v1.json": "66a696c0f7424657c09bc2ab922a1f4946a6d2dd8b541b716c33e1dc29a69238",
    "layout_tree_v1.json": "9534b4f57e922c55b288070ed84856fcff33af7f72907f34bebb7f82f4e6e696",
    "nested_tree_v1.json": "c9f314806e63ad08debdfaf961ae054c7c26e0001e79fa320000454cdffe9e0c",
    "python_sides_v1.json": "e02f91610459c62479b6c78981a952e51353994577afd537469ef97a3308e8c0",
}
_REGISTERED_PROGRAM_SURFACES = {"surface_python"}


def fixture(name: str) -> dict[str, object]:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def validate_layout(data: dict[str, object]) -> LayoutSnapshot:
    nodes = data["nodes"]
    surface_ids = {
        node.get("payload", {}).get("surfaceId")
        for node in nodes
        if node.get("kind") == "surface"
        and isinstance(node.get("payload", {}).get("surfaceId"), str)
    }
    return LayoutSnapshot.model_validate(
        data,
        context={
            "authenticated_program_surfaces": _REGISTERED_PROGRAM_SURFACES
            & surface_ids
        },
    )


def test_fixture_digests_match_expected_contract() -> None:
    assert set(EXPECTED) == {path.name for path in FIXTURES.glob("*.json")}
    for name, expected in EXPECTED.items():
        digest = hashlib.sha256((FIXTURES / name).read_bytes()).hexdigest()
        assert digest == expected


@pytest.mark.parametrize("name", ["layout_tree_v1.json", "nested_tree_v1.json"])
def test_layout_fixtures_round_trip(name: str) -> None:
    snapshot = validate_layout(fixture(name))
    assert LayoutSnapshot.model_validate_json(
        snapshot.model_dump_json(),
        context={"authenticated_program_surfaces": _REGISTERED_PROGRAM_SURFACES},
    ) == snapshot
    assert isinstance(snapshot.layoutRevision, int)


def test_nested_fixture_carries_required_surfaces() -> None:
    snapshot = validate_layout(fixture("nested_tree_v1.json"))
    ids = {node.id for node in snapshot.nodes}
    assert {"left_tabs", "chart_surface", "program_surface", "help_surface"} <= ids
    assert _max_depth(snapshot) == 8


def test_rejection_fixture_catalog_records_contract_cases() -> None:
    fixture_cases = set(fixture("layout_rejections_v1.json")["cases"])
    rejection_cases = _rejection_cases()
    assert fixture_cases == set(rejection_cases)
    for name, (operation, expected_reason) in rejection_cases.items():
        with pytest.raises((ValidationError, ValueError)) as raised:
            operation()
        assert expected_reason in str(raised.value), name
    accepted = fixture("layout_rejections_v1.json")
    assert accepted["depth8"] == "accepted"
    assert accepted["depth9"] == "rejected"
    for name in ("layout_tree_v1.json", "nested_tree_v1.json"):
        validate_layout(fixture(name))
    assert _max_depth(validate_layout(fixture("nested_tree_v1.json"))) == 8


def _rejection_cases() -> dict[str, tuple[object, str]]:
    tree = fixture("layout_tree_v1.json")
    nested = fixture("nested_tree_v1.json")
    duplicate = deepcopy(tree)
    duplicate["nodes"].append(deepcopy(duplicate["nodes"][-1]))
    orphan = deepcopy(tree)
    orphan["nodes"].append({"id": "orphan", "parentId": None, "children": [], "kind": "panel", "title": "Orphan", "size": "medium", "visibility": "open", "payload": {}})
    inconsistent = deepcopy(tree)
    next(node for node in inconsistent["nodes"] if node["id"] == "r_left")["children"] = ["r_right"]
    wrong_parent = deepcopy(tree)
    left = next(node for node in wrong_parent["nodes"] if node["id"] == "r_left")
    left["children"] = ["orphan_surface"]
    wrong_parent["nodes"].append({"id": "orphan_surface", "parentId": "r_left", "children": [], "kind": "surface", "title": "Wrong", "size": "medium", "visibility": "open", "payload": {"activityMessageId": "activity_wrong", "surfaceId": "surface_wrong"}})
    protected_chat = deepcopy(tree)
    chat = next(node for node in protected_chat["nodes"] if node["id"] == "r_chat")
    chat["children"] = ["chat_panel"]
    protected_chat["nodes"].append({"id": "chat_panel", "parentId": "r_chat", "children": [], "kind": "panel", "title": "Illegal", "size": "medium", "visibility": "open", "payload": {}})
    duplicate_mount = deepcopy(nested)
    duplicate_by_id = {node["id"]: node for node in duplicate_mount["nodes"]}
    duplicate_by_id["chart_surface"]["payload"] = duplicate_by_id["form_surface"]["payload"]
    cross_scope = validate_layout(nested)
    scoped_mounts = {
        (node.payload["activityMessageId"], node.payload["surfaceId"])
        for node in cross_scope.nodes if node.kind == "surface"
    }
    point = {"id": "p", "label": "Point", "value": 1}
    duplicate_points = [point, {**point, "label": "Duplicate"}]
    oversized = deepcopy(tree)
    oversized["shared"] = {"large": "é" * 33_000}
    return {
        "cycle": (_cycle_validation, "cycle"),
        "duplicate_id": (lambda: validate_layout(duplicate), "duplicate or missing root id"),
        "depth_9": (_depth_nine_validation, "maximum depth exceeded"),
        "orphan": (lambda: validate_layout(orphan), "orphan node"),
        "inconsistent_children": (lambda: validate_layout(inconsistent), "inconsistent child edge"),
        "wrong_parent_kind": (lambda: validate_layout(wrong_parent), "wrong parent kind"),
        "protected_chat_mutation": (lambda: validate_layout(protected_chat), "chat and tray cannot have children"),
        "duplicate_mount": (lambda: validate_layout(duplicate_mount), "duplicate mount"),
        "cross_scope_mount": (lambda: validate_registered_mounts(cross_scope, scoped_mounts - {("activity_form", "surface_form")}), "not registered in this scope"),
        "point_bool": (lambda: Point.model_validate({"id": "p", "label": "P", "value": True}), "valid number"),
        "point_null": (lambda: Point.model_validate({"id": "p", "label": "P", "value": None}), "valid number"),
        "point_nan": (lambda: Point.model_validate({"id": "p", "label": "P", "value": float("nan")}), "finite number"),
        "duplicate_point_id": (lambda: ShowChart.model_validate({"title": "Chart", "kind": "bar", "points": duplicate_points, "parent_id": "r_canvas"}), "point ids must be unique"),
        "oversized_utf8": (lambda: validate_layout(oversized), "64 KiB"),
    }


def _cycle_validation() -> None:
    candidate = fixture("layout_tree_v1.json")
    candidate["nodes"].extend([
        {"id": "program_surface", "parentId": "program_panel", "children": [], "kind": "surface", "title": "Program", "size": "medium", "visibility": "open", "payload": {"activityMessageId": "activity_program", "surfaceId": "program_surface"}},
        {"id": "cycle_tabs", "parentId": "cycle_split", "children": ["cycle_split", "program_panel"], "kind": "tabs", "title": "Cycle tabs", "size": "medium", "visibility": "open", "payload": {}},
        {"id": "cycle_split", "parentId": "cycle_tabs", "children": ["cycle_tabs"], "kind": "split", "title": "Cycle split", "size": "medium", "visibility": "open", "payload": {"axis": "horizontal"}},
        {"id": "program_panel", "parentId": "cycle_tabs", "children": ["program_surface"], "kind": "panel", "title": "Program", "size": "medium", "visibility": "open", "payload": {}},
    ])
    _validate_disconnected_cycle(candidate)


def _validate_disconnected_cycle(candidate: dict[str, object]) -> None:
    previous_handler = signal.signal(signal.SIGALRM, _alarm_timeout)
    signal.alarm(1)
    try:
        LayoutSnapshot.model_validate(
            candidate,
            context={"authenticated_program_surfaces": {"program_surface"}},
        )
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, previous_handler)


def _depth_nine_validation() -> None:
    candidate = fixture("nested_tree_v1.json")
    by_id = {node["id"]: node for node in candidate["nodes"]}
    by_id["depth_split"]["children"].append("depth_split_2")
    candidate["nodes"].extend([
        {"id": "depth_split_2", "parentId": "depth_split", "children": ["depth_panel_2"], "kind": "split", "title": "Nested", "size": "medium", "visibility": "open", "payload": {"axis": "horizontal"}},
        {"id": "depth_panel_2", "parentId": "depth_split_2", "children": ["depth_surface_2"], "kind": "panel", "title": "Too deep", "size": "medium", "visibility": "open", "payload": {}},
        {"id": "depth_surface_2", "parentId": "depth_panel_2", "children": [], "kind": "surface", "title": "Too deep leaf", "size": "medium", "visibility": "open", "payload": {"activityMessageId": "activity_deep", "surfaceId": "surface_deep"}},
    ])
    validate_layout(candidate)


def test_disconnected_program_cycle_rejects_without_hanging() -> None:
    candidate = fixture("layout_tree_v1.json")
    candidate["nodes"].extend([
        {"id": "program_surface", "parentId": "program_panel", "children": [], "kind": "surface", "title": "Program", "size": "medium", "visibility": "open", "payload": {"activityMessageId": "activity_program", "surfaceId": "program_surface"}},
        {"id": "cycle_tabs", "parentId": "cycle_split", "children": ["cycle_split", "program_panel"], "kind": "tabs", "title": "Cycle tabs", "size": "medium", "visibility": "open", "payload": {}},
        {"id": "cycle_split", "parentId": "cycle_tabs", "children": ["cycle_tabs"], "kind": "split", "title": "Cycle split", "size": "medium", "visibility": "open", "payload": {"axis": "horizontal"}},
        {"id": "program_panel", "parentId": "cycle_tabs", "children": ["program_surface"], "kind": "panel", "title": "Program", "size": "medium", "visibility": "open", "payload": {}},
    ])
    previous_handler = signal.signal(signal.SIGALRM, _alarm_timeout)
    signal.alarm(1)
    try:
        with pytest.raises(ValidationError, match="cycle"):
            LayoutSnapshot.model_validate(
                candidate,
                context={"authenticated_program_surfaces": {"program_surface"}},
            )
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, previous_handler)


def _alarm_timeout(_signum: int, _frame: object) -> None:
    raise TimeoutError("layout validation exceeded one second")


def test_region_accepts_thirteen_empty_panels() -> None:
    candidate = fixture("layout_tree_v1.json")
    region = next(node for node in candidate["nodes"] if node["id"] == "r_left")
    for index in range(13):
        panel_id = f"empty_panel_{index}"
        region["children"].append(panel_id)
        candidate["nodes"].append({"id": panel_id, "parentId": "r_left", "children": [], "kind": "panel", "title": "Empty", "size": "medium", "visibility": "open", "payload": {}})
    snapshot = validate_layout(candidate)
    assert len(snapshot.nodes) == 19


@pytest.mark.parametrize(
    "engine",
    ["not_the_pinned_engine-999.999.999", "monty-999.999.999"],
)
def test_pointer_rejects_unpinned_engine(engine: str) -> None:
    pointer = fixture("handoff_pointer_v1.json")
    with pytest.raises(ValidationError, match="pinned engine manifest"):
        InterpreterStatePointer.model_validate(
            {**pointer, "engine": engine},
            context={"pinned_engine_manifest": {"monty-1.3.0"}},
        )


def test_pointer_accepts_engine_from_caller_pinned_manifest() -> None:
    pointer = fixture("handoff_pointer_v1.json")
    engine = "custom_monty-2.3.4"
    validated = InterpreterStatePointer.model_validate(
        {**pointer, "engine": engine},
        context={"pinned_engine_manifest": {engine}},
    )
    assert validated.engine == engine


@pytest.mark.parametrize(
    ("node_id", "visibility"),
    [("wb_root", "closed"), ("r_chat", "minimized"), ("r_left", "closed"), ("r_right", "minimized"), ("r_canvas", "closed"), ("r_tray", "minimized")],
)
def test_reserved_nodes_must_remain_open(node_id: str, visibility: str) -> None:
    candidate = fixture("layout_tree_v1.json")
    next(node for node in candidate["nodes"] if node["id"] == node_id)["visibility"] = visibility
    with pytest.raises(ValidationError, match="reserved nodes must remain open"):
        validate_layout(candidate)


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
            validate_layout(candidate)


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
            validate_layout(candidate)


def test_registered_program_surface_requires_window_ancestry() -> None:
    candidate = fixture("nested_tree_v1.json")
    with pytest.raises(ValidationError, match="authenticated program registration metadata"):
        LayoutSnapshot.model_validate(candidate)
    by_id = {node["id"]: node for node in candidate["nodes"]}
    by_id["window_split"]["children"].remove("program_panel")
    by_id["r_right"]["children"].append("program_panel")
    by_id["program_panel"]["parentId"] = "r_right"
    with pytest.raises(ValidationError, match="program surface requires window ancestry"):
        LayoutSnapshot.model_validate(
            candidate, context={"authenticated_program_surfaces": {"surface_python"}}
        )


def _add_surfaces(snapshot: dict[str, object], target_count: int) -> dict[str, object]:
    result = deepcopy(snapshot)
    nodes = result["nodes"]
    surfaces = sum(node["kind"] == "surface" for node in nodes)
    region = next(node for node in nodes if node["id"] == "r_right")
    for index in range(target_count - surfaces):
        panel_id = f"capacity_panel_{index}"
        surface_id = f"capacity_surface_{index}"
        region["children"].append(panel_id)
        nodes.extend([
            {"id": panel_id, "parentId": "r_right", "children": [surface_id], "kind": "panel", "title": "Capacity", "size": "medium", "visibility": "open", "payload": {}},
            {"id": surface_id, "parentId": panel_id, "children": [], "kind": "surface", "title": "Capacity", "size": "medium", "visibility": "open", "payload": {"activityMessageId": f"activity_{index}", "surfaceId": surface_id}},
        ])
    return result


def _add_windows(snapshot: dict[str, object], target_count: int) -> dict[str, object]:
    result = deepcopy(snapshot)
    nodes = result["nodes"]
    canvas = next(node for node in nodes if node["id"] == "r_canvas")
    windows = sum(node["kind"] == "window" for node in nodes)
    for index in range(target_count - windows):
        window_id = f"capacity_window_{index}"
        canvas["children"].append(window_id)
        nodes.append({"id": window_id, "parentId": "r_canvas", "children": [], "kind": "window", "title": "Window", "size": "medium", "visibility": "open", "payload": {}})
    return result


def test_open_mount_capacity_counts_effective_visibility() -> None:
    source = fixture("nested_tree_v1.json")
    twelve_mounts = _add_surfaces(source, 12)
    LayoutSnapshot.model_validate(twelve_mounts, context={"authenticated_program_surfaces": {"surface_python"}})
    with pytest.raises(ValidationError, match="open content mount capacity"):
        LayoutSnapshot.model_validate(_add_surfaces(source, 13), context={"authenticated_program_surfaces": {"surface_python"}})
    hidden_mounts = _add_surfaces(source, 13)
    next(node for node in hidden_mounts["nodes"] if node["id"] == "capacity_panel_0")["visibility"] = "closed"
    LayoutSnapshot.model_validate(hidden_mounts, context={"authenticated_program_surfaces": {"surface_python"}})


def test_expanded_window_capacity_counts_effective_visibility() -> None:
    source = fixture("nested_tree_v1.json")
    LayoutSnapshot.model_validate(_add_windows(source, 2), context={"authenticated_program_surfaces": {"surface_python"}})
    with pytest.raises(ValidationError, match="expanded window capacity"):
        LayoutSnapshot.model_validate(_add_windows(source, 3), context={"authenticated_program_surfaces": {"surface_python"}})
    hidden_window = _add_windows(source, 3)
    next(node for node in hidden_window["nodes"] if node["id"] == "capacity_window_1")["visibility"] = "closed"
    LayoutSnapshot.model_validate(hidden_window, context={"authenticated_program_surfaces": {"surface_python"}})


def test_surface_payload_identifiers_are_validated_as_ids() -> None:
    candidate = fixture("nested_tree_v1.json")
    surface = next(node for node in candidate["nodes"] if node["id"] == "form_surface")
    surface["payload"] = {"activityMessageId": {"bad": "object"}, "surfaceId": 42}
    with pytest.raises(ValidationError):
        LayoutSnapshot.model_validate(candidate, context={"authenticated_program_surfaces": {"surface_python"}})


def test_run_result_is_client_only_and_requires_versioned_engine() -> None:
    result = fixture("python_sides_v1.json")["runResult"]
    for invalid in (
        {**result, "side": "server"},
        {**result, "engine": "unversioned"},
    ):
        with pytest.raises(ValidationError):
            RunResult.model_validate(invalid)


def test_authenticated_registration_rejects_cross_scope_mount() -> None:
    snapshot = validate_layout(fixture("nested_tree_v1.json"))
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
    original = validate_layout(source)
    moved = deepcopy(source)
    by_id = {node["id"]: node for node in moved["nodes"]}
    by_id["r_left"]["children"].remove("left_panel")
    by_id["r_right"]["children"].append("left_panel")
    by_id["left_panel"]["parentId"] = "r_right"
    moved_tree = validate_layout(moved)
    assert {node.id for node in original.nodes} == {node.id for node in moved_tree.nodes}
    closed = deepcopy(moved)
    closed_by_id = {node["id"]: node for node in closed["nodes"]}
    closed_by_id["left_panel"]["visibility"] = "closed"
    closed_tree = validate_layout(closed)
    surface = next(node for node in closed_tree.nodes if node.id == "form_surface")
    assert surface.visibility == "open"
    assert is_effectively_closed(closed_tree, surface.id)


def test_layout_rejects_depth_nine_after_nested_reparenting() -> None:
    candidate = fixture("nested_tree_v1.json")
    nodes = candidate["nodes"]
    by_id = {node["id"]: node for node in nodes}
    by_id["depth_split"]["children"].append("depth_split_2")
    nodes.extend([
        {"id": "depth_split_2", "parentId": "depth_split", "children": ["depth_panel_2"], "kind": "split", "title": "Nested", "size": "medium", "visibility": "open", "payload": {"axis": "horizontal"}},
        {"id": "depth_panel_2", "parentId": "depth_split_2", "children": ["depth_surface_2"], "kind": "panel", "title": "Too deep", "size": "medium", "visibility": "open", "payload": {}},
        {"id": "depth_surface_2", "parentId": "depth_panel_2", "children": [], "kind": "surface", "title": "Too deep leaf", "size": "medium", "visibility": "open", "payload": {"activityMessageId": "activity_deep", "surfaceId": "surface_deep"}},
    ])
    assert by_id["depth_split"]["children"] == ["depth_panel", "depth_split_2"]
    with pytest.raises(ValidationError, match="maximum depth exceeded"):
        validate_layout(candidate)


def test_tool_schemas_are_closed_and_minimum_only() -> None:
    tools = [GetWorkbench, OpenPanel, PlaceForm, ShowChart, RunPythonClient, RunPythonServer, CreateContainer, MovePanel, ClosePanel, RepairProgram]
    callable_names = {_callable_name(tool.__name__) for tool in tools}
    _assert_tool_names(callable_names)
    for tool in tools:
        schema = tool.model_json_schema()
        assert schema["additionalProperties"] is False
        assert len(schema.get("properties", {})) <= 5
        assert _all_objects_closed(schema)
    assert "selection_group" not in ShowChart.model_fields


def _callable_name(model_name: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", model_name).lower()


def _assert_tool_names(names: set[str]) -> None:
    assert names == _EXPECTED_TOOL_NAMES


def test_show_table_model_name_maps_to_its_real_callable_name() -> None:
    assert _callable_name("ShowTable") == "show_table"
    with pytest.raises(AssertionError):
        _assert_tool_names(_EXPECTED_TOOL_NAMES | {_callable_name("ShowTable")})


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
