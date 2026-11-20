"""Behavior of the deterministic minimum workbench tool table."""
import json
from pathlib import Path
import pytest
from soliplex_a2ui_workbench.workbench_context import WorkbenchToolContext
from soliplex_a2ui_workbench.workbench_repository import SQLiteWorkbenchRepository, WorkbenchScope
from soliplex_a2ui_workbench.workbench_templates import MINIMUM_ROOM_REGISTRATIONS, MINIMUM_ROOM_TOOLS, validate_room_registrations
from soliplex_a2ui_workbench.workbench_schemas import MINIMUM_ROOM_TOOL_MANIFEST
FIXTURES = Path(__file__).parents[1] / "fixtures/workbench"
@pytest.fixture
def ctx(tmp_path):
    scope = WorkbenchScope("actor", "server", "room", "thread")
    repo = SQLiteWorkbenchRepository(tmp_path / "workbench.db")
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    repo.publish(scope, "seed", 0, layout, [], registered_program_surfaces=set(), registered_mounts=set())
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
    form = MINIMUM_ROOM_TOOLS["place_form"].function(ctx, title="Intake", template="intake", parent_id="r_left")
    chart = MINIMUM_ROOM_TOOLS["show_chart"].function(ctx, title="Counts", kind="bar", points=[{"id":"north","label":"North","value":80}], parent_id="r_canvas")
    state = MINIMUM_ROOM_TOOLS["get_workbench"].function(ctx)
    assert form["layoutRevision"] == 2 and chart["layoutRevision"] == 3 and state["layoutRevision"] == 3
    chart_record = next(row for row in ctx.repository.load_snapshot(ctx.scope)["content"] if row["component"] == "Chart")
    assert chart_record["spec"] == {"kind":"bar", "series":[{"id":"values","label":"Counts","points":[{"id":"north","label":"North","value":80}]}]}
def test_python_client_is_inert_and_server_returns_disabled_without_mutation(ctx):
    tools = MINIMUM_ROOM_TOOLS
    window = tools["create_container"].function(ctx, parent_id="r_canvas", kind="window", title="Program")
    result = tools["run_python_client"].function(ctx, title="Demo", source="print(1)", parent_id=window["nodeId"])
    assert result["side"] == "client" and result["execution"] == "awaiting_user"
    from soliplex_a2ui_workbench.workbench_publication import BUILTIN_CATALOG_MANIFESTS, WorkbenchCatalogValidator, build_publication
    state = ctx.repository.load_snapshot(ctx.scope)
    record = {key: value for key, value in next(item for item in state["content"] if item["surfaceId"] == result["surfaceId"]).items() if key != "workbenchCommit"}
    emitted_plan = build_publication([record], WorkbenchCatalogValidator(), BUILTIN_CATALOG_MANIFESTS,
                                     layout=state["layout"], registered_program_surfaces={result["surfaceId"]})
    event = next(event for event in emitted_plan["events"] if event["kind"] == "content")
    emitted = event["event"]["content"]["a2ui_operations"]
    assert emitted[1]["updateDataModel"]["value"]["output"] == ""
    component = emitted[2]["updateComponents"]["components"][0]
    assert component["@catalogId"] == "urn:soliplex:catalog:lab:1"
    assert component["source"] == {"@path":"/source"} and component["output"] == {"@path":"/output"}
    before = ctx.repository.load_snapshot(ctx.scope)
    disabled = tools["run_python_server"].function(ctx, surface_id=result["surfaceId"], source="print(2)")
    assert disabled == {"status":"not_enabled","code":"server_runner_deferred","tool":"run_python_server","side":"server","execution":"disabled"}
    assert ctx.repository.load_snapshot(ctx.scope) == before
def test_closed_and_move_preserve_subtree_identity(ctx):
    tools = MINIMUM_ROOM_TOOLS
    created = tools["create_container"].function(ctx, parent_id="r_left", kind="panel", title="Panel")
    moved = tools["move_panel"].function(ctx, node_id=created["nodeId"], parent_id="r_right", order=0, size="large")
    assert moved["layoutRevision"] == created["layoutRevision"] + 1
    closed = tools["close_panel"].function(ctx, node_id=created["nodeId"])
    assert closed["layoutRevision"] == moved["layoutRevision"] + 1
    snapshot = ctx.repository.load_snapshot(ctx.scope)["layout"]
    assert next(node for node in snapshot["nodes"] if node["id"] == created["nodeId"])["visibility"] == "closed"
def test_unknown_room_fails_closed_before_repository_access():
    class NeverRepository:
        def load_snapshot(self, _scope): pytest.fail("repository touched for an unconfigured room")
    ctx = WorkbenchToolContext(WorkbenchScope("a", "s", "foreign", "t"), NeverRepository(), "run", allowed_rooms=frozenset({"room"}))
    with pytest.raises(PermissionError, match="SOLIPLEX_WORKBENCH_ROOMS"): MINIMUM_ROOM_TOOLS["get_workbench"].function(ctx)

def test_invalid_mutation_is_atomic_and_move_preserves_descendants(ctx):
    tools = MINIMUM_ROOM_TOOLS
    parent = tools["create_container"].function(ctx, parent_id="r_left", kind="tabs", title="Tabs")
    child = tools["create_container"].function(ctx, parent_id=parent["nodeId"], kind="panel", title="Panel")
    before = ctx.repository.load_snapshot(ctx.scope)
    with pytest.raises(ValueError):
        tools["move_panel"].function(ctx, node_id=parent["nodeId"], parent_id=child["nodeId"], order=0, size="large")
    assert ctx.repository.load_snapshot(ctx.scope) == before
    moved = tools["move_panel"].function(ctx, node_id=parent["nodeId"], parent_id="r_right", order=0, size="large")
    tree = ctx.repository.load_snapshot(ctx.scope)["layout"]
    preserved = next(node for node in tree["nodes"] if node["id"] == child["nodeId"])
    assert moved["layoutRevision"] == before["revision"] + 1
    assert preserved["id"] == child["nodeId"] and preserved["parentId"] == parent["nodeId"]


def test_stale_turn_cannot_overwrite_a_successful_tool_mutation(tmp_path):
    scope = WorkbenchScope("actor", "server", "room", "thread")
    repo = SQLiteWorkbenchRepository(tmp_path / "stale.db")
    layout = json.loads((FIXTURES / "layout_tree_v1.json").read_text())
    repo.publish(scope, "seed", 0, layout, [], registered_program_surfaces=set(), registered_mounts=set())
    first = WorkbenchToolContext(scope, repo, "first", allowed_rooms=frozenset({"room"}))
    second = WorkbenchToolContext(scope, repo, "second", allowed_rooms=frozenset({"room"}))
    MINIMUM_ROOM_TOOLS["create_container"].function(first, parent_id="r_left", kind="panel", title="One")
    with pytest.raises(Exception, match="stale"):
        MINIMUM_ROOM_TOOLS["create_container"].function(second, parent_id="r_right", kind="panel", title="Two")
    repo.close()


def test_tray_accepts_published_content(ctx):
    result = MINIMUM_ROOM_TOOLS["open_panel"].function(ctx, title="Tray note", text="Visible below the workspace", parent_id="r_tray")
    layout = ctx.repository.load_snapshot(ctx.scope)["layout"]
    assert next(node for node in layout["nodes"] if node["id"] == "r_tray")["children"]
    assert result["events"][-1]["kind"] == "layout"
