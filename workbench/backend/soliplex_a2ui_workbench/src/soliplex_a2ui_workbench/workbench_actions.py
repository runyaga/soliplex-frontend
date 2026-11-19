"""Validation, reservation and the sole workbench action reader."""

from __future__ import annotations

import hashlib
import json
from typing import Mapping

from pydantic import ValidationError

from .workbench_repository import PublicationConflict, SQLiteWorkbenchRepository, WorkbenchScope
from .workbench_schemas import ActionEnvelope, RunResult


class WorkbenchActionService:
    def __init__(self, repository: SQLiteWorkbenchRepository):
        self.repository = repository

    def accept(self, scope: WorkbenchScope, payload: Mapping[str, object]) -> dict[str, object]:
        encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
        if len(encoded) > 16_384:
            raise ValueError("action envelope exceeds 16 KiB")
        action = ActionEnvelope.model_validate(payload, context={"pinned_engine_manifest": {"monty-1.3.0"}})
        if action.actionSchemaVersion not in {"intake-submit@1", "program-export@1", "python-run-result@1"}:
            raise ValueError("unsupported action schema")
        digest = hashlib.sha256(encoded).hexdigest()
        duplicate = self.repository.existing_action(scope, action.submissionId, digest)
        if duplicate is not None:
            return duplicate
        current = self.repository.load_snapshot(scope)
        if current["layout"] is None:
            raise ValueError("stale workbench surface revision")
        registered = {str(record.get("activityMessageId")): record for record in current["content"]}
        record = registered.get(action.activityMessageId)
        if record is None:
            raise ValueError("action surface is not registered in this thread")
        surface_revision = record.get("surfaceRevision", current["revision"])
        if surface_revision != action.surfaceRevision:
            raise ValueError("stale workbench surface revision")
        surface_revision = record.get("surfaceRevision")
        if surface_revision is not None and surface_revision != action.surfaceRevision:
            raise ValueError("stale action surface revision")
        component = record.get("component")
        expected_components = {
            "intake-submit@1": {"PlaceForm", "IntakeForm"},
            "program-export@1": {"PythonRepl", "Program"},
            "python-run-result@1": {"PythonRepl", "Program"},
        }[action.actionSchemaVersion]
        if component not in expected_components:
            raise ValueError("action source component is not registered for this action")
        receipt_details: dict[str, object] = {}
        if isinstance(action.userAction, RunResult):
            invocation_data = action.userAction.model_dump(mode="json")
            receipt_details = {
                "invocationId": action.userAction.invocationId,
                "invocationDigest": hashlib.sha256(json.dumps(invocation_data, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
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
        return self.repository.reserve_action(
            scope, action.submissionId, digest, action.model_dump(mode="json"),
            expected_revision=int(current["revision"]),
            activity_message_id=action.activityMessageId,
            receipt_details=receipt_details,
        )

    def consume_dispatch(self, scope: WorkbenchScope, payload: Mapping[str, object]) -> dict[str, object] | None:
        """Read one reserved action from forwardedProps; reconnects must bypass this."""
        wrapper = payload.get("forwardedProps")
        if not isinstance(wrapper, dict):
            return None
        envelope = wrapper.get("a2uiAction")
        if not isinstance(envelope, dict):
            return None
        # The package owns reading this wire shape. Never consult or install
        # pydantic-ai's process-global private adapter patch.
        encoded = json.dumps(envelope, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
        digest = hashlib.sha256(encoded).hexdigest()
        consumed = self.repository.consume_action(scope, str(envelope.get("submissionId", "")), digest)
        if consumed is None:
            return None
        return ActionEnvelope.model_validate(consumed, context={"pinned_engine_manifest": {"monty-1.3.0"}}).model_dump(mode="json")

