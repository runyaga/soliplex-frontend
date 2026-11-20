"""Small deterministic tools that publish closed workbench snapshots."""

from __future__ import annotations

import copy
import uuid
from pathlib import Path
from typing import Any

from .workbench_context import WorkbenchToolContext
from .workbench_repository import PublicationConflict
from .workbench_templates import chart_record, form_record, python_record, text_record


def _identity(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:16]}"


def _node_id() -> str:
    return _identity("node")


def _record_ids() -> tuple[str, str]:
    return _identity("activity"), _identity("surface")


def _node(nodes: list[dict[str, Any]], node_id: str) -> dict[str, Any]:
    found = next((node for node in nodes if node["id"] == node_id), None)
    if found is None:
        raise ValueError(
            f"unknown workbench node {node_id!r} (kind unknown); call get_workbench "
            "and use a returned node id, not a surfaceId or activityMessageId. "
            "For placement use r_left (region), r_right (region), or r_canvas (region)"
        )
    return found


def _panel_target(nodes: list[dict[str, Any]], node_id: str) -> dict[str, Any]:
    """Resolve content to its nearest owner without changing the snapshot."""
    node = _node(nodes, node_id)
    if node["kind"] == "surface":
        while node["kind"] not in {"panel", "window"} and node["parentId"]:
            node = _node(nodes, node["parentId"])
    return node


def _publish(
    ctx: WorkbenchToolContext,
    snapshot: dict[str, Any],
    *,
    content: list[dict[str, Any]] | None = None,
    new_program_surface: str | None = None,
) -> dict[str, Any]:
    ctx.require_room()
    current = ctx.snapshot()
    expected = ctx.expected_revision
    if expected is None or current["layout"] is None:
        raise PublicationConflict("workbench has no registered layout")
    layout = snapshot
    if len(layout["nodes"]) > 64:
        nodes = ", ".join(f"{node['id']} ({node['kind']})" for node in layout["nodes"])
        raise ValueError(
            f"total node capacity exceeded: {nodes}; maximum 64 including closed nodes; "
            "move existing nodes or repair an existing program without allocating more nodes; "
            "start a new thread for new content at this limit; closing nodes does not free this limit"
        )
    layout["layoutRevision"] = expected + 1
    all_content = [
        {key: value for key, value in item.items() if key != "workbenchCommit"}
        for item in current["content"]
    ]
    for incoming in content or []:
        all_content = [
            item
            for item in all_content
            if item.get("activityMessageId") != incoming.get("activityMessageId")
        ]
        all_content.append(
            {key: value for key, value in incoming.items() if key != "workbenchCommit"}
        )
    program_surfaces = {
        str(item["surfaceId"])
        for item in all_content
        if item.get("component") == "PythonRepl"
    }
    if new_program_surface:
        program_surfaces.add(new_program_surface)
    mounts = {
        (str(item["activityMessageId"]), str(item["surfaceId"])) for item in all_content
    }
    result = ctx.repository.publish(
        ctx.scope,
        ctx.publication_key(),
        expected,
        layout,
        all_content,
        registered_program_surfaces=program_surfaces,
        registered_mounts=mounts,
    )
    ctx.expected_revision = result.snapshot["layoutRevision"]
    changed = {item["activityMessageId"] for item in content or []}
    events = [
        part
        for part in result.events
        if part["kind"] == "layout" or part["event"]["messageId"] in changed
    ]
    return {
        "status": "published",
        "layoutRevision": ctx.expected_revision,
        "events": events,
    }


def _current(ctx: WorkbenchToolContext) -> tuple[dict[str, Any], dict[str, Any]]:
    state = ctx.snapshot()
    layout = state.get("layout")
    if not isinstance(layout, dict):
        raise PublicationConflict("workbench has no registered layout")
    return state, copy.deepcopy(layout)


