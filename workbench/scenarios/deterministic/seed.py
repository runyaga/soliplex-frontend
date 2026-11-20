"""Seed real thread history with unmodified metadata from workbench wrappers.

Run inside the backend container. Configuration is JSON on stdin, never argv.
The host runner can also execute this source over stdin without copying files.
"""

from __future__ import annotations

import asyncio
import contextlib
import io
import json
import logging
import os
import sys
import warnings
from pathlib import Path

SCENARIOS = (
    "form_in_left_sidebar",
    "chart_on_canvas",
    "program_in_window",
    "fix_program_in_window",
    "second_window",
    "move_panel",
    "close_panel",
    "reload_replay",
)
SOURCE = 'print("scenario original")\n'
FIXED_SOURCE = 'print("scenario fixed")\n'
POINTS = [
    {"id": "north", "label": "North", "value": 80},
    {"id": "south", "label": "South", "value": 76},
]


async def scripted_tools(name, call):
    """Only public wrappers are invoked. Ids come from their actual results."""
    if name in {"form_in_left_sidebar", "reload_replay"}:
        await call(
            "place_form", template="intake", title="Scenario intake", parent_id="r_left"
        )
    elif name == "chart_on_canvas":
        await call(
            "show_chart",
            title="Scenario regions",
            kind="bar",
            points=POINTS,
            parent_id="r_canvas",
        )
    elif name in {"program_in_window", "fix_program_in_window", "second_window"}:
        window = await call(
            "create_container",
            parent_id="r_canvas",
            kind="window",
            title="Scenario program window",
        )
        program = await call(
            "run_python_client",
            title="Scenario program",
            source=SOURCE,
            parent_id=window["nodeId"],
        )
        if name == "fix_program_in_window":
            # Remove the old child before placing its replacement. close_panel
            # preserves edges, so closing it alone does not empty the window.
            retired = await call(
                "create_container",
                parent_id="r_canvas",
                kind="window",
                title="Retired program",
            )
            await call(
                "move_panel",
                node_id=program["nodeId"],
                parent_id=retired["nodeId"],
                order=0,
                size="small",
            )
            await call("close_panel", node_id=retired["nodeId"])
            await call(
                "run_python_client",
                title="Scenario program",
                source=FIXED_SOURCE,
                parent_id=window["nodeId"],
            )
        if name == "second_window":
            second = await call(
                "create_container",
                parent_id="r_canvas",
                kind="window",
                title="Scenario second window",
            )
            await call(
                "open_panel",
                title="Scenario second content",
                text="Second window is populated",
                parent_id=second["nodeId"],
            )
    elif name == "move_panel":
        chart = await call(
            "show_chart",
            title="Scenario regions",
            kind="bar",
            points=POINTS,
            parent_id="r_canvas",
        )
        tree = await call("get_workbench")
        panel = next(
            node["parentId"] for node in tree["nodes"] if node["id"] == chart["nodeId"]
        )
        await call(
            "move_panel", node_id=panel, parent_id="r_right", order=0, size="medium"
        )
    elif name == "close_panel":
        # A remaining surface makes a blank workspace an explicit failure.
        await call(
            "open_panel",
            title="Scenario retained",
            text="Retained canvas content",
            parent_id="r_canvas",
        )
        form = await call(
            "place_form", template="intake", title="Scenario intake", parent_id="r_left"
        )
        tree = await call("get_workbench")
        panel = next(
            node["parentId"] for node in tree["nodes"] if node["id"] == form["nodeId"]
        )
        await call("close_panel", node_id=panel)
    else:
        raise ValueError("unknown scenario")


