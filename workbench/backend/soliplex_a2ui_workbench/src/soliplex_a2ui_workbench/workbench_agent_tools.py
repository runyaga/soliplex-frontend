"""Soliplex-facing adapters for the deterministic workbench tools."""

from __future__ import annotations

import asyncio
import json

from ag_ui.core import ActivitySnapshotEvent
from pydantic import ValidationError
from pydantic_ai import ModelRetry, RunContext, ToolReturn
from soliplex.agents import AgentDependencies

from . import workbench_tools
from .workbench_context import WorkbenchToolContext, configured_rooms
from .workbench_projection import projection_from_thread
from .workbench_routes import workbench_scope
from .workbench_schemas import MINIMUM_ROOM_TOOL_MANIFEST


async def _context(ctx: RunContext[AgentDependencies]) -> WorkbenchToolContext:
    """Create one working projection on the run-owned dependency object."""
    deps = ctx.deps
    user = deps.user
    actor = getattr(user, "preferred_username", None) or getattr(user, "username", None)
    if not actor or not deps.room_id or not deps.thread_id or not deps.run_id:
        raise ValueError(
            "authenticated user, room, thread, and run are required for workbench tools"
        )
    scope = workbench_scope(
        deps.the_installation, str(actor), deps.room_id, deps.thread_id
    )
    allowed_rooms = configured_rooms()
    if scope.room_id not in allowed_rooms:
        raise PermissionError(
            "workbench room is not configured in SOLIPLEX_WORKBENCH_ROOMS"
        )
    if not hasattr(deps, "_workbench_lock"):
        deps._workbench_lock = asyncio.Lock()
    async with deps._workbench_lock:
        existing = getattr(deps, "_workbench_context", None)
        if (
            existing is None
            or existing.scope != scope
            or existing.run_id != deps.run_id
        ):
            deps._workbench_context = WorkbenchToolContext(
                scope,
                await projection_from_thread(deps, scope),
                deps.run_id,
                allowed_rooms=allowed_rooms,
            )
        return deps._workbench_context


async def get_workbench(ctx: RunContext[AgentDependencies]) -> dict[str, object]:
    """Return the current workbench structure, catalogs, templates, and revision."""
    return await _call(workbench_tools.get_workbench, ctx)


async def open_panel(
    ctx: RunContext[AgentDependencies], title: str, text: str, parent_id: str
) -> ToolReturn:
    """Open a text panel with the supplied text.

    Args:
        title: Short heading shown on the panel.
        text: Text content to display.
        parent_id: Existing container node where the panel should be placed.
    """
    return await _call(
        workbench_tools.open_panel, ctx, title=title, text=text, parent_id=parent_id
    )


async def place_form(
    ctx: RunContext[AgentDependencies], template: str, title: str, parent_id: str
) -> ToolReturn:
    """Place the built-in intake form.

    Args:
        template: The available form template, currently ``intake``.
        title: Short heading shown above the form.
        parent_id: Existing container node where the form should be placed.
    """
    return await _call(
        workbench_tools.place_form,
        ctx,
        template=template,
        title=title,
        parent_id=parent_id,
    )


async def show_chart(
    ctx: RunContext[AgentDependencies],
    title: str,
    kind: str,
    points: list[dict[str, object]],
    parent_id: str,
) -> ToolReturn:
    """Show a chart using the supplied data points.

    Args:
        title: Short chart heading.
        kind: Chart style, either ``bar`` or ``line``.
        points: Data points, each with a unique ``id``, display ``label``, and numeric ``value``.
        parent_id: Existing container node where the chart should be placed.
    """
    return await _call(
        workbench_tools.show_chart,
        ctx,
        title=title,
        kind=kind,
        points=points,
        parent_id=parent_id,
    )


async def run_python_client(
    ctx: RunContext[AgentDependencies],
    title: str,
    source: str,
    parent_id: str,
    replace: bool = False,
) -> ToolReturn:
    """Create an inert Python editor that runs only after the user presses Run.

    Args:
        title: Short heading shown above the editor.
        source: Python source text to preload; it is not executed by this tool.
        parent_id: Container on the canvas, or inside an existing window. A window is created if needed.
        replace: Replace its existing program, retaining window and surface ids.
    """
    return await _call(
        workbench_tools.run_python_client,
        ctx,
        title=title,
        source=source,
        parent_id=parent_id,
        replace=replace,
    )


