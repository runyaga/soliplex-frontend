"""Fixed A2UI surfaces published into chat as AG-UI activity snapshots.

Proposed for src/soliplex_dojo/src/soliplex_dojo/a2ui_lab.py. Each tool returns
an ActivitySnapshotEvent in ToolReturn.metadata, which pydantic-ai's AG-UI
event stream forwards to the client unchanged. Payloads name components and
carry source text only. The client runs Python only when the user presses Run.
"""

from __future__ import annotations

from ag_ui.core import ActivitySnapshotEvent
from pydantic_ai import RunContext, ToolReturn
from soliplex.agents import AgentDependencies

from soliplex_a2ui_workbench import a2ui_action

# Action-only runs reach the model as one user message per run.
a2ui_action.install()

ACTIVITY_TYPE = "a2ui-surface"
BASIC_CATALOG = "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
LAB_CATALOG = "urn:soliplex:catalog:lab:1"

_WIDGETS = '''import ui

clicks = 0

def build():
    return ui.Card(ui.Column([
        ui.Text(f"Python has seen {clicks} clicks"),
        ui.TextField("Name", ui.bind("/form/name"), "Type a name"),
        ui.Slider("Size", 0, 100, ui.bind("/form/size"), 10),
        ui.Button(ui.Text("Send to Python"), "primary", ui.Event("submit", {
            "name": ui.bind("/form/name"),
            "size": ui.bind("/form/size"),
        })),
    ]))

def handle_event(name, context):
    global clicks
    clicks += 1
    print(name, context)
    ui.show(build(), {"form": context})

ui.show(build(), {"form": {"name": "dojo", "size": 40}})
'''


def _op(surface_id: str, key: str, body: dict) -> dict:
    return {"version": "1.0", key: {"surfaceId": surface_id, **body}}


def _event(ctx: RunContext[AgentDependencies], surface_id: str, ops: list[dict]):
    return ActivitySnapshotEvent(
        message_id=f"a2ui:{ctx.deps.thread_id}:{surface_id}:{ctx.tool_call_id}",
        activity_type=ACTIVITY_TYPE,
        replace=True,
        content={"a2ui_operations": ops},
    )


def basic_surface_operations() -> list[dict]:
    """A checklist made only of basic-catalog components."""
    sid = "dojo-checklist"
    return [
        _op(sid, "createSurface", {"catalogId": BASIC_CATALOG}),
        _op(sid, "updateDataModel", {
            "path": "/",
            "value": {"brief": False, "weather": True, "note": ""},
        }),
        _op(sid, "updateComponents", {"components": [
            {"id": "root", "component": "Column",
             "children": ["title", "brief", "weather", "note"]},
            {"id": "title", "component": "Text", "text": "Mission checklist"},
            {"id": "brief", "component": "CheckBox", "label": "Crew briefed",
             "value": {"@path": "/brief"}},
            {"id": "weather", "component": "CheckBox", "label": "Weather checked",
             "value": {"@path": "/weather"}},
            {"id": "note", "component": "TextField", "label": "Note",
             "value": {"@path": "/note"}},
        ]}),
    ]


DEFAULT_SOURCE = "x = sum(range(10))\nprint(x)\nx * 2"
MAX_SOURCE = 20000
# Repair rounds the client requests without asking. The client clamps it.
REPAIR_ROUNDS = 2
MODES = ("repl", "run")


def python_repl_operations(
    source: str = DEFAULT_SOURCE,
    title: str = "Python in your browser",
    attempt: int = 0,
    chain_id: str | None = None,
    mode: str = "repl",
) -> list[dict]:
    """A PythonRepl from the lab catalog, preloaded with source text only.

    A failed run dispatches ``python_failed`` with the result at
    ``/repl/result``. ``attempt`` and ``chain_id`` mark a repaired editor.
    """
    sid = "dojo-python"
    retry: dict = {"max": REPAIR_ROUNDS}
    if chain_id:
        retry |= {"chainId": chain_id[:64], "attempt": attempt}
    return [
        _op(sid, "createSurface", {"catalogId": BASIC_CATALOG}),
        _op(sid, "updateDataModel", {
            "path": "/",
            "value": {"repl": {"source": source}},
        }),
        _op(sid, "updateComponents", {"components": [
            {"id": "root", "component": "Column", "children": ["title", "repl"]},
            {"id": "title", "component": "Text", "text": title},
            {"id": "repl", "component": "PythonRepl", "catalogId": LAB_CATALOG,
             "source": {"@path": "/repl/source"},
             "outputPath": "/repl/result",
             "mode": mode,
             "retry": retry,
             "onFailure": {"event": {
                 "name": "python_failed",
                 "context": {"result": {"@path": "/repl/result"}},
             }},
             "examples": [{"label": "Widgets from Python", "source": _WIDGETS}]},
        ]}),
    ]


async def show_checklist(ctx: RunContext[AgentDependencies]) -> ToolReturn:
    """Show the user an interactive mission checklist in the chat."""
    event = _event(ctx, "dojo-checklist", basic_surface_operations())
    return ToolReturn({"shown": "checklist"}, metadata=event)


async def show_python_repl(
    ctx: RunContext[AgentDependencies],
    source: str | None = None,
    title: str | None = None,
    attempt: int | None = None,
    chain_id: str | None = None,
    mode: str | None = None,
) -> ToolReturn:
    """Show the user a Python editor that runs code in their browser.

    Args:
        source: Complete Python program to load into the editor. Omit for a
            short starter example.
        title: Short heading shown above the editor.
        attempt: For a repair after python_failed: the attempt number from
            the action. Omit otherwise.
        chain_id: For a repair after python_failed: the chainId from the
            action. Omit otherwise.
        mode: "run" shows a Run button and the latest result, with the code
            behind a toggle, for apps, games and charts. "repl" (default)
            shows the editor and a transcript, for exploring code.

    The user presses Run to execute code. Nothing runs until then.
    """
    text = (source or DEFAULT_SOURCE).strip("\n") + "\n"
    if len(text) > MAX_SOURCE:
        return ToolReturn({"error": f"source exceeds {MAX_SOURCE} characters"})
    heading = (title or "Python in your browser").strip()[:80]
    ops = python_repl_operations(
        text,
        heading,
        attempt=max(int(attempt or 0), 0),
        chain_id=chain_id,
        mode=mode if mode in MODES else "repl",
    )
    event = _event(ctx, "dojo-python", ops)
    return ToolReturn({"shown": "python_repl"}, metadata=event)
