"""Program actions use authenticated activities and never invoke inference."""

import asyncio
import copy

from ag_ui.core import ActivitySnapshotEvent
from fastapi import APIRouter, FastAPI, Request
from fastapi.testclient import TestClient
from pydantic_ai import Agent
from pydantic_ai.models.function import FunctionModel
from pydantic_ai.ui.ag_ui import AGUIAdapter
import pytest

from test_workbench_agent_tools import publication_fixture
from soliplex_a2ui_workbench.program_actions import apply_program_actions
from soliplex_a2ui_workbench.workbench_projection import RunWorkbenchProjection
from soliplex_a2ui_workbench.workbench_routes import create_guarded_agui_router


def fixture():
    ctx, form, chart, window, program = asyncio.run(publication_fixture())
    scope = ctx.deps._workbench_context.scope
    initial_events = [
        event for result in [form, chart, window, program] for event in result.metadata
    ]
    projection = RunWorkbenchProjection(scope, initial_events)
    projection.test_history = initial_events
    record = next(
        r for r in projection.content.values() if r["component"] == "PythonRepl"
    )
    return scope, projection, record, window.return_value["nodeId"]


def test_program_batch_is_atomic_bounded_and_owner_scoped():
    scope, projection, record, window = fixture()
    before = copy.deepcopy(projection.layout)
    opened = {
        "op": "open",
        "window_id": "result_window",
        "title": "Result",
        "kind": "text",
        "content": "10",
    }
    events = apply_program_actions(projection, scope, "run", record, [opened])
    assert projection.layout == before  # No partial changes before delivery.
    accepted = copy.deepcopy(projection)
    for e in events:
        accepted._fold(ActivitySnapshotEvent.model_validate(e))
    assert (
        accepted.layout["shared"]["programWindows"]["result_window"]
        == record["surfaceId"]
    )
    moved = apply_program_actions(
        accepted,
        scope,
        "move",
        record,
        [{"op": "move", "window_id": "result_window", "order": 0}],
    )
    for e in moved:
        accepted._fold(ActivitySnapshotEvent.model_validate(e))
    closed = apply_program_actions(
        accepted,
        scope,
        "close",
        record,
        [{"op": "close", "window_id": "result_window"}],
    )
    for e in closed:
        accepted._fold(ActivitySnapshotEvent.model_validate(e))
    assert (
        next(n for n in accepted.layout["nodes"] if n["id"] == "result_window")[
            "visibility"
        ]
        == "closed"
    )
    for actions in [
        [opened] * 9,
        [{"op": "close", "window_id": "r_chat"}],
        [{"op": "close", "window_id": "node_3"}],
        [
            opened,
            {
                "op": "open",
                "window_id": "third",
                "title": "Third",
                "kind": "text",
                "content": "x",
            },
        ],
    ]:
        with pytest.raises(ValueError):
            apply_program_actions(projection, scope, "reject", record, actions)
        assert projection.layout == before


def test_opened_python_is_inert_source_with_no_retry():
    scope, projection, record, _ = fixture()
    events = apply_program_actions(
        projection,
        scope,
        "run",
        record,
        [
            {
                "op": "open",
                "window_id": "child",
                "title": "Child",
                "kind": "python",
                "content": "print(2)",
            }
        ],
    )
    components = events[0]["content"]["a2ui_operations"][-1]["updateComponents"][
        "components"
    ]
    assert components[0]["component"] == "PythonRepl"
    assert "retry" not in components[0]
    assert (
        events[0]["content"]["a2ui_operations"][1]["updateDataModel"]["value"]["source"]
        == "print(2)"
    )


def test_action_only_stream_opens_closes_and_replay_runs_no_model():
    scope, projection, record, _ = fixture()
    upstream = APIRouter()
    model_calls = []

    def forbidden(*args):
        model_calls.append(args)
        raise AssertionError("inference forbidden")

    @upstream.post("/v1/rooms/{room_id}/agui/{thread_id}/{run_id}")
    async def endpoint(request: Request):
        if request.headers.get("last-event-id"):
            return {"replay": True}
        adapter = await AGUIAdapter.from_request(
            request, agent=Agent(FunctionModel(forbidden))
        )
        events = [e async for e in adapter.run_stream()]
        for e in events:
            projection._fold(e)
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

    def send(actions, run, headers=None):
        return client.post(
            f"/v1/rooms/{scope.room_id}/agui/{scope.thread_id}/{run}",
            headers=headers or {},
            json={
                "threadId": scope.thread_id,
                "runId": run,
                "state": {},
                "messages": [],
                "tools": [],
                "context": [],
                "forwardedProps": {
                    "a2uiAction": {
                        "submissionId": run,
                        "activityMessageId": record["activityMessageId"],
                        "userAction": {
                            "name": "workbench.program.layout",
                            "surfaceId": record["surfaceId"],
                            "sourceComponentId": "root",
                            "context": {
                                "invocationId": "gesture-one",
                                "actions": actions,
                            },
                        },
                    }
                },
            },
        )

    actions = [
        {
            "op": "open",
            "window_id": "result_window",
            "title": "Result",
            "kind": "text",
            "content": "10",
        }
    ]
    response = send(actions, "open")
    assert response.status_code == 200, response.text
    assert response.json()[0]["type"] == "RUN_STARTED"
    before = copy.deepcopy(projection.layout)
    assert send(actions, "replay", {"last-event-id": "1"}).json() == {"replay": True}
    assert projection.layout == before
    # Reload folds saved activities only; no handler/model is called.
    reloaded = RunWorkbenchProjection(
        scope,
        [
            *projection.test_history,
            *[
                ActivitySnapshotEvent.model_validate(e)
                for e in response.json()
                if e["type"] == "ACTIVITY_SNAPSHOT"
            ],
        ],
    )
    assert reloaded.layout == before
    assert len([n for n in reloaded.layout["nodes"] if n["id"] == "result_window"]) == 1
    assert "open" in reloaded.submission_ids
    assert (
        send([{"op": "close", "window_id": "result_window"}], "close").status_code
        == 200
    )
    assert send(actions * 9, "limit").status_code == 422
    assert not model_calls