async def run_python_server(
    ctx: RunContext[AgentDependencies], surface_id: str, source: str
) -> dict[str, str]:
    """Request server-side execution for a workbench Python surface.

    Args:
        surface_id: Identity of the Python surface to execute.
        source: Python source text requested for execution.
    """
    return await _call(
        workbench_tools.run_python_server, ctx, surface_id=surface_id, source=source
    )


async def create_container(
    ctx: RunContext[AgentDependencies], parent_id: str, kind: str, title: str
) -> ToolReturn:
    """Create an empty workbench container.

    Args:
        parent_id: Existing container node that will contain the new node.
        kind: Container style: ``split``, ``tabs``, ``panel``, or ``window``.
        title: Short label for the new container.
    """
    return await _call(
        workbench_tools.create_container,
        ctx,
        parent_id=parent_id,
        kind=kind,
        title=title,
    )


async def move_panel(
    ctx: RunContext[AgentDependencies],
    node_id: str,
    parent_id: str,
    order: int,
    size: str,
) -> ToolReturn:
    """Move a workbench panel and set its placement.

    Args:
        node_id: Identity of the panel to move.
        parent_id: Existing container node that will receive the panel.
        order: Zero-based position among the container's children.
        size: Requested panel size: ``small``, ``medium``, or ``large``.
    """
    return await _call(
        workbench_tools.move_panel,
        ctx,
        node_id=node_id,
        parent_id=parent_id,
        order=order,
        size=size,
    )


async def close_panel(ctx: RunContext[AgentDependencies], node_id: str) -> ToolReturn:
    """Close a workbench panel.

    Args:
        node_id: Identity of the panel to close.
    """
    return await _call(workbench_tools.close_panel, ctx, node_id=node_id)


async def repair_program(
    ctx: RunContext[AgentDependencies],
    source: str,
    node_id: str | None = None,
    parent_id: str | None = None,
    title: str = "Python",
) -> ToolReturn:
    """Replace the source text of a workbench Python program.

    Args:
        node_id: Existing program surface or window to repair; omit when using parent_id.
        source: Updated Python source text to show in the editor.
        parent_id: Container for a new program, creating a window if needed; omit node_id.
        title: Heading for a newly created program window.
    """
    return await _call(
        workbench_tools.repair_program,
        ctx,
        node_id=node_id,
        source=source,
        parent_id=parent_id,
        title=title,
    )


async def _call(function, ctx: RunContext[AgentDependencies], **kwargs):
    try:
        arguments = (
            MINIMUM_ROOM_TOOL_MANIFEST[function.__name__]
            .model_validate(kwargs)
            .model_dump()
        )
        result = function(await _context(ctx), **arguments)
        if "events" not in result:
            return result
        content = {key: value for key, value in result.items() if key != "events"}
        events = [
            ActivitySnapshotEvent.model_validate(part["event"])
            for part in result["events"]
        ]
        return ToolReturn(content, metadata=events)
    except (ValueError, PermissionError) as exc:
        # Pydantic errors normally echo rejected input (including Python source).
        # Keep field locations and reasons, never the rejected input or context.
        if isinstance(exc, ValidationError):
            detail = "; ".join(
                f"{'.'.join(map(str, error['loc'])) or 'layout'}: {error['msg']}"
                for error in exc.errors(
                    include_input=False, include_context=False, include_url=False
                )
            )
        else:
            detail = str(exc)
        correction = "Call get_workbench, then retry with valid node ids and arguments."
        if "window ancestry" in detail or "canvas ancestry" in detail:
            correction = (
                "Programs need a window on the canvas: call create_container(kind='window', "
                "parent_id='r_canvas', title='Program') first, or pass a window id. "
                "run_python_client also accepts parent_id='r_canvas' to create one automatically."
            )
        # The error envelope survives AG-UI versions without tool outcome fields.
        # ModelRetry also makes this a rejected call in the model's own history.
        raise ModelRetry(
            json.dumps({"error": f"{function.__name__}: {detail}. {correction}"})
        ) from exc
