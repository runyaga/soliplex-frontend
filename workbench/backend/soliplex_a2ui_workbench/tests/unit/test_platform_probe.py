"""Publication is inert; boundary experiments are explicitly opt-in."""

from pathlib import Path

from soliplex_a2ui_workbench import workbench_tools as tools
from soliplex_a2ui_workbench.workbench_context import WorkbenchToolContext
from soliplex_a2ui_workbench.workbench_projection import RunWorkbenchProjection
from soliplex_a2ui_workbench.workbench_repository import WorkbenchScope
from soliplex_a2ui_workbench.workbench_teaching import (
    ADVANCED_DEMOS,
    DEMO_SUGGESTIONS,
    ROOM_SUGGESTIONS,
    room_skill,
)


def test_platform_probe_publishes_exact_bounded_source_without_execution():
    scope = WorkbenchScope("actor", "server", "room", "thread")
    ctx = WorkbenchToolContext(
        scope, RunWorkbenchProjection(scope), "run", allowed_rooms=frozenset({"room"})
    )
    published = tools.open_demo(ctx, "platform_probe")
    assert published["execution"] == "awaiting_user"
    source = Path(tools.__file__).with_name("platform_probe_demo.py").read_text()
    assert len(source.encode("utf-8")) < 1_000_000
    record = ctx.snapshot()["content"][0]
    assert record["source"] == source
    assert record["output"] == ""
    assert record.get("typeCheck", False) is False
    assert published["confirmation"] == "Platform probe is open; press Run to begin."


def test_probe_has_exact_typed_suggestion_without_room_button():
    text = "Open the platform probe."
    assert DEMO_SUGGESTIONS[text] == "platform_probe"
    assert "platform_probe" not in ADVANCED_DEMOS
    assert text not in ROOM_SUGGESTIONS
    assert f'{text} -> open_demo("platform_probe")' in room_skill("workbench")
