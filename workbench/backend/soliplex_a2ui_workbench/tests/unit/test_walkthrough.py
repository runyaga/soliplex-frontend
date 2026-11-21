"""The tour is server-scripted, validated, ordered and model-free."""

import copy
from types import SimpleNamespace
from unittest.mock import patch

import pytest
from ag_ui.core import ActivitySnapshotEvent
from fastapi import APIRouter, FastAPI, Request
from fastapi.testclient import TestClient
from pydantic_ai import Agent
from pydantic_ai.models.function import FunctionModel
from pydantic_ai.ui.ag_ui import AGUIAdapter
from soliplex_a2ui_workbench import workbench_projection
from soliplex_a2ui_workbench import workbench_tools as tools
from soliplex_a2ui_workbench.workbench_projection import RunWorkbenchProjection
from soliplex_a2ui_workbench.workbench_repository import WorkbenchScope
from soliplex_a2ui_workbench.workbench_routes import create_guarded_agui_router
from soliplex_a2ui_workbench.workbench_schemas import (
    LayoutSnapshot,
    validate_registered_mounts,
)
from soliplex_a2ui_workbench.workbench_teaching import ROOM_SUGGESTIONS, room_skill
from soliplex_a2ui_workbench.workbench_walkthrough import (
    SAMPLES,
    STEPS,
    SUGGESTION,
    _context,
    handle_step,
    start_walkthrough,
)


def fixture(tmp_path):
    scope = WorkbenchScope("actor", "server", "room", "thread")
    projection = RunWorkbenchProjection(scope)
    installation = SimpleNamespace(sandbox_workdirs_path=tmp_path)
    start = start_walkthrough(_context(projection, scope, "start", installation))
    projection.test_history = [
        ActivitySnapshotEvent.model_validate(part["event"]) for part in start["events"]
    ]
    return scope, projection, installation


def envelope(projection, action="next", **context):
    state = projection.layout["shared"]["walkthrough"]
    return {
        "submissionId": f"action-{state['step']}-{action}",
        "activityMessageId": projection.layout_activity_id,
        "userAction": {
            "name": f"workbench.walkthrough.{action}",
            "surfaceId": projection.layout_surface_id,
            "sourceComponentId": "root",
            "context": {"id": state["id"], "step": state["step"], **context},
        },
    }


def advance(scope, projection, installation):
    return handle_step(projection, scope, "next", envelope(projection), installation)


def assert_layout(projection):
    layout = LayoutSnapshot.model_validate(
        projection.layout,
        context={"authenticated_program_surfaces": projection.programs},
    )
    validate_registered_mounts(layout, projection.mounts)


def test_every_step_uses_validator_and_stable_ids_and_saves_real_csv(tmp_path):
    scope, projection, installation = fixture(tmp_path)
    ctx = _context(projection, scope, "unrelated", installation)
    other = tools.open_panel(ctx, "My own panel", "Keep me", "r_canvas")
    history = [
        *projection.test_history,
        *[
            ActivitySnapshotEvent.model_validate(part["event"])
            for part in other["events"]
        ],
    ]
    with patch.object(
        workbench_projection,
        "build_publication",
        wraps=workbench_projection.build_publication,
    ) as validator:
        for step in range(1, len(STEPS)):
            result = advance(scope, projection, installation)
            assert result["narration"].startswith(f"Step {step + 1} of {len(STEPS)}")
            assert result["events"]
            assert_layout(projection)
            state = projection.layout["shared"]["walkthrough"]
            history.extend(
                ActivitySnapshotEvent.model_validate(part["event"])
                for part in result["events"]
            )
            if step == 2:
                bar = copy.deepcopy(state["nodes"]["bar"])
            if step in {3, 4}:
                assert state["nodes"]["bar"] == bar
                parent = tools._panel_target(projection.layout["nodes"], bar["nodeId"])[
                    "parentId"
                ]
                assert parent == (state["split"] if step == 3 else "r_right")
            if step == 7:
                assert "walkthrough-team-survey.csv" in result["narration"]
                assert f"{state['id']}-sample" in result["narration"]
            if step == 8:
                record = projection.content[
                    state["nodes"]["program"]["activityMessageId"]
                ]
                assert (
                    record["source"]
                    == tools.Path(tools.__file__)
                    .with_name("monty_gui_demo.py")
                    .read_text()
                )
        assert validator.call_count >= len(STEPS) - 1
    assert state["status"] == "complete"
    assert (
        tools._panel_target(projection.layout["nodes"], other["nodeId"])["visibility"]
        == "open"
    )
    for key, node in state["nodes"].items():
        assert tools._panel_target(projection.layout["nodes"], node["nodeId"])[
            "visibility"
        ] == ("closed" if key == "form" else "open")
    assert (
        tools._panel_target(projection.layout["nodes"], state["narrationNode"])[
            "visibility"
        ]
        == "open"
    )
    csv = (tmp_path / "room/thread/walkthrough-team-survey.csv").read_text()
    assert "Sample visitor,Blue,true" in csv
    assert SAMPLES["name"] in csv
    # Restored history contains state, but folding it executes neither a step nor Python.
    replay = RunWorkbenchProjection(scope, history)
    assert replay.layout["shared"]["walkthrough"]["status"] == "complete"


