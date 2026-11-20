"""Canvas actions use real published surfaces, the AGUI adapter and a model spy.

Replaces reservation/consume/trace-outbox tests: actions have no preflight or
request-byte rewrite now. Repository persistence tests remain in their suite.
"""

import asyncio
import copy
import inspect
import json
from types import SimpleNamespace

import pytest
from ag_ui.core import RunAgentInput
from fastapi import APIRouter, FastAPI, Request
from fastapi.testclient import TestClient
from pydantic_ai import Agent
from pydantic_ai.messages import (
    ModelResponse,
    TextPart,
    ToolCallPart,
    ToolReturnPart,
    UserPromptPart,
)
from pydantic_ai.models.function import FunctionModel
from pydantic_ai.ui.ag_ui import AGUIAdapter

from soliplex_a2ui_workbench.workbench_actions import (
    CanvasSubmission,
    SubmissionDedup,
    submission_messages,
)
from soliplex_a2ui_workbench.workbench_projection import (
    RunWorkbenchProjection,
    projection_from_thread,
    restore_submission_history,
)
from soliplex_a2ui_workbench.workbench_routes import (
    build_router,
    create_guarded_agui_router,
)
from test_workbench_agent_tools import publication_fixture


@pytest.fixture
def boundary(tmp_path):
    context, form, chart, window, program = asyncio.run(publication_fixture())
    scope = context.deps._workbench_context.scope
    projection = RunWorkbenchProjection(
        scope,
        [
            event
            for result in [form, chart, window, program]
            for event in result.metadata
        ],
    )
    published_form = next(
        record
        for record in projection.content.values()
        if record["component"] == "PlaceForm"
    )
    published_program = next(
        record
        for record in projection.content.values()
        if record["component"] == "PythonRepl"
    )
    captured = []
    wires = []
    stored = []
    upstream = APIRouter()

    @upstream.post("/v1/rooms/{room_id}/agui/{thread_id}/{run_id}")
    async def downstream(request: Request):
        raw = await request.body()
        # Like stock Soliplex, reconnect does not invoke the adapter or model.
        if request.headers.get("last-event-id"):
            return {"replayed": True}

        def capture(messages, info):
            captured.append(messages)
            assert "workbench_intake" not in [tool.name for tool in info.function_tools]
            return ModelResponse(parts=[TextPart("ok")])

        agent = Agent(FunctionModel(capture))
        adapter = await AGUIAdapter.from_request(request, agent=agent)
        assert await request.body() == raw
        await agent.run(message_history=adapter.messages)
        stored.append(adapter.run_input)
        if request.path_params["room_id"] == scope.room_id:
            restore_submission_history(projection, adapter.run_input)
        wires.append(adapter.run_input)
        return adapter.run_input.model_dump(
            mode="json", by_alias=True, exclude_none=True
        )

    app = FastAPI()

    @app.middleware("http")
    async def installation_for_results(request, call_next):
        request.state.workbench_installation = SimpleNamespace(
            sandbox_workdirs_path=tmp_path / "workdirs"
        )
        return await call_next(request)

    before = inspect.getattr_static(AGUIAdapter, "messages")
    app.include_router(
        create_guarded_agui_router(
            upstream,
            scope_provider=scope,
            projection_provider=lambda request, checked_scope: projection,
            workbench_rooms={scope.room_id},
        )
    )
    assert inspect.getattr_static(AGUIAdapter, "messages") is before
    return SimpleNamespace(
        client=TestClient(app),
        scope=scope,
        projection=projection,
        form=published_form,
        program=published_program,
        captured=captured,
        wires=wires,
        stored=stored,
        workdirs=tmp_path / "workdirs",
    )