def _content_result(
    ctx: WorkbenchToolContext,
    record: dict[str, Any],
    parent_id: str,
    *,
    title: str,
    program: bool = False,
) -> dict[str, Any]:
    _, layout = _current(ctx)
    parent = _node(layout["nodes"], parent_id)
    if parent["kind"] not in {"region", "split", "tabs", "panel", "window"}:
        raise ValueError(
            f"{parent_id} ({parent['kind']}): content parent is not a container; "
            "use r_left (region), r_right (region), or an empty panel/window id"
        )
    if parent["kind"] in {"panel", "window"} and parent["children"]:
        children = ", ".join(
            f"{child_id} ({_node(layout['nodes'], child_id)['kind']})"
            for child_id in parent["children"]
        )
        raise ValueError(
            f"{parent_id} ({parent['kind']}) contains {children}: content parent must be empty; "
            "use an empty panel/window or r_canvas (region) to create another owner. "
            "For an existing Python program use repair_program with its surface node id"
        )
    content_parent_id = parent_id
    ancestors = []
    current = parent
    while current is not None:
        ancestors.append(current)
        current = (
            _node(layout["nodes"], current["parentId"]) if current["parentId"] else None
        )
    needs_window = program and not any(node["kind"] == "window" for node in ancestors)
    if needs_window:
        if not any(node["id"] == "r_canvas" for node in ancestors):
            raise ValueError(
                f"{parent_id} ({parent['kind']}): program windows require canvas ancestry; "
                "pass 'r_canvas' (region) or a container inside it"
            )
        # A panel can contain a split, which can in turn contain a window.
        # Keep the caller's container identity and publish the entire change once.
        if parent["kind"] == "panel":
            split_id = _node_id()
            parent["children"].append(split_id)
            parent = {
                "id": split_id,
                "parentId": parent_id,
                "children": [],
                "kind": "split",
                "title": title,
                "size": "medium",
                "visibility": "open",
                "payload": {"axis": "horizontal"},
            }
            layout["nodes"].append(parent)
            parent_id = split_id
    if needs_window or parent["kind"] in {"region", "split", "tabs"}:
        content_parent_id = _node_id()
        parent["children"].append(content_parent_id)
        layout["nodes"].append(
            {
                "id": content_parent_id,
                "parentId": parent_id,
                "children": [],
                "kind": "window" if needs_window else "panel",
                "title": title,
                "size": "medium",
                "visibility": "open",
                "payload": {},
            }
        )
    node_id = _node_id()
    content_parent = _node(layout["nodes"], content_parent_id)
    content_parent["children"].append(node_id)
    node = {
        "id": node_id,
        "parentId": content_parent_id,
        "children": [],
        "kind": "surface",
        "title": title,
        "size": "medium",
        "visibility": "open",
        "payload": {
            "activityMessageId": record["activityMessageId"],
            "surfaceId": record["surfaceId"],
        },
    }
    layout["nodes"].append(node)
    published = _publish(
        ctx,
        layout,
        content=[record],
        new_program_surface=record["surfaceId"] if program else None,
    )
    return {
        "status": "published",
        "layoutRevision": published["layoutRevision"],
        "events": published["events"],
        "nodeId": node_id,
        "activityMessageId": record["activityMessageId"],
        "surfaceId": record["surfaceId"],
        **({"side": "client", "execution": "awaiting_user"} if program else {}),
    }


def open_demo(ctx: WorkbenchToolContext, name: str) -> dict[str, object]:
    """Publish a curated program, without importing or executing its source."""
    if name != "monty_gui":
        raise ValueError('unknown demo; use open_demo(name="monty_gui")')
    source = Path(__file__).with_name("monty_gui_demo.py").read_text()
    return run_python_client(ctx, "Monty GUI demo", source, "r_canvas")


def get_workbench(ctx: WorkbenchToolContext, **_injected: object) -> dict[str, object]:
    """Return bounded stable node identities, tree structure, catalogs and templates."""
    state = ctx.snapshot()
    layout = state.get("layout")
    if not isinstance(layout, dict):
        raise PublicationConflict("workbench has no registered layout")
    protected = {"wb_root", "r_chat", "r_left", "r_right", "r_canvas", "r_tray"}
    return {
        "layoutRevision": state["revision"],
        "rootId": layout["rootId"],
        "nodes": [
            {
                "id": node["id"],
                "kind": node["kind"],
                "parentId": node["parentId"],
                "children": list(node["children"]),
                "protected": node["id"] in protected,
            }
            for node in layout["nodes"]
        ],
        "catalogs": ["basic", "graphics:2", "lab:1"],
        "templates": ["intake"],
    }


def read_form_results(ctx: WorkbenchToolContext, title: str) -> dict[str, object]:
    """Read bounded saved rows in this authenticated thread, without writes."""
    from .workbench_form_results import read_form_results as read_results

    intake = any(
        record.get("title") == title and record.get("template") == "intake"
        for record in ctx.snapshot()["content"]
    )
    return read_results(ctx.installation, ctx.scope, "intake" if intake else title)


