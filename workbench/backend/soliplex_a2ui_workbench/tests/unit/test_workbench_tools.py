"""Behavior of the deterministic minimum workbench tool table."""

import json
from pathlib import Path

import pytest
from soliplex_a2ui_workbench.workbench_context import WorkbenchToolContext
from soliplex_a2ui_workbench.workbench_repository import (
    SQLiteWorkbenchRepository,
    WorkbenchScope,
)
from soliplex_a2ui_workbench.workbench_schemas import MINIMUM_ROOM_TOOL_MANIFEST
from soliplex_a2ui_workbench.workbench_templates import (
    MINIMUM_ROOM_REGISTRATIONS,
    MINIMUM_ROOM_TOOLS,
    validate_room_registrations,
)

FIXTURES = Path(__file__).parents[1] / "fixtures/workbench"


@pytest.fixture
def ctx(tmp_path):
    scope = WorkbenchScope("actor", "server", "room", "thread")
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.db")
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    repo.publish(
        scope,
        "seed",
        0,
        layout,
        [],
        registered_program_surfaces=set(),
        registered_mounts=set(),
    )
    yield WorkbenchToolContext(scope, repo, "run-1", allowed_rooms=frozenset({"room"}))
    repo.close()


def test_tool_table_names_and_schemas_match_manifest():
    validate_room_registrations()
    assert len(MINIMUM_ROOM_REGISTRATIONS) == 2
    for room_tools in MINIMUM_ROOM_REGISTRATIONS:
        assert set(room_tools) == set(MINIMUM_ROOM_TOOL_MANIFEST)
        assert "show_table" not in room_tools
        for name, schema in MINIMUM_ROOM_TOOL_MANIFEST.items():
            assert room_tools[name].input_model is schema


def test_form_chart_and_get_workbench_publish_successive_revisions(ctx):
    form = MINIMUM_ROOM_TOOLS["place_form"].function(
        ctx, title="Intake", template="intake", parent_id="r_left"
    )
    chart = MINIMUM_ROOM_TOOLS["show_chart"].function(
        ctx,
        title="Counts",
        kind="bar",
        points=[{"id": "north", "label": "North", "value": 80}],
        parent_id="r_canvas",
    )
    state = MINIMUM_ROOM_TOOLS["get_workbench"].function(ctx)
    assert (
        form["layoutRevision"] == 2
        and chart["layoutRevision"] == 3
        and state["layoutRevision"] == 3
    )
    chart_record = next(
        row
        for row in ctx.repository.load_snapshot(ctx.scope)["content"]
        if row["component"] == "Chart"
    )
    assert chart_record["spec"] == {
        "kind": "bar", "title": "Counts",
        "points": [{"id": "north", "label": "North", "value": 80}],
    }


def test_python_client_is_inert_and_server_returns_disabled_without_mutation(ctx):
    tools = MINIMUM_ROOM_TOOLS
    window = tools["create_container"].function(
        ctx, parent_id="r_canvas", kind="window", title="Program"
    )
    result = tools["run_python_client"].function(
        ctx, title="Demo", source="print(1)", parent_id=window["nodeId"]
    )
    assert result["side"] == "client" and result["execution"] == "awaiting_user"
    from soliplex_a2ui_workbench.workbench_publication import (
        BUILTIN_CATALOG_MANIFESTS,
        WorkbenchCatalogValidator,
        build_publication,
    )

    state = ctx.repository.load_snapshot(ctx.scope)
    record = {
        key: value
        for key, value in next(
            item
            for item in state["content"]
            if item["surfaceId"] == result["surfaceId"]
        ).items()
        if key != "workbenchCommit"
    }
    emitted_plan = build_publication(
        [record],
        WorkbenchCatalogValidator(),
        BUILTIN_CATALOG_MANIFESTS,
        layout=state["layout"],
        registered_program_surfaces={result["surfaceId"]},
    )
    event = next(
        event for event in emitted_plan["events"] if event["kind"] == "content"
    )
    emitted = event["event"]["content"]["a2ui_operations"]
    assert emitted[1]["updateDataModel"]["value"]["output"] == ""
    component = emitted[2]["updateComponents"]["components"][0]
    assert component["@catalogId"] == "urn:soliplex:catalog:lab:1"
    assert (
        component["source"] == {"@path": "/source"}
        and component["outputPath"] == "/output"
    )
    before = ctx.repository.load_snapshot(ctx.scope)
    disabled = tools["run_python_server"].function(
        ctx, surface_id=result["surfaceId"], source="print(2)"
    )
    assert disabled == {
        "status": "not_enabled",
        "code": "server_runner_deferred",
        "tool": "run_python_server",
        "side": "server",
        "execution": "disabled",
    }
    assert ctx.repository.load_snapshot(ctx.scope) == before