def envelope(record, submission="submit-1", *, program=False):
    return {
        "submissionId": submission,
        "activityMessageId": record["activityMessageId"],
        "userAction": {
            "name": "workbench.program.run_result" if program else "submit_intake",
            "surfaceId": record["surfaceId"],
            "sourceComponentId": "root" if program else "submit",
            "timestamp": "2026-11-19T00:00:00Z",
            "context": {
                "side": "client",
                "engine": "monty-1.3.0",
                "invocationId": "inv-1",
                "chainId": "chain-1",
                "outcome": "success",
                "output": "Hello from REPL",
            }
            if program
            else {
                "question": "CURRENT_FIELD_VALUE",
                "districts": ["north"],
                "acknowledged": True,
            },
        },
    }


def send(boundary, action=None, run="run-1", **changes):
    payload = {
        "threadId": boundary.scope.thread_id,
        "runId": run,
        "state": {},
        "messages": [{"id": "anchor", "role": "user", "content": "Old chat"}],
        "tools": [],
        "context": [],
        "forwardedProps": {} if action is None else {"a2uiAction": action},
    }
    payload.update(changes)
    return boundary.client.post(
        f"/v1/rooms/{boundary.scope.room_id}/agui/{boundary.scope.thread_id}/{run}",
        json=payload,
    )


@pytest.mark.parametrize("forwarded_key", ["forwardedProps", "forwarded_props"])
def test_published_intake_is_exactly_one_untrusted_pair_in_real_model_input(
    boundary, forwarded_key
):
    action = envelope(boundary.form)
    # Use only one spelling, as a normal client does.
    payload = {
        "threadId": boundary.scope.thread_id,
        "runId": "run-1",
        "state": {},
        "messages": [],
        "tools": [],
        "context": [],
        forwarded_key: {"a2uiAction": action},
    }
    result = boundary.client.post(
        f"/v1/rooms/{boundary.scope.room_id}/agui/{boundary.scope.thread_id}/run-1",
        json=payload,
    )
    assert result.status_code == 200, result.text
    messages = boundary.captured[0]
    calls = [
        part
        for message in messages
        for part in message.parts
        if isinstance(part, ToolCallPart)
    ]
    returns = [
        part
        for message in messages
        for part in message.parts
        if isinstance(part, ToolReturnPart)
    ]
    assert len(calls) == len(returns) == 1
    assert calls[0].tool_name == returns[0].tool_name == "workbench_intake"
    assert calls[0].tool_call_id == returns[0].tool_call_id
    assert "untrusted_user_submitted_data" in str(returns[0].content)
    assert str(returns[0].content).count("CURRENT_FIELD_VALUE") == 1
    assert all(
        "CURRENT_FIELD_VALUE" not in str(part.content)
        for message in messages
        for part in message.parts
        if isinstance(part, UserPromptPart)
    )
    assert [message["role"] for message in result.json()["messages"]] == [
        "assistant",
        "tool",
    ]
    duplicate = send(boundary, action, run="duplicate")
    assert duplicate.status_code == 409
    assert len(boundary.captured) == 1


@pytest.mark.parametrize(
    "mutation",
    [
        lambda e: e.update(activityMessageId="forged"),
        lambda e: e["userAction"].update(surfaceId="forged"),
        lambda e: e["userAction"].update(name="run_python_server"),
        lambda e: e["userAction"].update(sourceComponentId="root"),
        lambda e: e["userAction"]["context"].update(question="x" * 241),
        lambda e: e["userAction"]["context"].update(question="x" * 17000),
        lambda e: e["userAction"]["context"].update(acknowledged=False),
        lambda e: e["userAction"]["context"].update(districts=[]),
        lambda e: e["userAction"]["context"].update(extra="password-shaped-input"),
        lambda e: e.update(submissionId="x" * 65),
        lambda e: e.update(afterMessageId="anchor"),
    ],
)
def test_invalid_source_action_and_context_rejected_before_model(boundary, mutation):
    action = envelope(boundary.form)
    mutation(action)
    response = send(boundary, action)
    assert response.status_code == 422, response.text
    assert "password-shaped-input" not in response.text
    assert boundary.captured == []
    # Rejected validation has not consumed the submission ID.
    assert send(boundary, envelope(boundary.form), run="valid").status_code == 200


