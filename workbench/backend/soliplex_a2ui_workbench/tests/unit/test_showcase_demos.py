"""Curated suggestions publish reviewed source and remain inert until Run."""

import json
from pathlib import Path

import pytest
from pydantic_ai.ui.ag_ui import AGUIAdapter
from soliplex_a2ui_workbench import workbench_tools as tools
from soliplex_a2ui_workbench.workbench_context import WorkbenchToolContext
from soliplex_a2ui_workbench.workbench_projection import RunWorkbenchProjection
from soliplex_a2ui_workbench.workbench_repository import WorkbenchScope
from soliplex_a2ui_workbench.workbench_teaching import ROOM_SUGGESTIONS, room_skill


@pytest.mark.parametrize(
    "name",
    [
        "survey_results",
        "notes",
        "todo",
        "sales_pipeline",
        "hot_patch",
        "reproducer",
        "healing_pipeline",
    ],
)
def test_curated_demo_is_exact_inert_source(name):
    scope = WorkbenchScope("actor", "server", "room", "thread")
    ctx = WorkbenchToolContext(
        scope, RunWorkbenchProjection(scope), "run", allowed_rooms=frozenset({"room"})
    )
    result = tools.open_demo(ctx, name)
    assert result["execution"] == "awaiting_user"
    record = next(
        r for r in ctx.snapshot()["content"] if r["surfaceId"] == result["surfaceId"]
    )
    assert (
        record["source"]
        == Path(tools.__file__).with_name(f"{name}_demo.py").read_text()
    )
    assert record.get("typeCheck", False) == (name == "healing_pipeline")


def test_every_suggestion_has_a_user_case_and_curated_teaching():
    cases = json.loads(
        (Path(__file__).parents[4] / "scenarios/model/prompts.yaml").read_text()
    )
    assert len(ROOM_SUGGESTIONS) == 12
    for suggestion in ROOM_SUGGESTIONS:
        assert any(case["prompt"] == suggestion for case in cases), suggestion
    for name in [
        "survey_results",
        "notes",
        "todo",
        "sales_pipeline",
        "hot_patch",
        "reproducer",
        "healing_pipeline",
    ]:
        assert f'open_demo("{name}")' in room_skill("workbench")


def test_form_receipt_streams_before_model_reply_and_survives_replay(tmp_path):
    from types import SimpleNamespace

    from ag_ui.core import ActivitySnapshotEvent
    from fastapi import APIRouter, FastAPI, Request
    from fastapi.testclient import TestClient
    from pydantic_ai import Agent
    from pydantic_ai.messages import ModelResponse, TextPart
    from pydantic_ai.models.function import FunctionModel
    from soliplex_a2ui_workbench.workbench_actions import validate_submission
    from soliplex_a2ui_workbench.workbench_form_results import append_form_result
    from soliplex_a2ui_workbench.workbench_routes import create_guarded_agui_router

    scope = WorkbenchScope("actor", "server", "room", "thread")
    projection = RunWorkbenchProjection(scope)
    ctx = WorkbenchToolContext(
        scope, projection, "place", allowed_rooms=frozenset({"room"})
    )
    placed = tools.place_form(ctx, "Team survey", "r_left", fields=["Name"])
    history = [part["event"] for part in placed["events"]]
    record = projection.content[placed["activityMessageId"]]
    installation = SimpleNamespace(sandbox_workdirs_path=tmp_path)
    upstream = APIRouter()

    @upstream.post("/v1/rooms/{room_id}/agui/{thread_id}/{run_id}")
    async def endpoint(request: Request):
        request.state.workbench_installation = installation
        adapter = await AGUIAdapter.from_request(
            request,
            agent=Agent(
                FunctionModel(lambda *_: ModelResponse(parts=[TextPart("Saved.")]))
            ),
        )
        return [
            event.model_dump(mode="json", by_alias=True, exclude_none=True)
            async for event in adapter.run_stream()
        ]

    app = FastAPI()
    app.include_router(
        create_guarded_agui_router(
            upstream,
            scope_provider=scope,
            projection_provider=lambda *_: projection,
            workbench_rooms={"room"},
        )
    )
    envelope = {
        "submissionId": "one",
        "activityMessageId": placed["activityMessageId"],
        "userAction": {
            "name": "submit_form",
            "surfaceId": placed["surfaceId"],
            "sourceComponentId": "submit",
            "context": {"values": {"name": "Casey"}},
        },
    }
    response = TestClient(app).post(
        "/v1/rooms/room/agui/thread/submit",
        json={
            "threadId": "thread",
            "runId": "submit",
            "state": {},
            "tools": [],
            "context": [],
            "messages": [],
            "forwardedProps": {"a2uiAction": envelope},
        },
    )
    assert response.status_code == 200, response.text
    events = response.json()
    assert events[0]["type"] == "RUN_STARTED"
    assert events[1]["type"] == "ACTIVITY_SNAPSHOT", events
    assert "Saved row 1 to team-survey.csv" in json.dumps(events[1])
    replay = RunWorkbenchProjection(
        scope,
        [
            ActivitySnapshotEvent.model_validate(e)
            for e in [*history, *events]
            if e["type"] == "ACTIVITY_SNAPSHOT"
        ],
    )
    assert (
        replay.content[record["activityMessageId"]]["receipt"]
        == "Saved row 1 to team-survey.csv"
    )
    submission = validate_submission(envelope, projection)
    assert append_form_result(
        installation, scope, submission, record, with_receipt=True
    ) == {"filename": "team-survey.csv", "row": 1}


def test_suggestions_are_short_and_have_an_exact_demo_mapping():
    from soliplex_a2ui_workbench.workbench_teaching import DEMO_SUGGESTIONS

    assert set(ROOM_SUGGESTIONS[1:]) == set(DEMO_SUGGESTIONS)
    assert len(set(DEMO_SUGGESTIONS.values())) == 11
    for text, name in DEMO_SUGGESTIONS.items():
        assert len(text) <= 65
        assert f'{text} -> open_demo("{name}")' in room_skill("workbench")


@pytest.mark.parametrize(
    "name",
    [
        "monty_gui",
        "syntax_error",
        "name_error",
        "type_check",
        "survey_results",
        "notes",
        "todo",
        "sales_pipeline",
        "hot_patch",
        "reproducer",
        "healing_pipeline",
    ],
)
def test_every_demo_returns_one_user_confirmation_separate_from_guidance(name):
    scope = WorkbenchScope("actor", "server", "room", "thread")
    ctx = WorkbenchToolContext(
        scope, RunWorkbenchProjection(scope), "run", allowed_rooms=frozenset({"room"})
    )
    result = tools.open_demo(ctx, name)
    confirmation = result["confirmation"]
    assert confirmation.count(".") == 1
    assert "Run" in confirmation
    assert not any(
        word in confirmation for word in ["STATE", "pending", "division", "repairing"]
    )
    assert "Reply with only" in result["instruction"]
