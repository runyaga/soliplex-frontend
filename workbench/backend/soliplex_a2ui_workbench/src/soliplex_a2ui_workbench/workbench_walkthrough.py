"""Scripted tour. Each accepted action is one separately persisted AG-UI turn."""

from __future__ import annotations

import copy
import uuid

from . import workbench_tools as tools
from .workbench_actions import validate_submission
from .workbench_context import WorkbenchToolContext
from .workbench_form_results import append_form_result
from .workbench_schemas import ActionEnvelope

SUGGESTION = "Start the walkthrough."
SAMPLES = {"name": "Sample visitor", "color": ["Blue"], "subscribe": True}
# title, narration, minimum reading time, client effect. Source never comes from a model.
STEPS = (
    (
        "The workbench",
        "The canvas holds your main work. Left and right sidebars hold supporting surfaces; the bottom tray holds this story. The agent places surfaces through server-validated tools.",
        8000,
        "none",
    ),
    (
        "A line chart",
        "Weekly visits appears on the canvas. This is a real HHG line chart, published with show_chart so its data and placement are validated.",
        5000,
        "none",
    ),
    (
        "A bar chart",
        "Regions appears in the right sidebar. Different chart types use the same validated show_chart path.",
        5000,
        "none",
    ),
    (
        "Move beside the line",
        "The bar chart moves beside the line chart. Its stable id stays the same, so moving a surface does not recreate its content.",
        5000,
        "none",
    ),
    (
        "Move back",
        "The bar chart returns to the right sidebar. Your placements win: if you move a tour chart yourself, the tour leaves it where you put it.",
        6000,
        "none",
    ),
    (
        "A custom form",
        "A Team survey appears on the left. The server validates its fields and rejects credential requests. Submitting saves a row in this thread's CSV.",
        6000,
        "none",
    ),
    (
        "Fill sample values",
        "I am filling Name, Color and Subscribe with sample values on your behalf. You can see them in the fields before the next step submits them.",
        6000,
        "fill",
    ),
    (
        "Submit the sample",
        "I am submitting those sample values through the server's form validator.",
        6000,
        "none",
    ),
    (
        "A curated Python program",
        "Here is the unchanged Monty GUI demo. Clicking Start gave permission to run this curated source during this tour. Model-written code never gets that permission.",
        6000,
        "none",
    ),
    (
        "Python drives the GUI",
        "I am pressing Run. Python builds a counter, buttons and a chart; its separate app window opens beside the program, through the server's validated layout path.",
        6000,
        "run",
    ),
    (
        "Press +1 once",
        "I am pressing +1. The button calls handle_event in the retained Python session. Python changes its count and redraws the GUI: a round trip.",
        5000,
        "plus",
    ),
    (
        "Press +1 twice",
        "I am pressing +1 again. The same session keeps the count, and handle_event redraws it as 2.",
        5000,
        "plus",
    ),
    (
        "Press +1 three times",
        "One more +1 makes 3. The displayed last-event line lets you see the round trip.",
        5000,
        "plus",
    ),
    (
        "Add a point",
        "I am pressing Add point. Python adds the current count to its chart data and redraws the chart.",
        5000,
        "add_point",
    ),
    (
        "Open the log",
        "I am pressing Open log window. handle_event requests a window; the server validates that request before the event log appears on the canvas.",
        6000,
        "open_log",
    ),
    (
        "AI Fix: skipped on this branch",
        "AI Fix is the checkbox that asks the agent to repair a failed program. A NameError demo would need a verified repair and automatic rerun. That chain is being fixed on another branch, so this tour skips it rather than pretend it succeeded.",
        10000,
        "none",
    ),
    (
        "Try it yourself",
        "The tour is complete. I have closed only its own surfaces, leaving this narration. Try Open the Monty GUI demo, Team survey, the Weekly visits dashboard, or the Primes program from the room suggestions.",
        8000,
        "none",
    ),
)