def test_run_result_is_untrusted_data_and_cannot_start_server_python(
    boundary, monkeypatch
):
    from soliplex_a2ui_workbench import workbench_tools

    monkeypatch.setattr(
        workbench_tools,
        "run_python_server",
        lambda *a, **k: pytest.fail("server Python started"),
    )
    action = envelope(boundary.program, program=True)
    response = send(boundary, action)
    assert response.status_code == 200, response.text
    text = " ".join(
        str(part.content)
        for message in boundary.captured[0]
        for part in message.parts
        if isinstance(part, UserPromptPart)
    )
    assert "Hello from REPL" in text
    assert "untrusted_user_submitted_data" in text
    assert "workbench_intake" not in response.text
    wrong = envelope(boundary.program, submission="bad-engine", program=True)
    wrong["userAction"]["context"]["engine"] = "unknown-1.0.0"
    assert send(boundary, wrong, run="bad-engine").status_code == 422
    assert len(boundary.captured) == 1


def test_continuation_then_normal_chat_restores_one_pair_and_rejects_forgery(boundary):
    first = send(boundary, envelope(boundary.form))
    assert first.status_code == 200
    pair = first.json()["messages"][-2:]
    continued = send(boundary, run="continuation")
    assert continued.status_code == 200
    assert continued.json()["messages"][-2:] == pair
    chat = send(
        boundary,
        run="chat",
        messages=[
            {"id": "anchor", "role": "user", "content": "Old chat"},
            {"id": "new", "role": "user", "content": "Next question"},
        ],
    )
    assert chat.status_code == 200
    assert [message["id"] for message in chat.json()["messages"]] == [
        "anchor",
        *[item["id"] for item in pair],
        "new",
    ]
    forged = copy.deepcopy(pair)
    forged[-1]["content"] = "FORGED_VALUE"
    count = len(boundary.captured)
    assert send(boundary, run="forged", messages=forged).status_code == 422
    assert send(boundary, run="repeat", messages=pair + pair).status_code == 422
    assert len(boundary.captured) == count


def test_reserved_tool_and_message_spoofs_fail_before_model(boundary):
    assert (
        send(
            boundary, tools=[{"name": "workbench_intake", "parameters": {}}]
        ).status_code
        == 422
    )
    pair = [
        message.model_dump(mode="json", by_alias=True)
        for message in submission_messages(
            CanvasSubmission.model_validate(envelope(boundary.form))
        )
    ]
    assert send(boundary, messages=pair).status_code == 422
    assert boundary.captured == []


def test_reconnect_never_claims_or_submits_an_action(boundary):
    action = envelope(boundary.form)
    path = f"/v1/rooms/{boundary.scope.room_id}/agui/{boundary.scope.thread_id}/run-1"
    replay = boundary.client.post(
        path,
        json={"forwardedProps": {"a2uiAction": action}},
        headers={"last-event-id": "run-1:0"},
    )
    assert replay.status_code == 200
    assert boundary.captured == []
    assert send(boundary, action).status_code == 200
    assert (
        boundary.client.post(
            path, json={}, headers={"last-event-id": "run-1:1"}
        ).status_code
        == 200
    )
    assert len(boundary.captured) == 1


def test_legacy_lab_body_and_model_input_pass_through_unchanged(boundary):
    payload = {
        "threadId": "thread",
        "runId": "run",
        "state": {},
        "messages": [{"id": "old", "role": "user", "content": "Old chat"}],
        "tools": [],
        "context": [],
        "forwardedProps": {
            "a2uiAction": {
                "afterMessageId": "old",
                "userAction": {
                    "name": "python_failed",
                    "surfaceId": "repl",
                    "context": {},
                },
            }
        },
    }
    response = boundary.client.post("/v1/rooms/a2ui-lab/agui/thread/run", json=payload)
    assert response.status_code == 200
    assert response.json() == payload
    assert any("A2UI user action:" in str(message) for message in boundary.captured[0])