def test_closed_and_move_preserve_subtree_identity(ctx):
    tools = MINIMUM_ROOM_TOOLS
    created = tools["create_container"].function(
        ctx, parent_id="r_left", kind="panel", title="Panel"
    )
    moved = tools["move_panel"].function(
        ctx, node_id=created["nodeId"], parent_id="r_right", order=0, size="large"
    )
    assert moved["layoutRevision"] == created["layoutRevision"] + 1
    closed = tools["close_panel"].function(ctx, node_id=created["nodeId"])
    assert closed["layoutRevision"] == moved["layoutRevision"] + 1
    snapshot = ctx.repository.load_snapshot(ctx.scope)["layout"]
    assert (
        next(node for node in snapshot["nodes"] if node["id"] == created["nodeId"])[
            "visibility"
        ]
        == "closed"
    )


def test_unknown_room_fails_closed_before_repository_access():
    class NeverRepository:
        def load_snapshot(self, _scope):
            pytest.fail("repository touched for an unconfigured room")

    ctx = WorkbenchToolContext(
        WorkbenchScope("a", "s", "foreign", "t"),
        NeverRepository(),
        "run",
        allowed_rooms=frozenset({"room"}),
    )
    with pytest.raises(PermissionError, match="SOLIPLEX_WORKBENCH_ROOMS"):
        MINIMUM_ROOM_TOOLS["get_workbench"].function(ctx)


def test_invalid_mutation_is_atomic_and_move_preserves_descendants(ctx):
    tools = MINIMUM_ROOM_TOOLS
    parent = tools["create_container"].function(
        ctx, parent_id="r_left", kind="tabs", title="Tabs"
    )
    child = tools["create_container"].function(
        ctx, parent_id=parent["nodeId"], kind="panel", title="Panel"
    )
    before = ctx.repository.load_snapshot(ctx.scope)
    with pytest.raises(ValueError):
        tools["move_panel"].function(
            ctx,
            node_id=parent["nodeId"],
            parent_id=child["nodeId"],
            order=0,
            size="large",
        )
    assert ctx.repository.load_snapshot(ctx.scope) == before
    moved = tools["move_panel"].function(
        ctx, node_id=parent["nodeId"], parent_id="r_right", order=0, size="large"
    )
    tree = ctx.repository.load_snapshot(ctx.scope)["layout"]
    preserved = next(node for node in tree["nodes"] if node["id"] == child["nodeId"])
    assert moved["layoutRevision"] == before["revision"] + 1
    assert (
        preserved["id"] == child["nodeId"] and preserved["parentId"] == parent["nodeId"]
    )


def test_stale_turn_cannot_overwrite_a_successful_tool_mutation(tmp_path):
    scope = WorkbenchScope("actor", "server", "room", "thread")
    repo = SQLiteWorkbenchRepository(tmp_path / "stale.db")
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    repo.publish(
        scope,
        "seed",
        0,
        layout,
        [],
        registered_program_surfaces=set(),
        registered_mounts=set(),
    )
    first = WorkbenchToolContext(
        scope, repo, "first", allowed_rooms=frozenset({"room"})
    )
    second = WorkbenchToolContext(
        scope, repo, "second", allowed_rooms=frozenset({"room"})
    )
    MINIMUM_ROOM_TOOLS["create_container"].function(
        first, parent_id="r_left", kind="panel", title="One"
    )
    with pytest.raises(Exception, match="stale"):
        MINIMUM_ROOM_TOOLS["create_container"].function(
            second, parent_id="r_right", kind="panel", title="Two"
        )
    repo.close()