def create_container(
    ctx: WorkbenchToolContext,
    parent_id: str,
    kind: str,
    title: str,
    *,
    _node_id_override: str | None = None,
) -> dict[str, object]:
    """Create one empty split, tabs, panel or window under a valid parent."""
    _, layout = _current(ctx)
    parent = _node(layout["nodes"], parent_id)
    if parent["kind"] not in {"region", "split", "tabs"}:
        raise ValueError(
            f"{parent_id} ({parent['kind']}): container parent cannot accept a child "
            f"via create_container(kind={kind!r}); use r_left (region), r_right (region), "
            "r_canvas (region), or a split/tabs id"
        )
    node_id = _node_id_override or _node_id()
    parent["children"].append(node_id)
    payload = {"axis": "horizontal"} if kind == "split" else {}
    layout["nodes"].append(
        {
            "id": node_id,
            "parentId": parent_id,
            "children": [],
            "kind": kind,
            "title": title,
            "size": "medium",
            "visibility": "open",
            "payload": payload,
        }
    )
    result = _publish(ctx, layout)
    return {
        "status": "published",
        "layoutRevision": result["layoutRevision"],
        "events": result["events"],
        "nodeId": node_id,
    }


def place_form(
    ctx: WorkbenchToolContext, title: str, parent_id: str,
    template: str | None = None, fields: list[dict[str, object] | str] | None = None
) -> dict[str, object]:
    """Place a validated bound form under an allowed container."""
    from .workbench_schemas import PlaceForm
    definition = PlaceForm.model_validate({"title": title, "parent_id": parent_id, "template": template, "fields": fields})
    activity_id, surface_id = _record_ids()
    return _content_result(
        ctx, form_record(activity_id, surface_id, title, fields=definition.model_dump()["fields"]), parent_id, title=title
    )


def show_chart(
    ctx: WorkbenchToolContext,
    title: str,
    kind: str,
    points: list[dict[str, object]],
    parent_id: str,
    scale: dict[str, float | None] | None = None,
) -> dict[str, object]:
    """Publish one categorical graphics:2 Chart without running a renderer."""
    activity_id, surface_id = _record_ids()
    return _content_result(
        ctx,
        chart_record(activity_id, surface_id, title, kind, points, scale),
        parent_id,
        title=title,
    )


def open_panel(
    ctx: WorkbenchToolContext, title: str, text: str, parent_id: str
) -> dict[str, object]:
    """Open a basic text surface under an allowed container."""
    activity_id, surface_id = _record_ids()
    return _content_result(
        ctx, text_record(activity_id, surface_id, title, text), parent_id, title=title
    )


def run_python_client(
    ctx: WorkbenchToolContext,
    title: str,
    source: str,
    parent_id: str,
    replace: bool = False,
) -> dict[str, object]:
    """Place an inert browser PythonRepl surface; execution waits for user Run."""
    if replace:
        return repair_program(ctx, source=source, parent_id=parent_id, title=title)
    activity_id, surface_id = _record_ids()
    return _content_result(
        ctx,
        python_record(activity_id, surface_id, title, source),
        parent_id,
        title=title,
        program=True,
    )


def run_python_server(
    ctx: WorkbenchToolContext, surface_id: str, source: str
) -> dict[str, str]:
    """Validate registered client program scope, then return the fixed disabled result."""
    ctx.require_room()
    state = ctx.snapshot()
    record = next(
        (item for item in state["content"] if item.get("surfaceId") == surface_id), None
    )
    if record is None or record.get("component") != "PythonRepl":
        raise ValueError("server Python surface is not registered in this thread")
    return {
        "status": "not_enabled",
        "code": "server_runner_deferred",
        "tool": "run_python_server",
        "side": "server",
        "execution": "disabled",
    }


def move_panel(
    ctx: WorkbenchToolContext, node_id: str, parent_id: str, order: int, size: str
) -> dict[str, object]:
    """Move a stable subtree, resolving content leaves to their nearest owner."""
    _, layout = _current(ctx)
    nodes = layout["nodes"]
    protected = {"wb_root", "r_chat", "r_left", "r_right", "r_canvas", "r_tray"}
    moving = _panel_target(nodes, node_id)
    node_id = moving["id"]
    if node_id in protected:
        raise ValueError(
            f"{node_id} ({moving['kind']}): protected workbench node cannot be moved; "
            "move an authored panel/window or its content node instead; call get_workbench for ids"
        )
    parent = _node(nodes, parent_id)
    if moving["parentId"] is None:
        raise ValueError(
            f"{node_id} ({moving['kind']}): workbench root cannot be moved; "
            "move an authored panel/window under r_left, r_right, or r_canvas (regions)"
        )
    old_parent = _node(nodes, moving["parentId"])
    old_parent["children"].remove(node_id)
    if parent_id == node_id or _is_descendant(nodes, node_id, parent_id):
        raise ValueError(
            f"{node_id} ({moving['kind']}) cannot move a node into its descendant "
            f"{parent_id} ({parent['kind']}) or itself; choose a parent outside the subtree, "
            "such as r_canvas (region)"
        )
    if not 0 <= order <= len(parent["children"]):
        raise ValueError(
            f"{node_id} ({moving['kind']}) into {parent_id} ({parent['kind']}): "
            f"child order {order} is out of range; use order from 0 to {len(parent['children'])} "
            "after removing the moving node from its old position"
        )
    moving["parentId"] = parent_id
    moving["size"] = size
    parent["children"].insert(order, node_id)
    result = _publish(ctx, layout)
    return {
        "status": "published",
        "layoutRevision": result["layoutRevision"],
        "events": result["events"],
        "nodeId": node_id,
    }