def test_duplicate_keys_reject_before_adapter_and_model(boundary):
    response = boundary.client.post(
        f"/v1/rooms/{boundary.scope.room_id}/agui/{boundary.scope.thread_id}/run",
        content=b'{"threadId":"thread","runId":"run","state":{"x":1,"x":2}}',
        headers={"content-type": "application/json"},
    )
    assert response.status_code == 400
    assert boundary.captured == []


def test_dedup_is_scope_bound_and_fails_closed_at_capacity(boundary):
    dedup = SubmissionDedup(capacity=1)
    dedup.claim(boundary.scope, "one", set())
    with pytest.raises(ValueError, match="already accepted"):
        dedup.claim(boundary.scope, "one", set())
    with pytest.raises(ValueError, match="capacity"):
        dedup.claim(boundary.scope, "two", set())
    with pytest.raises(ValueError, match="already accepted"):
        SubmissionDedup().claim(boundary.scope, "persisted", {"persisted"})


def test_preflight_route_removed():
    assert not any(
        route.path.endswith("/workbench/actions") for route in build_router().routes
    )


def test_persisted_run_input_restores_intake_and_dedup_after_restart():
    from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
    from soliplex.agui.persistence import ThreadStorage
    from soliplex.agui.schema import Base

    async def exercise():
        engine = create_async_engine("sqlite+aiosqlite:///:memory:")
        try:
            async with engine.begin() as connection:
                await connection.run_sync(Base.metadata.create_all)
            context, form, chart, window, program = await publication_fixture()
            scope = context.deps._workbench_context.scope
            projection = RunWorkbenchProjection(scope, form.metadata)
            record = next(iter(projection.content.values()))
            action = envelope(record)
            pair = submission_messages(CanvasSubmission.model_validate(action))
            async with AsyncSession(engine, expire_on_commit=False) as session:
                storage = ThreadStorage(session)
                thread = await storage.new_thread(
                    user_name=scope.actor_id,
                    email="@".join(("alice", "example.test")),
                    room_id=scope.room_id,
                )
                thread.thread_id = scope.thread_id
                await session.flush()
                run = (await thread.list_runs())[0]
                for event in form.metadata:
                    await storage.save_single_event(
                        user_name=scope.actor_id,
                        room_id=scope.room_id,
                        thread_id=scope.thread_id,
                        run_id=run.run_id,
                        event=event,
                    )
                accepted = RunAgentInput(
                    thread_id=scope.thread_id,
                    run_id=run.run_id,
                    state={},
                    messages=[
                        {"id": "anchor", "role": "user", "content": "Old chat"},
                        *pair,
                    ],
                    tools=[],
                    context=[],
                    forwarded_props={"a2uiAction": action},
                )
                await storage.add_run_input(
                    user_name=scope.actor_id,
                    room_id=scope.room_id,
                    thread_id=scope.thread_id,
                    run_id=run.run_id,
                    run_input=accepted,
                )
                await session.commit()
            fresh = await projection_from_thread(
                SimpleNamespace(thread_persistence_engine=engine), scope
            )
            assert fresh.submission_ids == {action["submissionId"]}
            assert fresh.submission_history == [("anchor", pair)]
            assert record["activityMessageId"] in fresh.content
            with pytest.raises(ValueError, match="already accepted"):
                SubmissionDedup().claim(
                    scope, action["submissionId"], fresh.submission_ids
                )
            foreign_scope = type(scope)(
                "mallory", scope.server_id, scope.room_id, scope.thread_id
            )
            with pytest.raises(Exception):
                await projection_from_thread(
                    SimpleNamespace(thread_persistence_engine=engine), foreign_scope
                )
        finally:
            await engine.dispose()

    asyncio.run(exercise())