def _context(projection, scope, run_id, installation=None):
    return WorkbenchToolContext(
        scope,
        projection,
        run_id,
        allowed_rooms=frozenset({scope.room_id}),
        installation=installation,
    )


def narration(state):
    return f"Step {state['step'] + 1} of {len(STEPS)} · {state['title']}\n\n{state['text']}"


def _finish(ctx, state, events):
    # Revise one stable text surface and validated layout. No runtime is invoked here.
    _, layout = tools._current(ctx)
    record = next(
        item
        for item in ctx.snapshot()["content"]
        if item["activityMessageId"] == state["narrationActivity"]
    )
    record["properties"]["text"] = narration(state)
    layout["shared"]["walkthrough"] = state
    result = tools._publish(ctx, layout, content=[record])
    events.extend(result["events"])
    return {"events": events, "narration": narration(state)}


def start_walkthrough(ctx):
    events = []
    previous = ctx.snapshot()["layout"]["shared"].get("walkthrough")
    if previous:
        events.extend(_close_tour(ctx, previous))
        events.extend(tools.close_panel(ctx, previous["narrationNode"])["events"])
    panel = tools.open_panel(ctx, "Walkthrough", "Starting the walkthrough.", "r_tray")
    state = {
        "id": f"tour_{uuid.uuid4().hex[:16]}",
        "step": 0,
        "status": "running",
        "nodes": {},
        "narrationActivity": panel["activityMessageId"],
        "narrationNode": panel["nodeId"],
    }
    _describe(state, 0)
    return _finish(ctx, state, [*events, *panel["events"]])


def _describe(state, step):
    state.update(
        step=step,
        title=STEPS[step][0],
        text=STEPS[step][1],
        delayMs=STEPS[step][2],
        effect=STEPS[step][3],
    )


def _placement(ctx, node_id):
    layout = ctx.snapshot()["layout"]
    owner = tools._panel_target(layout["nodes"], node_id)
    parent = tools._node(layout["nodes"], owner["parentId"])
    return {
        "parent": owner["parentId"],
        "size": owner["size"],
        "visibility": owner["visibility"],
        "order": parent["children"].index(owner["id"]),
    }