async def seed_one(config, installation, engine, name):
    from ag_ui.core import RunAgentInput, RunFinishedEvent, RunStartedEvent
    from pydantic_ai import RunContext, ToolReturn
    from pydantic_ai.usage import RunUsage
    from soliplex.agents import AgentDependencies
    from soliplex.agui.persistence import ThreadStorage
    from soliplex.models import UserProfile
    from soliplex_a2ui_workbench import workbench_agent_tools as wrappers
    from sqlalchemy.ext.asyncio import AsyncSession

    async with AsyncSession(engine, expire_on_commit=False) as session:
        async with session.begin():
            storage = ThreadStorage(session)
            thread = await storage.new_thread(
                user_name=config["user"],
                email=config["email"],
                room_id=config["room"],
                thread_metadata={"name": f"Scenario: {name}"},
            )
            # v0.93 creates an initial run even with initial_run=False.
            run = (await thread.list_runs())[0]
            identity = {
                "user_name": config["user"],
                "room_id": config["room"],
                "thread_id": thread.thread_id,
                "run_id": run.run_id,
            }
            await storage.add_run_input(
                **identity,
                run_input=RunAgentInput(
                    thread_id=thread.thread_id,
                    run_id=run.run_id,
                    state={},
                    messages=[],
                    tools=[],
                    context=[],
                    forwarded_props={},
                ),
            )
            deps = AgentDependencies(
                the_installation=installation,
                thread_persistence_engine=engine,
                room_id=config["room"],
                thread_id=thread.thread_id,
                run_id=run.run_id,
                user=UserProfile(
                    given_name="Scenario",
                    family_name="Harness",
                    email=config["email"],
                    preferred_username=config["user"],
                ),
            )
            # Commit the identity first, so the wrapper's separate authenticated
            # history read can see the actual thread. No inference is performed.
        async with session.begin():
            ctx = RunContext(deps=deps, model=None, usage=RunUsage())
            events = [RunStartedEvent(thread_id=thread.thread_id, run_id=run.run_id)]

            async def call(tool, **kwargs):
                result = await getattr(wrappers, tool)(ctx, **kwargs)
                if isinstance(result, ToolReturn):
                    if not isinstance(result.metadata, list) or not result.metadata:
                        raise ValueError("wrapper did not return activity metadata")
                    events.extend(result.metadata)
                    result = result.return_value
                if not isinstance(result, dict) or "error" in result:
                    raise ValueError("wrapper failed")
                return result

            await scripted_tools(name, call)
            events.append(
                RunFinishedEvent(thread_id=thread.thread_id, run_id=run.run_id)
            )
            # This public API stores typed events AND marks the run completed.
            await storage.save_run_events(**identity, events=events)
        return thread.thread_id


async def seed(config):
    from soliplex.cli.cli_util import get_installation
    from sqlalchemy.ext.asyncio import create_async_engine

    installation = get_installation(
        Path(
            config.get("installation")
            or os.environ.get("SOLIPLEX_INSTALLATION_PATH", "/environment")
        )
    )
    installation.resolve_secrets()
    installation.resolve_environment()
    engine = create_async_engine(
        installation.thread_persistence_async_dburi, echo=False
    )
    results = []
    try:
        for name in SCENARIOS:
            try:
                thread_id = await seed_one(config, installation, engine, name)
            except Exception:  # noqa: BLE001 - never echo credential-bearing library failures
                thread_id = None
            results.append({"scenario": name, "thread_id": thread_id})
    finally:
        await engine.dispose()
    return results


def main(config):
    # Database and config exceptions may contain connection strings. Never
    # forward library stdout, stderr, warnings, or traceback text to the host.
    logging.disable(logging.CRITICAL)
    warnings.filterwarnings("ignore")
    try:
        with (
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            results = asyncio.run(seed(config))
    except Exception:  # noqa: BLE001 - redact config and database failures at the process boundary
        results = [{"scenario": name, "thread_id": None} for name in SCENARIOS]
    print(json.dumps(results))
    return int(any(item["thread_id"] is None for item in results))


if __name__ == "__main__":
    try:
        settings = globals().get("SCENARIO_CONFIG") or json.loads(sys.stdin.readline())
        sys.exit(main(settings))
    except Exception:  # noqa: BLE001 - malformed input must not produce a traceback
        # Deliberately no exception payloads, including malformed configuration.
        sys.exit(1)