def test_stock_router_hook_preserves_signature_auth_dependencies_and_global_adapter():
    from soliplex.views.agui import router as stock

    original = next(
        route
        for route in stock.routes
        if "POST" in route.methods and route.path.endswith("/{run_id}")
    )
    original_adapter = original.endpoint.__globals__["ai_ag_ui"].AGUIAdapter
    guarded = create_guarded_agui_router(stock, workbench_rooms={"workbench"})

    def flattened(router):
        for route in router.routes:
            nested = getattr(route, "original_router", None)
            if nested is not None:
                yield from flattened(nested)
            else:
                yield route

    hooked = next(
        route
        for route in flattened(guarded)
        if "POST" in getattr(route, "methods", ()) and route.path.endswith("/{run_id}")
    )
    assert inspect.signature(hooked.endpoint) == inspect.signature(original.endpoint)
    assert original.endpoint.__globals__["ai_ag_ui"].AGUIAdapter is original_adapter
    assert hooked.endpoint.__globals__["ai_ag_ui"].AGUIAdapter is not original_adapter
    assert original.endpoint.__code__ is hooked.endpoint.__code__
    assert set(inspect.signature(hooked.endpoint).parameters) >= {
        "the_room_authz",
        "the_user_claims",
    }


@pytest.mark.parametrize("user_action", [None, [], "invalid"])
def test_malformed_action_shape_is_rejected_before_inference(boundary, user_action):
    response = send(
        boundary,
        {
            "submissionId": "shape",
            "activityMessageId": boundary.program["activityMessageId"],
            "userAction": user_action,
        },
    )
    assert response.status_code == 422
    assert not boundary.captured


@pytest.mark.parametrize(
    "changes",
    [
        {"name": None},
        {"color": ["Green"]},
        {"age": 121},
        {"extra": "x"},
        {"subscribe": "true"},
        {"notes": 9},
    ],
)
def test_invalid_custom_forms_never_reach_inference(boundary, monkeypatch, changes):
    from test_workbench_forms import published, envelope as custom_envelope, VALUES

    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")
    _, projection, record = asyncio.run(published())
    boundary.projection.content.update(projection.content)
    response = send(boundary, custom_envelope(record, {**VALUES, **changes}))
    assert response.status_code == 422
    assert response.json()["detail"].startswith("Form ")
    assert not boundary.captured
    assert not boundary.workdirs.exists()


def test_custom_form_action_turn_persists_and_restores_canonical_pair(
    boundary, monkeypatch
):
    from test_workbench_forms import published, envelope as custom_envelope

    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")
    _, projection, record = asyncio.run(published())
    boundary.projection.content.update(projection.content)
    response = send(boundary, custom_envelope(record))
    assert response.status_code == 200
    pair = response.json()["messages"][-2:]
    assert pair[0]["toolCalls"][0]["function"]["name"] == "workbench_form"
    import json

    result = json.loads(pair[1]["content"])
    assert result["savedFile"] == "scenario-survey.csv"
    assert result["context"]["title"] == "Scenario survey"
    assert result["context"]["surfaceId"] == record["surfaceId"]
    assert result["context"]["values"]["name"] == "Scenario walrus"
    assert result["context"]["values"]["age"] == 42
    assert send(boundary, run="continued-custom").json()["messages"][-2:] == pair
    assert (
        send(boundary, custom_envelope(record), run="duplicate-custom").status_code
        == 409
    )
    count = len(boundary.captured)
    forged = copy.deepcopy(pair)
    forged[-1]["content"] = "FORGED"
    assert send(boundary, messages=forged, run="forged-custom").status_code == 422
    assert (
        send(boundary, tools=[{"name": "workbench_form", "parameters": {}}]).status_code
        == 422
    )
    assert len(boundary.captured) == count