def handle_step(projection, scope, run_id, raw, installation=None):
    envelope = ActionEnvelope.model_validate(raw)
    action = envelope.userAction
    if (
        envelope.activityMessageId != projection.layout_activity_id
        or action.surfaceId != projection.layout_surface_id
        or action.sourceComponentId not in (None, "root")
        or action.name
        not in {"workbench.walkthrough.next", "workbench.walkthrough.stop"}
    ):
        raise ValueError("unregistered walkthrough control")
    state = copy.deepcopy(projection.layout["shared"].get("walkthrough"))
    context = action.context
    stopping = action.name.endswith(".stop")
    if (
        not state
        or set(context) != {"id", "step"}
        or context["id"] != state["id"]
        or type(context["step"]) is not int
        or (
            context["step"] != state["step"]
            if action.name.endswith(".next")
            else not 0 <= context["step"] <= state["step"]
        )
        or (not stopping and state["status"] != "running")
    ):
        raise ValueError("unknown, stopped or out-of-order walkthrough step")
    ctx = _context(projection, scope, run_id, installation)
    events = []
    if stopping and state["status"] != "running":
        return _finish(ctx, state, events)
    if stopping:
        state.update(
            status="stopped",
            effect="none",
            text="Walkthrough stopped. Your canvas is ready to use.",
        )
    else:
        step = state["step"] + 1
        if step >= len(STEPS):
            raise ValueError("walkthrough already complete")
        _describe(state, step)
        nodes = state["nodes"]

        def place(key, result):
            events.extend(result["events"])
            nodes[key] = {
                k: result[k] for k in ("nodeId", "surfaceId", "activityMessageId")
            }

        points = [
            {"id": "north", "label": "North", "value": 80},
            {"id": "south", "label": "South", "value": 76},
        ]
        if step == 1:
            split = tools.create_container(
                ctx, "r_canvas", "split", "Walkthrough charts"
            )
            events.extend(split["events"])
            state["split"] = split["nodeId"]
            place(
                "line",
                tools.show_chart(
                    ctx,
                    "Weekly visits",
                    "line",
                    [
                        {"id": day.lower(), "label": day, "value": value}
                        for day, value in zip(
                            ["Mon", "Tue", "Wed", "Thu", "Fri"],
                            [12, 18, 9, 22, 30],
                            strict=True,
                        )
                    ],
                    state["split"],
                ),
            )
        elif step == 2:
            place("bar", tools.show_chart(ctx, "Regions", "bar", points, "r_right"))
            state["barPlacement"] = _placement(ctx, nodes["bar"]["nodeId"])
        elif step in {3, 4}:
            # A user move changes this parent. Never overwrite that placement.
            layout = ctx.snapshot()["layout"]
            owner = tools._panel_target(layout["nodes"], nodes["bar"]["nodeId"])
            if _placement(ctx, owner["id"]) == state["barPlacement"] and not state.get(
                "userPlaced"
            ):
                target = state["split"] if step == 3 else "r_right"
                order = len(tools._node(layout["nodes"], target)["children"])
                events.extend(
                    tools.move_panel(ctx, owner["id"], target, order, "medium")[
                        "events"
                    ]
                )
                state["barPlacement"] = _placement(ctx, owner["id"])
            else:
                state["userPlaced"] = True
                state["text"] = (
                    "You moved the bar chart, so I am keeping your placement. Its stable id and content stay intact."
                )
        elif step == 5:
            place(
                "form",
                tools.place_form(
                    ctx,
                    "Walkthrough Team survey",
                    "r_left",
                    fields=[
                        {
                            "name": "name",
                            "label": "Name",
                            "kind": "text",
                            "required": True,
                        },
                        {
                            "name": "color",
                            "label": "Color",
                            "kind": "choice",
                            "options": ["Red", "Green", "Blue"],
                        },
                        {"name": "subscribe", "label": "Subscribe", "kind": "checkbox"},
                    ],
                ),
            )
        elif step == 7:
            form = nodes["form"]
            submission = validate_submission(
                {
                    "submissionId": f"{state['id']}-sample",
                    "activityMessageId": form["activityMessageId"],
                    "userAction": {
                        "name": "submit_form",
                        "surfaceId": form["surfaceId"],
                        "sourceComponentId": "submit",
                        "context": {"values": SAMPLES},
                    },
                },
                projection,
            )
            filename = append_form_result(
                installation,
                scope,
                submission,
                projection.content[form["activityMessageId"]],
            )
            state["text"] = (
                f"Submitted the sample values. Saved CSV row with submission id {submission.submissionId} in {filename}, in this thread's files."
            )
        elif step == 8:
            place("program", tools.open_demo(ctx, "monty_gui"))
        elif step == len(STEPS) - 1:
            events.extend(_close_tour(ctx, state))
            state["status"] = "complete"
    return _finish(ctx, state, events)


def _close_tour(ctx, state):
    """Close owned surfaces without hiding unrelated content moved into its split."""
    layout = ctx.snapshot()["layout"]
    nodes = state["nodes"]
    program = nodes.get("program", {}).get("surfaceId")
    targets = [item["nodeId"] for item in nodes.values()]
    if program:
        targets.extend(
            key
            for key, owner in layout["shared"].get("programWindows", {}).items()
            if owner == program
        )
    if "split" in state:
        split = tools._node(layout["nodes"], state["split"])
        tour_owners = {
            tools._panel_target(layout["nodes"], item["nodeId"])["id"]
            for item in nodes.values()
        }
        if all(child in tour_owners for child in split["children"]):
            targets.append(split["id"])
    events = []
    for target in dict.fromkeys(targets):
        events.extend(tools.close_panel(ctx, target)["events"])
    return events