def test_tray_accepts_published_content(ctx):
    result = MINIMUM_ROOM_TOOLS["open_panel"].function(
        ctx, title="Tray note", text="Visible below the workspace", parent_id="r_tray"
    )
    layout = ctx.repository.load_snapshot(ctx.scope)["layout"]
    assert next(node for node in layout["nodes"] if node["id"] == "r_tray")["children"]
    assert result["events"][-1]["kind"] == "layout"


@pytest.mark.parametrize("target", ["window", "surface", "replace"])
def test_program_revision_preserves_mount_window_and_position_without_execution(
    ctx, target
):
    from soliplex_a2ui_workbench import workbench_tools as tools

    window = tools.create_container(ctx, "r_canvas", "window", "Tally")
    program = tools.run_python_client(
        ctx, "Tally", 'import ui\nui.Label("bad")', window["nodeId"]
    )
    before = ctx.snapshot()
    if target == "replace":
        result = tools.run_python_client(
            ctx,
            "Tally",
            'import ui\nui.show(ui.Text("fixed"))',
            window["nodeId"],
            replace=True,
        )
    else:
        result = tools.repair_program(
            ctx,
            window["nodeId"] if target == "window" else program["nodeId"],
            'import ui\nui.show(ui.Text("fixed"))',
        )
    after = ctx.snapshot()
    assert after["layout"]["nodes"] == before["layout"]["nodes"]
    assert result["surfaceId"] == program["surfaceId"]
    assert result["nodeId"] == program["nodeId"]
    assert result["execution"] == "client_controlled"
    assert "autoRun=true runs automatically" in result["instruction"]
    assert "otherwise say press Run" in result["instruction"]
    content = next(r for r in after["content"] if r["surfaceId"] == result["surfaceId"])
    assert content["source"].endswith('ui.show(ui.Text("fixed"))')
    assert content["activityMessageId"] == program["activityMessageId"]
    emitted = next(e["event"] for e in result["events"] if e["kind"] == "content")
    assert (
        "retry"
        not in emitted["content"]["a2ui_operations"][-1]["updateComponents"][
            "components"
        ][0]
    )


def test_repair_reopens_a_previously_closed_program_leaf(ctx):
    from soliplex_a2ui_workbench import workbench_tools as tools

    window = tools.create_container(ctx, "r_canvas", "window", "Tally")
    program = tools.run_python_client(ctx, "Tally", 'print("old")', window["nodeId"])
    # Reproduce a historical closed leaf; close_panel now closes its window.
    layout = ctx.snapshot()["layout"]
    next(n for n in layout["nodes"] if n["id"] == program["nodeId"])["visibility"] = (
        "closed"
    )
    tools._publish(ctx, layout)
    result = tools.repair_program(ctx, window["nodeId"], 'print("fixed")')
    layout = ctx.snapshot()["layout"]
    assert (
        next(n for n in layout["nodes"] if n["id"] == program["nodeId"])["visibility"]
        == "open"
    )
    assert (
        next(n for n in layout["nodes"] if n["id"] == window["nodeId"])["visibility"]
        == "open"
    )
    assert result["execution"] == "client_controlled"


