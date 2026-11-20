"""Validation, reservation and the sole workbench action reader."""

from __future__ import annotations

import hashlib
import json
from typing import Mapping, Protocol

from pydantic import ValidationError

from .workbench_repository import PublicationConflict, SQLiteWorkbenchRepository, WorkbenchScope
from .workbench_schemas import ActionEnvelope, IntakeSubmit, ProgramExport, RunResult
from .workbench_tracing import LogfireTraceSink


class TraceSink(Protocol):
    def emit(self, event: Mapping[str, object]) -> None: ...


WORKBENCH_INTAKE_TOOL_NAME = "workbench_intake"


def synthetic_intake_messages(envelope: Mapping[str, object]) -> list[dict[str, object]]:
    """Build a stable AG-UI assistant tool-call and untrusted tool-result pair."""
    submission_id = envelope.get("submissionId")
    context = envelope.get("userAction")
    if not isinstance(submission_id, str) or not isinstance(context, Mapping):
        raise ValueError("validated intake reservation is malformed")
    digest = hashlib.sha256(submission_id.encode("utf-8")).hexdigest()[:24]
    call_id = f"workbench-intake-{digest}"
    result = {
        "kind": "untrusted_user_submitted_data",
        "actionSchemaVersion": "intake.submit@1",
        "submissionId": submission_id,
        "context": dict(context),
    }
    return [
        {
            "id": f"{call_id}-assistant",
            "role": "assistant",
            "toolCalls": [{
                "id": call_id,
                "type": "function",
                "function": {"name": WORKBENCH_INTAKE_TOOL_NAME, "arguments": json.dumps({"submissionId": submission_id}, separators=(",", ":"))},
            }],
        },
        {
            "id": f"{call_id}-result",
            "role": "tool",
            "toolCallId": call_id,
            "content": json.dumps(result, sort_keys=True, separators=(",", ":"), ensure_ascii=False),
        },
    ]


class WorkbenchActionService:
    def __init__(self, repository: SQLiteWorkbenchRepository, trace_sink: TraceSink | None = None):
        self.repository = repository
        self.trace_sink = trace_sink or LogfireTraceSink()

    def accept(self, scope: WorkbenchScope, payload: Mapping[str, object]) -> dict[str, object]:
        encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
        if len(encoded) > 16_384:
            raise ValueError("action envelope exceeds 16 KiB")
        context_models = {
            "intake.submit@1": IntakeSubmit,
            "workbench.program.export_chart@1": ProgramExport,
            "workbench.program.run_result@1": RunResult,
        }
        schema_version = payload.get("actionSchemaVersion")
        if not isinstance(schema_version, str):
            raise ValueError("unsupported action schema")
        context_model = context_models.get(schema_version)
        if context_model is None:
            raise ValueError("unsupported action schema")
        typed_context = context_model.model_validate(
            payload.get("userAction"),
            context={"pinned_engine_manifest": {"monty-1.3.0"}},
        )
        normalized = dict(payload)
        normalized["userAction"] = typed_context.model_dump(mode="json")
        action = ActionEnvelope.model_validate(normalized, context={"pinned_engine_manifest": {"monty-1.3.0"}})
        digest = hashlib.sha256(encoded).hexdigest()
        duplicate = self.repository.existing_action(scope, action.submissionId, digest)
        if duplicate is not None:
            if isinstance(action.userAction, RunResult):
                self.repository.emit_trace_once(scope, action.userAction.invocationId, self.trace_sink)
            return duplicate
        current = self.repository.load_snapshot(scope)
        if current["layout"] is None:
            raise PublicationConflict("stale workbench surface revision")
        registered = {str(record.get("activityMessageId")): record for record in current["content"]}
        record = registered.get(action.activityMessageId)
        if record is None:
            raise ValueError("action surface is not registered in this thread")
        surface_revision = record.get("surfaceRevision", current["revision"])
        if surface_revision != action.surfaceRevision:
            raise PublicationConflict("stale workbench surface revision")
        component = record.get("component")
        expected_components = {
            "intake.submit@1": {"PlaceForm", "IntakeForm"},
            "workbench.program.export_chart@1": {"PythonRepl", "Program"},
            "workbench.program.run_result@1": {"PythonRepl", "Program"},
        }[action.actionSchemaVersion]
        if component not in expected_components:
            raise ValueError("action source component is not registered for this action")
        receipt_details: dict[str, object] = {}
        if isinstance(action.userAction, RunResult):
            invocation_data = action.userAction.model_dump(mode="json")
            invocation_identity = {
                "result": invocation_data,
                "activityMessageId": action.activityMessageId,
                "surfaceId": str(record.get("surfaceId")),
            }
            receipt_details = {
                "invocationId": action.userAction.invocationId,
                "invocationDigest": hashlib.sha256(json.dumps(invocation_identity, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
                "trace": {
                    "python.side": "client",
                    "python.engine": action.userAction.engine,
                    "room": scope.room_id,
                    "thread": scope.thread_id,
                    "surface": str(record.get("surfaceId")),
                    "chain_id": action.userAction.chainId,
                    "invocation_id": action.userAction.invocationId,
                },
            }
        receipt = self.repository.reserve_action(
            scope, action.submissionId, digest, action.model_dump(mode="json"),
            expected_revision=int(current["revision"]),
            activity_message_id=action.activityMessageId,
            receipt_details=receipt_details,
        )
        if isinstance(action.userAction, RunResult):
            self.repository.emit_trace_once(scope, action.userAction.invocationId, self.trace_sink)
        return receipt

    def consume_dispatch(self, scope: WorkbenchScope, payload: Mapping[str, object]) -> dict[str, object] | None:
        """Read one reserved action from forwardedProps; reconnects must bypass this."""
        wrapper = payload.get("forwardedProps")
        if not isinstance(wrapper, dict):
            return None
        envelope = wrapper.get("a2uiAction")
        if not isinstance(envelope, dict):
            return None
        if envelope.get("actionSchemaVersion") != "intake.submit@1":
            return None
        # The package owns reading this wire shape. Never consult or install
        # pydantic-ai's process-global private adapter patch.
        encoded = json.dumps(envelope, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
        digest = hashlib.sha256(encoded).hexdigest()
        consumed = self.repository.consume_action(scope, str(envelope.get("submissionId", "")), digest)
        if consumed is None:
            return None
        return ActionEnvelope.model_validate(consumed, context={"pinned_engine_manifest": {"monty-1.3.0"}}).model_dump(mode="json")

