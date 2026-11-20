"""The room guide combines registered catalog teaching and executable examples."""
from __future__ import annotations

import json
from pathlib import Path

from .workbench_schemas import MINIMUM_ROOM_TOOL_MANIFEST

TOOL_EXAMPLES = {
    "get_workbench": {},
    "open_panel": {"title": "Note", "text": "Hello", "parent_id": "r_left"},
    "place_form": {"template": "intake", "title": "Intake", "parent_id": "r_left"},
    "show_chart": {"title": "Counts", "kind": "bar", "points": [{"id": "a", "label": "A", "value": 2.0}], "parent_id": "r_canvas"},
    "run_python_client": {"title": "Tally", "source": 'import ui\nui.show(ui.Text("0"))', "parent_id": "WINDOW_ID"},
    "run_python_server": {"surface_id": "SURFACE_ID", "source": "print(1)"},
    "create_container": {"parent_id": "r_canvas", "kind": "window", "title": "Tally"},
    "move_panel": {"node_id": "NODE_ID", "parent_id": "r_right", "order": 0, "size": "medium"},
    "close_panel": {"node_id": "NODE_ID"},
    "repair_program": {"node_id": "PROGRAM_NODE_ID", "source": 'import ui\nui.show(ui.Text("Fixed"))'},
}

DEMO = '''import ui
result_window = ""

def draw():
    ui.show(ui.Column([
        ui.Text("Compute then open a result window"),
        ui.Button(ui.Text("Compute"), action=ui.Event("compute", {})),
        ui.Button(ui.Text("Close result"), action=ui.Event("close", {})),
    ]), data=DATA)

def handle_event(name, context):
    global result_window
    if name == "compute":
        result = sum([2, 3, 5])
        result_window = ui.workbench.open_window("Result", "text", str(result))
    if name == "close" and result_window:
        ui.workbench.close_window(result_window)
        result_window = ""
    draw()

DATA = {}
draw()
'''


def room_skill(skill_name):
    if set(TOOL_EXAMPLES) != set(MINIMUM_ROOM_TOOL_MANIFEST):
        raise ValueError("workbench tool teaching drift")
    generated = json.loads(Path(__file__).with_name("catalog_teaching.json").read_text())
    examples = []
    for name, arguments in TOOL_EXAMPLES.items():
        MINIMUM_ROOM_TOOL_MANIFEST[name].model_validate(arguments)
        examples.append(f"- `{name}({json.dumps(arguments, ensure_ascii=False)})`")
    basic = next(c for c in generated["catalogs"] if "Text" in c["components"])
    variants = ", ".join(basic["components"]["Text"]["properties"]["variant"]["enum"])
    signatures = "\n".join(f"- `{signature}`" for signature in generated["pythonSignatures"].values())
    return f'''---
name: {skill_name}
description: Workbench tools and the actual registered Python ui API.
---

# Workbench room guide

Call get_workbench first. Keep returned stable ids and call tools incrementally
with parent_id and kind. Never invent agent tool target ids. Windows require
canvas ancestry. No nested windows. Maximum depth 8, splits 3 children, tabs
12, open surfaces 12, open windows 2. Closing a parent hides its descendants.
The user's placements win. run_python_server is declared but disabled and
returns not_enabled. Client tools only publish source; the user presses Run.

To fix a program, call repair_program with its surface node id or window id.
Alternatively run_python_client with replace=true and the existing window id.
These preserve identities and placement and never run the revised source.
Do not close or move the old program before repairing it. A repair reopens a
closed content leaf while keeping its owning window in place.

## One example per registered tool

{chr(10).join(examples)}

## Python ui API

Use import ui and these real signatures. ui.Text exists; ui.Label does not.
Handles are immutable and belong to one execution. Children are list-first:
ui.Column([ui.Text("Hello")]). Button takes a component child, not a string.
Use a plain top-level def handle_event(name, context). Event context is a dict.
Labels are strings. Valid Text variants from the registered catalog: {variants}.
Show at most 3 items side by side.
Use data=DATA on redraw. CLIENT viewport is measured at the next gesture;
do not assume a screen size before a user gesture.

{signatures}

ui.workbench requests are allowed only during the user's Run or button event.
They are staged until successful completion, limited to 8 per gesture, and
accepted by the server using the same tree rules as tools. open_window returns
an id; move_window(id, order=0) reorders on the canvas; close_window(id) closes.
A program may change its own window and windows it opened. kind is text or
python. A python window shows source and Run; opening never executes it.
Replay, reload, restore and layout moves never execute a program or API call.

## Multi-step demo: compute, open result, close result

Put this source in a window with run_python_client. The user presses Run,
then Compute to open a second result window, then Close result.

```python
{DEMO}```

## Generated catalog reference ({generated["generator"]})

This is catalog reference, not a request to emit Express. Author Python source
through the signatures above and publish it with run_python_client.

{generated["catalogTeaching"]}
'''