@pytest.mark.parametrize("tool_name", ["run_python_client", "repair_program"])
@pytest.mark.parametrize("parent_kind", ["region", "split", "tabs", "panel", "window"])
def test_program_container_parent_creates_only_the_needed_window_atomically(
    ctx, tool_name, parent_kind
):
    from soliplex_a2ui_workbench import workbench_tools as tools

    parent_id = "r_canvas"
    if parent_kind != "region":
        parent_id = tools.create_container(ctx, parent_id, parent_kind, "Parent")[
            "nodeId"
        ]
    before = ctx.snapshot()
    result = getattr(tools, tool_name)(
        ctx, title="Tally", source="print(1)", parent_id=parent_id
    )
    after = ctx.snapshot()
    assert after["revision"] == before["revision"] + 1
    windows = [n for n in after["layout"]["nodes"] if n["kind"] == "window"]
    assert len(windows) == 1
    window = windows[0]
    if parent_kind == "window":
        assert window["id"] == parent_id
    else:
        assert window["title"] == "Tally"
    assert window["children"] == [result["nodeId"]]
    assert result["execution"] == "awaiting_user"
    repaired = tools.repair_program(
        ctx, source="print(2)", parent_id=window["id"], title="Ignored"
    )
    assert repaired["surfaceId"] == result["surfaceId"]
    assert repaired["nodeId"] == result["nodeId"]
    assert ctx.snapshot()["layout"]["nodes"] == after["layout"]["nodes"]


@pytest.mark.parametrize("tool_name", ["run_python_client", "repair_program"])
@pytest.mark.parametrize("parent_id", ["missing", "wb_root", "r_chat", "r_left"])
def test_invalid_program_parent_does_not_publish(ctx, tool_name, parent_id):
    from soliplex_a2ui_workbench import workbench_tools as tools

    before = ctx.snapshot()
    with pytest.raises(ValueError):
        getattr(tools, tool_name)(
            ctx, title="Tally", source="print(1)", parent_id=parent_id
        )
    assert ctx.snapshot() == before


def test_program_in_container_inside_window_does_not_nest_windows(ctx):
    from soliplex_a2ui_workbench import workbench_tools as tools

    window = tools.create_container(ctx, "r_canvas", "window", "Tally")
    # Move a split into the window, retaining the ordinary tree validation.
    split = tools.create_container(ctx, "r_canvas", "split", "Split")
    tools.move_panel(ctx, split["nodeId"], window["nodeId"], 0, "medium")
    tools.run_python_client(ctx, "Tally", "print(1)", split["nodeId"])
    assert (
        len([n for n in ctx.snapshot()["layout"]["nodes"] if n["kind"] == "window"])
        == 1
    )


def test_chart_on_region_does_not_need_a_window(ctx):
    from soliplex_a2ui_workbench import workbench_tools as tools

    tools.show_chart(
        ctx, "Counts", "bar", [{"id": "a", "label": "A", "value": 2}], "r_canvas"
    )
    assert not any(n["kind"] == "window" for n in ctx.snapshot()["layout"]["nodes"])


@pytest.mark.parametrize("operation", ["move_panel", "close_panel"])
@pytest.mark.parametrize("owner_kind", ["panel", "window"])
@pytest.mark.parametrize("target_kind", ["owner", "content"])
def test_panel_tools_accept_owner_or_content_in_one_mutation(
    ctx, operation, owner_kind, target_kind
):
    from soliplex_a2ui_workbench import workbench_tools as tools

    owner = tools.create_container(ctx, "r_canvas", owner_kind, "Owner")["nodeId"]
    content = tools.open_panel(ctx, "Note", "Unchanged", owner)["nodeId"]
    before = ctx.snapshot()
    target = owner if target_kind == "owner" else content
    if operation == "move_panel":
        destination = tools.create_container(ctx, "r_canvas", "tabs", "Destination")[
            "nodeId"
        ]
        before = ctx.snapshot()
        result = tools.move_panel(ctx, target, destination, 0, "large")
    else:
        result = tools.close_panel(ctx, target)
    after = ctx.snapshot()
    nodes = {node["id"]: node for node in after["layout"]["nodes"]}
    assert result["nodeId"] == owner
    assert after["revision"] == before["revision"] + 1 == result["layoutRevision"]
    assert [event["kind"] for event in result["events"]] == ["layout"]
    assert set(nodes) == {node["id"] for node in before["layout"]["nodes"]}

    def content_payload(state):
        return [
            {
                key: value
                for key, value in record.items()
                if key not in {"workbenchCommit", "surfaceRevision"}
            }
            for record in state["content"]
        ]

    assert content_payload(after) == content_payload(before)
    assert nodes[content]["parentId"] == owner
    assert nodes[owner]["children"] == [content]
    if operation == "move_panel":
        assert nodes[owner]["parentId"] == destination
        assert nodes[owner]["size"] == "large"
        assert owner not in nodes["r_canvas"]["children"]
        assert nodes[destination]["children"] == [owner]
    else:
        assert nodes[owner]["visibility"] == "closed"
        assert nodes[content]["visibility"] == "open"