@pytest.mark.parametrize("step", range(len(STEPS) - 1))
def test_stop_at_every_step_and_reject_further_actions(tmp_path, step):
    scope, projection, installation = fixture(tmp_path)
    for _ in range(step):
        advance(scope, projection, installation)
    result = handle_step(
        projection, scope, "stop", envelope(projection, "stop"), installation
    )
    assert "stopped" in result["narration"]
    assert_layout(projection)
    with pytest.raises(ValueError, match="stopped"):
        advance(scope, projection, installation)


def test_unknown_out_of_order_and_wrong_source_are_rejected_without_mutation(tmp_path):
    scope, projection, installation = fixture(tmp_path)
    before = copy.deepcopy(projection.layout)
    for context in [
        {"step": 10},
        {"step": -1},
        {"step": True},
        {"id": "unknown"},
        {"extra": 1},
    ]:
        with pytest.raises(ValueError):
            handle_step(
                projection, scope, "bad", envelope(projection, **context), installation
            )
        assert projection.layout == before
    raw = envelope(projection)
    raw["userAction"]["surfaceId"] = "foreign"
    with pytest.raises(ValueError, match="control"):
        handle_step(projection, scope, "bad", raw, installation)


def test_user_placement_wins(tmp_path):
    scope, projection, installation = fixture(tmp_path)
    advance(scope, projection, installation)
    advance(scope, projection, installation)
    state = projection.layout["shared"]["walkthrough"]
    bar = state["nodes"]["bar"]["nodeId"]
    tools.move_panel(_context(projection, scope, "user"), bar, "r_left", 0, "small")
    advance(scope, projection, installation)
    advance(scope, projection, installation)
    assert tools._panel_target(projection.layout["nodes"], bar)["parentId"] == "r_left"
    assert (
        "keeping your placement" in projection.layout["shared"]["walkthrough"]["text"]
    )


def test_complete_action_only_route_streams_story_and_never_calls_model(tmp_path):
    scope = WorkbenchScope("actor", "server", "room", "thread")
    projection = RunWorkbenchProjection(scope)
    model_calls = []
    upstream = APIRouter()

    def forbidden(*args):
        model_calls.append(args)
        raise AssertionError("walkthrough must never infer")

    @upstream.post("/v1/rooms/{room_id}/agui/{thread_id}/{run_id}")
    async def endpoint(request: Request):
        request.state.workbench_installation = SimpleNamespace(
            sandbox_workdirs_path=tmp_path
        )
        adapter = await AGUIAdapter.from_request(
            request, agent=Agent(FunctionModel(forbidden))
        )
        events = [e async for e in adapter.run_stream()]
        for event in events:
            projection._fold(event)
        return [e.model_dump(mode="json", by_alias=True) for e in events]

    app = FastAPI()
    app.include_router(
        create_guarded_agui_router(
            upstream,
            scope_provider=scope,
            projection_provider=lambda *_: projection,
            workbench_rooms={scope.room_id},
        )
    )
    client = TestClient(app)

    def send(step=None):
        run = f"tour-{step}"
        return client.post(
            f"/v1/rooms/room/agui/thread/{run}",
            json={
                "threadId": "thread",
                "runId": run,
                "state": {},
                "tools": [],
                "context": [],
                "messages": [{"id": "start", "role": "user", "content": SUGGESTION}]
                if step is None
                else [],
                "forwardedProps": {}
                if step is None
                else {"a2uiAction": envelope(projection)},
            },
        )

    for step in [None, *range(1, len(STEPS))]:
        response = send(step)
        assert response.status_code == 200, response.text
        events = response.json()
        assert events[0]["type"] == "RUN_STARTED"
        assert events[-1]["type"] == "RUN_FINISHED"
        assert [e["type"] for e in events[-4:-1]] == [
            "TEXT_MESSAGE_START",
            "TEXT_MESSAGE_CONTENT",
            "TEXT_MESSAGE_END",
        ]
        assert f"Step {(step or 0) + 1} of {len(STEPS)}" in events[-3]["delta"]
    assert not model_calls
    assert send(99).status_code == 422


