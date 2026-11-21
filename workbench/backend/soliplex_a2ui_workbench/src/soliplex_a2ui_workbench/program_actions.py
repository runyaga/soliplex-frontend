"""Bounded, no-inference program layout transactions through the tool validator."""

from __future__ import annotations

import copy
import hashlib
from typing import Annotated, Literal

from pydantic import Field, TypeAdapter

from . import workbench_tools as tools
from .workbench_context import WorkbenchToolContext
from .workbench_schemas import Closed, Id, Source, Title

MAX_LAYOUT_ACTIONS = 8


class OpenWindow(Closed):
    op: Literal["open"]
    window_id: Id
    title: Title
    kind: Literal["text", "python"]
    content: Source


class ShowApp(Closed):
    op: Literal["show_app"]


class UpdateWindow(Closed):
    op: Literal["update"]
    window_id: Id
    content: Source


class MoveWindow(Closed):
    op: Literal["move"]
    window_id: Id
    order: Annotated[int, Field(ge=0, le=63)] = 0


class CloseWindow(Closed):
    op: Literal["close"]
    window_id: Id


ProgramActions = Annotated[
    list[
        Annotated[
            OpenWindow | MoveWindow | CloseWindow | UpdateWindow | ShowApp,
            Field(discriminator="op"),
        ]
    ],
    Field(min_length=1, max_length=MAX_LAYOUT_ACTIONS),
]
_actions = TypeAdapter(ProgramActions)


def apply_program_actions(
    projection, scope, run_id, record, raw_actions, submission_id=None
):
    """Validate the complete gesture before exposing any of its activities.

    Ownership is server-authored layout data. The working projection is private
    until the stock AG-UI endpoint persists/delivers the returned activities.
    """
    actions = _actions.validate_python(raw_actions)
    working = copy.deepcopy(projection)
    ctx = WorkbenchToolContext(
        scope, working, run_id, allowed_rooms=frozenset({scope.room_id})
    )
    owner = record["surfaceId"]
    owners = working.layout.get("shared", {}).get("programWindows", {}).copy()
    # The window containing this registered program belongs to it as well.
    leaf = next(
        (
            n
            for n in working.layout["nodes"]
            if n["kind"] == "surface" and n["payload"].get("surfaceId") == owner
        ),
        None,
    )
    if leaf is None:
        raise ValueError("program has no mounted window")
    parent = tools._node(working.layout["nodes"], leaf["parentId"])
    while parent["kind"] != "window" and parent["parentId"]:
        if parent["visibility"] != "open":
            raise ValueError("program is hidden by an ancestor")
        parent = tools._node(working.layout["nodes"], parent["parentId"])
    if (
        parent["kind"] != "window"
        or parent["visibility"] != "open"
        or leaf["visibility"] != "open"
    ):
        raise ValueError("program is not in an open window")
    ancestor = parent
    while ancestor["parentId"] is not None:
        ancestor = tools._node(working.layout["nodes"], ancestor["parentId"])
        if ancestor["visibility"] != "open":
            raise ValueError("program is hidden by an ancestor")
    owners.setdefault(parent["id"], owner)
    events = []
    for action in actions:
        if isinstance(action, ShowApp):
            layout = copy.deepcopy(working.layout)
            app_id = "app_" + hashlib.sha256(owner.encode()).hexdigest()[:32]
            apps = layout["shared"].setdefault("programApps", {})
            if app_id in apps and apps[app_id] != owner:
                raise ValueError("app window belongs to another program")
            app = next((n for n in layout["nodes"] if n["id"] == app_id), None)
            if app is None:
                app = {
                    "id": app_id,
                    "parentId": "r_canvas",
                    "children": [],
                    "kind": "window",
                    "title": str(record["title"])[:76] + " app",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {},
                }
                layout["nodes"].append(app)
                canvas = tools._node(layout["nodes"], "r_canvas")
                # For direct canvas programs, keep the accepted sibling order.
                position = (
                    canvas["children"].index(parent["id"]) + 1
                    if parent["id"] in canvas["children"]
                    else len(canvas["children"])
                )
                canvas["children"].insert(position, app_id)
            elif apps.get(app_id) != owner:
                raise ValueError("app window id already exists")
            apps[app_id] = owner
            app["visibility"] = "open"
            owners[app_id] = owner
            result = tools._publish(ctx, layout)
        elif isinstance(action, OpenWindow):
            if any(n["id"] == action.window_id for n in working.layout["nodes"]):
                raise ValueError("program window id already exists")
            created = tools.create_container(
                ctx,
                "r_canvas",
                "window",
                action.title,
                _node_id_override=action.window_id,
            )
            events.extend(created["events"])
            owners[action.window_id] = owner
            if action.kind == "python":
                result = tools.run_python_client(
                    ctx, action.title, action.content, action.window_id
                )
            else:
                result = tools.open_panel(
                    ctx, action.title, action.content, action.window_id
                )
        else:
            if owners.get(action.window_id) != owner:
                raise ValueError("program may only change windows it owns")
            if isinstance(action, MoveWindow):
                result = tools.move_panel(
                    ctx, action.window_id, "r_canvas", action.order, "medium"
                )
            elif isinstance(action, UpdateWindow):
                layout = copy.deepcopy(working.layout)
                window = tools._node(layout["nodes"], action.window_id)
                if window["kind"] != "window" or len(window["children"]) != 1:
                    raise ValueError("update requires an owned content window")
                leaf = tools._node(layout["nodes"], window["children"][0])
                if leaf["kind"] != "surface":
                    raise ValueError("update requires a direct content surface")
                content = copy.deepcopy(
                    working.content[leaf["payload"]["activityMessageId"]]
                )
                if content["component"] == "PythonRepl":
                    content["source"] = action.content
                elif content["component"] == "Text":
                    content["properties"]["text"] = action.content
                else:
                    raise ValueError("update supports text and Python windows only")
                window["visibility"] = leaf["visibility"] = "open"
                result = tools._publish(ctx, layout, content=[content])
            else:
                result = tools.close_panel(ctx, action.window_id)
        events.extend(result["events"])
    layout = copy.deepcopy(working.layout)
    layout["shared"]["programWindows"] = owners
    if submission_id is not None:
        submitted = list(layout["shared"].get("programSubmissions", []))
        if submission_id in submitted or len(submitted) >= 4096:
            raise ValueError("program submission already accepted or capacity reached")
        layout["shared"]["programSubmissions"] = [*submitted, submission_id]
    events.extend(tools._publish(ctx, layout)["events"])
    # All content first, followed by the final accepted tree. No client edit.
    return [part["event"] for part in events if part["kind"] == "content"] + [
        events[-1]["event"]
    ]