@pytest.mark.parametrize("operation", ["move_panel", "close_panel"])
def test_content_target_uses_nearest_panel_inside_window(ctx, operation):
    from soliplex_a2ui_workbench import workbench_tools as tools

    window = tools.create_container(ctx, "r_canvas", "window", "Window")["nodeId"]
    split = tools.create_container(ctx, "r_canvas", "split", "Split")["nodeId"]
    tools.move_panel(ctx, split, window, 0, "medium")
    content = tools.open_panel(ctx, "Note", "Hello", split)["nodeId"]
    before = ctx.snapshot()
    previous = {node["id"]: node for node in before["layout"]["nodes"]}
    panel = previous[content]["parentId"]
    if operation == "move_panel":
        result = tools.move_panel(ctx, content, "r_right", 0, "large")
    else:
        result = tools.close_panel(ctx, content)
    after = ctx.snapshot()
    nodes = {node["id"]: node for node in after["layout"]["nodes"]}
    assert result["nodeId"] == panel
    assert nodes[window] == previous[window]
    assert nodes[content] == previous[content]
    assert after["revision"] == before["revision"] + 1


def _assert_layout_rejection(ctx, action, *details):
    before = ctx.snapshot()
    revision = ctx.expected_revision
    with pytest.raises(ValueError) as failure:
        action()
    message = str(failure.value)
    for detail in details:
        assert detail in message
    assert ctx.snapshot() == before
    assert ctx.expected_revision == revision


@pytest.mark.parametrize("kind,limit", [("split", 3), ("tabs", 12)])
def test_container_capacity_error_identifies_parent_children_and_alternative(
    ctx, kind, limit
):
    from soliplex_a2ui_workbench import workbench_tools as tools

    parent = tools.create_container(ctx, "r_left", kind, "Full")["nodeId"]
    children = [
        tools.create_container(ctx, parent, "panel", "Child")["nodeId"]
        for _ in range(limit)
    ]
    incoming = tools.create_container(ctx, "r_right", "panel", "Incoming")["nodeId"]
    _assert_layout_rejection(
        ctx,
        lambda: tools.move_panel(ctx, incoming, parent, 0, "medium"),
        f"{kind} capacity exceeded",
        f"{parent} ({kind})",
        f"{children[0]} (panel)",
        f"{incoming} (panel)",
        f"maximum {limit}",
        "move a child",
        "r_canvas",
    )


def test_wrong_parent_and_occupied_parent_errors_give_valid_alternatives(ctx):
    from soliplex_a2ui_workbench import workbench_tools as tools

    panel = tools.create_container(ctx, "r_left", "panel", "Panel")["nodeId"]
    content = tools.open_panel(ctx, "Note", "Text", panel)["nodeId"]
    incoming = tools.create_container(ctx, "r_right", "panel", "Incoming")["nodeId"]
    _assert_layout_rejection(
        ctx,
        lambda: tools.move_panel(ctx, incoming, content, 0, "medium"),
        "wrong parent kind",
        f"{incoming} (panel)",
        f"{content} (surface)",
        "use r_left",
    )
    _assert_layout_rejection(
        ctx,
        lambda: tools.open_panel(ctx, "Extra", "Text", panel),
        f"{panel} (panel)",
        f"{content} (surface)",
        "must be empty",
        "empty panel/window",
    )
    tabs = tools.create_container(ctx, "r_right", "tabs", "Tabs")["nodeId"]
    _assert_layout_rejection(
        ctx,
        lambda: tools.move_panel(ctx, tabs, panel, 0, "medium"),
        "panel capacity exceeded",
        f"{panel} (panel)",
        f"{tabs} (tabs)",
        "maximum 1",
        "empty panel/window",
    )
    _assert_layout_rejection(
        ctx,
        lambda: tools.open_panel(ctx, "Extra", "Text", content),
        f"{content} (surface)",
        "not a container",
        "r_left (region)",
    )
    _assert_layout_rejection(
        ctx,
        lambda: tools.create_container(ctx, panel, "panel", "Extra"),
        f"{panel} (panel)",
        "container parent",
        "r_canvas (region)",
    )