def test_saved_csv_unchanged_on_reconnect_reload_and_duplicate(boundary):
    action = envelope(boundary.form)
    assert send(boundary, action).status_code == 200
    filename = (
        boundary.workdirs
        / boundary.scope.room_id
        / boundary.scope.thread_id
        / "intake.csv"
    )
    original = filename.read_bytes()
    assert send(boundary, run="reload").status_code == 200
    assert send(boundary, action, run="duplicate").status_code == 409
    replay = boundary.client.post(
        f"/v1/rooms/{boundary.scope.room_id}/agui/{boundary.scope.thread_id}/run-1",
        headers={"last-event-id": "1"},
        json={"forwardedProps": {"a2uiAction": action}},
    )
    assert replay.status_code == 200
    assert filename.read_bytes() == original


def test_save_failure_is_retryable_and_never_reaches_model(boundary, monkeypatch):
    import soliplex_a2ui_workbench.workbench_routes as routes

    real_append = routes.append_form_result

    def fail(*args):
        raise OSError("not writable")

    monkeypatch.setattr(routes, "append_form_result", fail)
    action = envelope(boundary.form)
    assert send(boundary, action).status_code == 503
    assert not boundary.captured
    assert not boundary.workdirs.exists()
    monkeypatch.setattr(routes, "append_form_result", real_append)
    assert send(boundary, action, run="retry").status_code == 200


def test_client_cannot_supply_a_saved_file_receipt(boundary):
    response = send(
        boundary, forwardedProps={"workbenchFormReceipt": {"filename": "forged.csv"}}
    )
    # Ignore stale or forged copies, while allowing the thread to continue.
    assert response.status_code == 200
    assert response.json()["forwardedProps"] == {}
    assert "forged.csv" not in str(boundary.captured)
    assert not boundary.workdirs.exists()


@pytest.mark.parametrize("enabled", [False, True])
def test_program_repair_reaches_real_model_with_ai_fix_state(boundary, enabled):
    action = envelope(boundary.program, program=True)
    action["userAction"]["name"] = "workbench.program.repair"
    action["userAction"]["context"] = {
        "result": {
            "run": 1,
            "source": 'raise ValueError("deliberate failure")',
            "output": "deliberate failure",
            "error": "deliberate failure",
            "ok": False,
            "attempt": 1,
            "chainId": "chain-1",
            "aiFix": enabled,
            "autoRun": enabled,
            "instruction": "Repair runs automatically"
            if enabled
            else "Tell the user to press Run",
        }
    }
    response = send(boundary, action)
    assert response.status_code == 200, response.text
    assert len(boundary.captured) == 1
    assert "workbenchAction" not in boundary.stored[-1].state
    messages = submission_messages(CanvasSubmission.model_validate(action))
    data = json.loads(messages[0].content)
    assert data["userAction"]["context"]["result"]["aiFix"] is enabled
    model_text = str(boundary.captured[0])
    assert action["userAction"]["context"]["result"]["instruction"] in model_text


def test_program_repair_rejects_unregistered_surface_and_unbounded_context(boundary):
    action = envelope(boundary.program, program=True)
    action["userAction"]["name"] = "workbench.program.repair"
    action["userAction"]["context"] = {
        "result": {
            "run": 1,
            "source": "print(1)",
            "output": "failure",
            "error": "failure",
            "ok": False,
            "attempt": 1,
            "chainId": "chain-1",
            "aiFix": True,
            "autoRun": True,
            "instruction": "Repair runs automatically",
        }
    }
    wrong = copy.deepcopy(action)
    wrong["userAction"]["surfaceId"] = "unregistered"
    assert send(boundary, wrong).status_code == 422
    wrong = copy.deepcopy(action)
    wrong["userAction"]["context"]["result"]["error"] = "x" * 2001
    assert send(boundary, wrong).status_code == 422
    assert boundary.captured == []