def _is_descendant(
    nodes: list[dict[str, Any]], parent_id: str, candidate_id: str
) -> bool:
    parent = _node(nodes, parent_id)
    return candidate_id in _descendant_ids(nodes, parent)


def _descendant_ids(nodes: list[dict[str, Any]], node: dict[str, Any]) -> set[str]:
    result: set[str] = set()
    for child_id in node["children"]:
        result.add(child_id)
        result |= _descendant_ids(nodes, _node(nodes, child_id))
    return result


def close_panel(ctx: WorkbenchToolContext, node_id: str) -> dict[str, object]:
    """Close a subtree or a content leaf's nearest owner, retaining identities."""
    _, layout = _current(ctx)
    node = _panel_target(layout["nodes"], node_id)
    node_id = node["id"]
    if node_id in {"wb_root", "r_chat", "r_left", "r_right", "r_canvas", "r_tray"}:
        raise ValueError(
            f"{node_id} ({node['kind']}): protected workbench node cannot be closed; "
            "close an authored panel/window or its content node instead; call get_workbench for ids"
        )
    node["visibility"] = "closed"
    closed_ids = {node_id} | _descendant_ids(layout["nodes"], node)
    programs = {
        n["payload"].get("surfaceId") for n in layout["nodes"]
        if n["id"] in closed_ids and n["kind"] == "surface"
    }
    for app_id, owner in layout["shared"].get("programApps", {}).items():
        if owner in programs:
            _node(layout["nodes"], app_id)["visibility"] = "closed"
    result = _publish(ctx, layout)
    return {
        "status": "published",
        "layoutRevision": result["layoutRevision"],
        "events": result["events"],
        "nodeId": node_id,
    }


def repair_program(
    ctx: WorkbenchToolContext,
    node_id: str | None = None,
    source: str = "",
    parent_id: str | None = None,
    title: str = "Python",
) -> dict[str, object]:
    """Revise a registered program; the client controls execution via AI Fix."""
    ctx.require_room()
    state, layout = _current(ctx)
    if (node_id is None) == (parent_id is None):
        raise ValueError(
            "pass exactly one of node_id (existing program) or parent_id (container)"
        )
    node = _node(layout["nodes"], node_id or parent_id)
    if (
        parent_id is not None
        and node["kind"] in {"region", "split", "tabs", "panel", "window"}
        and not (node["kind"] == "window" and node["children"])
    ):
        return run_python_client(ctx, title, source, parent_id)
    if node["kind"] == "window" and len(node["children"]) == 1:
        node = _node(layout["nodes"], node["children"][0])
    if node["kind"] != "surface":
        raise ValueError(
            f"{node['id']} ({node['kind']}): repair target must be a registered program "
            "surface or its window; call get_workbench and pass that surface node id, "
            "or use parent_id='r_canvas' to place a new program"
        )
    record = next(
        (
            item
            for item in state["content"]
            if item.get("surfaceId") == node["payload"].get("surfaceId")
            and item.get("component") == "PythonRepl"
        ),
        None,
    )
    if record is None:
        raise ValueError(
            f"{node['id']} ({node['kind']}): repair target is not a registered program; "
            "pass a Python program surface node id or its window, "
            "or use parent_id='r_canvas' to place a new program"
        )
    # Older repair attempts closed the content leaf before replacing it.
    # Reopen that leaf; retain the owning window's visibility and placement.
    node["visibility"] = "open"
    record["source"] = source
    record["output"] = ""
    result = _publish(ctx, layout, content=[record])
    return {
        "status": "published",
        "layoutRevision": result["layoutRevision"],
        "events": result["events"],
        "nodeId": node["id"],
        "surfaceId": record["surfaceId"],
        "execution": "client_controlled",
        "instruction": "Follow the repair request: autoRun=true runs automatically; otherwise say press Run.",
    }


def start_walkthrough(ctx):
    """Start only the server-curated walkthrough, without running Python."""
    from .workbench_walkthrough import start_walkthrough as start
    return start(ctx)