@pytest.mark.parametrize(
    "reserved", ["wb_root", "r_chat", "r_left", "r_right", "r_canvas", "r_tray"]
)
@pytest.mark.parametrize("operation", ["move_panel", "close_panel"])
def test_reserved_node_errors_identify_kind_and_authored_alternative(
    ctx, reserved, operation
):
    from soliplex_a2ui_workbench import workbench_tools as tools

    args = (
        (ctx, reserved, "r_left", 0, "medium")
        if operation == "move_panel"
        else (ctx, reserved)
    )
    _assert_layout_rejection(
        ctx,
        lambda: getattr(tools, operation)(*args),
        f"{reserved} ({'workspace' if reserved == 'wb_root' else 'region'})",
        "protected",
        "authored panel/window",
        "get_workbench",
    )


def test_chat_placement_error_identifies_region_and_alternatives(ctx):
    from soliplex_a2ui_workbench import workbench_tools as tools

    incoming = tools.create_container(ctx, "r_left", "panel", "Panel")["nodeId"]
    _assert_layout_rejection(
        ctx,
        lambda: tools.move_panel(ctx, incoming, "r_chat", 0, "medium"),
        "r_chat (region)",
        f"{incoming} (panel)",
        "chat cannot have children",
        "use r_left (region)",
    )


@pytest.mark.parametrize(
    "operation",
    ["move_panel", "close_panel", "open_panel", "create_container", "repair_program"],
)
def test_unknown_id_error_names_id_and_how_to_find_valid_ids(ctx, operation):
    from soliplex_a2ui_workbench import workbench_tools as tools

    arguments = {
        "move_panel": (ctx, "missing", "r_left", 0, "medium"),
        "close_panel": (ctx, "missing"),
        "open_panel": (ctx, "Title", "Text", "missing"),
        "create_container": (ctx, "missing", "panel", "Title"),
        "repair_program": (ctx, "missing", "print(1)"),
    }
    _assert_layout_rejection(
        ctx,
        lambda: getattr(tools, operation)(*arguments[operation]),
        "unknown workbench node 'missing'",
        "kind unknown",
        "get_workbench",
        "returned node id",
        "r_canvas (region)",
    )


def test_depth_error_names_deep_node_parent_and_shallower_alternative(ctx):
    from soliplex_a2ui_workbench import workbench_tools as tools

    parent = "r_canvas"
    for _ in range(6):
        parent = tools.create_container(ctx, parent, "split", "Deep")["nodeId"]
    incoming = tools.create_container(ctx, "r_left", "panel", "Panel")["nodeId"]
    _assert_layout_rejection(
        ctx,
        lambda: tools.move_panel(ctx, incoming, parent, 0, "medium"),
        "maximum depth exceeded",
        f"{incoming} (panel)",
        f"{parent} (split)",
        "depth 9",
        "maximum 8",
        "shallower parent",
        "r_canvas (region)",
    )