def test_start_suggestion_and_teaching():
    assert ROOM_SUGGESTIONS[0] == SUGGESTION
    assert "call start_walkthrough(); do nothing else" in room_skill("workbench")


def test_harness_step_titles_match_the_server_script():
    import json
    from pathlib import Path

    path = Path(__file__).parents[4] / "scenarios/model/walkthrough.json"
    checkpoints = json.loads(path.read_text())
    assert [item["title"] for item in checkpoints] == [step[0] for step in STEPS]
    assert all(item["assertions"] for item in checkpoints)


def test_stop_handles_an_in_flight_next_and_repeated_stop(tmp_path):
    scope, projection, installation = fixture(tmp_path)
    stop = envelope(projection, "stop")
    advance(scope, projection, installation)
    handle_step(projection, scope, "stop", stop, installation)
    assert projection.layout["shared"]["walkthrough"]["status"] == "stopped"
    handle_step(projection, scope, "stop-again", stop, installation)
    assert projection.layout["shared"]["walkthrough"]["status"] == "stopped"


def test_user_resizing_in_the_same_region_wins(tmp_path):
    scope, projection, installation = fixture(tmp_path)
    for _ in range(2):
        advance(scope, projection, installation)
    state = projection.layout["shared"]["walkthrough"]
    bar = state["nodes"]["bar"]["nodeId"]
    tools.move_panel(_context(projection, scope, "user"), bar, "r_right", 0, "small")
    advance(scope, projection, installation)
    assert tools._panel_target(projection.layout["nodes"], bar)["parentId"] == "r_right"
    assert tools._panel_target(projection.layout["nodes"], bar)["size"] == "small"


def test_wrap_up_keeps_unrelated_content_moved_inside_the_tour_split(tmp_path):
    scope, projection, installation = fixture(tmp_path)
    advance(scope, projection, installation)
    state = projection.layout["shared"]["walkthrough"]
    other = tools.open_panel(
        _context(projection, scope, "user"), "My notes", "Keep me", state["split"]
    )
    for _ in range(2, len(STEPS)):
        advance(scope, projection, installation)
    assert (
        tools._node(projection.layout["nodes"], state["split"])["visibility"] == "open"
    )
    assert (
        tools._panel_target(projection.layout["nodes"], other["nodeId"])["visibility"]
        == "open"
    )


def test_explicit_restart_cleans_only_previous_tour_surfaces(tmp_path):
    scope, projection, installation = fixture(tmp_path)
    for _ in range(8):
        advance(scope, projection, installation)
    previous = copy.deepcopy(projection.layout["shared"]["walkthrough"])
    other = tools.open_panel(
        _context(projection, scope, "user"), "My notes", "Keep", "r_left"
    )
    start_walkthrough(_context(projection, scope, "restart", installation))
    current = projection.layout["shared"]["walkthrough"]
    assert current["id"] != previous["id"]
    assert current["step"] == 0
    for item in previous["nodes"].values():
        assert (
            tools._panel_target(projection.layout["nodes"], item["nodeId"])[
                "visibility"
            ]
            == "closed"
        )
    assert (
        tools._panel_target(projection.layout["nodes"], other["nodeId"])["visibility"]
        == "open"
    )