def test_window_ancestry_errors_identify_nodes_and_valid_canvas_placement(ctx):
    from soliplex_a2ui_workbench import workbench_tools as tools

    first = tools.create_container(ctx, "r_canvas", "window", "First")["nodeId"]
    second = tools.create_container(ctx, "r_canvas", "window", "Second")["nodeId"]
    split = tools.create_container(ctx, "r_canvas", "split", "Split")["nodeId"]
    tools.move_panel(ctx, split, first, 0, "medium")
    _assert_layout_rejection(
        ctx,
        lambda: tools.move_panel(ctx, second, split, 0, "medium"),
        "nested windows are forbidden",
        f"{second} (window)",
        f"{first} (window)",
        "under r_canvas (region)",
    )
    _assert_layout_rejection(
        ctx,
        lambda: tools.move_panel(ctx, second, "r_right", 0, "medium"),
        "windows require canvas ancestry",
        f"{second} (window)",
        "r_right (region)",
        "under r_canvas (region)",
    )
    program = tools.run_python_client(ctx, "Program", "print(1)", split)["nodeId"]
    panel = next(
        n["parentId"] for n in ctx.snapshot()["layout"]["nodes"] if n["id"] == program
    )
    _assert_layout_rejection(
        ctx,
        lambda: tools.move_panel(ctx, program, "r_right", 0, "medium"),
        "program surface requires window ancestry",
        f"{program} (surface)",
        f"{panel} (panel)",
        "split/tabs inside a window",
        "r_canvas (region)",
    )


def test_open_mount_and_window_capacity_errors_explain_how_to_free_capacity(ctx):
    from soliplex_a2ui_workbench import workbench_tools as tools

    contents = [
        tools.open_panel(ctx, "Note", "Text", "r_left")["nodeId"] for _ in range(12)
    ]
    _assert_layout_rejection(
        ctx,
        lambda: tools.open_panel(ctx, "Overflow", "Text", "r_left"),
        "open content mount capacity exceeded",
        f"{contents[0]} (surface in ",
        "maximum 12",
        "close_panel",
        "free an open mount",
    )
    first = tools.create_container(ctx, "r_canvas", "window", "First")["nodeId"]
    tools.create_container(ctx, "r_canvas", "window", "Second")
    _assert_layout_rejection(
        ctx,
        lambda: tools.create_container(ctx, "r_canvas", "window", "Third"),
        "expanded window capacity exceeded",
        f"{first} (window)",
        "maximum 2",
        "close_panel",
        "repair_program",
    )


def test_total_node_capacity_error_explains_closed_nodes_still_count(ctx):
    from soliplex_a2ui_workbench import workbench_tools as tools

    for _ in range(58):
        tools.create_container(ctx, "r_left", "panel", "Panel")
    _assert_layout_rejection(
        ctx,
        lambda: tools.create_container(ctx, "r_right", "panel", "Overflow"),
        "total node capacity exceeded",
        "r_left (region)",
        "maximum 64 including closed nodes",
        "move existing nodes or repair an existing program",
        "start a new thread for new content",
        "closing nodes does not free",
    )


def test_cycle_and_order_errors_identify_nodes_and_valid_retry(ctx):
    from soliplex_a2ui_workbench import workbench_tools as tools

    split = tools.create_container(ctx, "r_left", "split", "Split")["nodeId"]
    panel = tools.create_container(ctx, split, "panel", "Panel")["nodeId"]
    _assert_layout_rejection(
        ctx,
        lambda: tools.move_panel(ctx, split, panel, 0, "medium"),
        f"{split} (split)",
        f"{panel} (panel)",
        "descendant",
        "parent outside the subtree",
    )
    _assert_layout_rejection(
        ctx,
        lambda: tools.move_panel(ctx, panel, "r_right", 2, "medium"),
        f"{panel} (panel)",
        "r_right (region)",
        "out of range",
        "use order from 0 to 0",
    )


def test_control_data_capacity_error_names_workspace_and_valid_alternative(ctx):
    from soliplex_a2ui_workbench import workbench_tools as tools

    layout = ctx.snapshot()["layout"]
    layout["shared"]["oversized"] = "x" * 65_536
    _assert_layout_rejection(
        ctx,
        lambda: tools._publish(ctx, layout),
        "layout exceeds 64 KiB",
        "wb_root (workspace)",
        "reuse existing nodes",
        "start a new thread",
    )
