"""Validate canvas submissions and project accepted data into model input.

No reservation, Python execution, or request-byte mutation happens here.
"""
from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping
from threading import Lock

from ag_ui.core import Message
from pydantic import TypeAdapter

from .workbench_schemas import ActionEnvelope as CanvasSubmission
from .workbench_schemas import IntakeSubmit, RunResult

WORKBENCH_INTAKE_TOOL_NAME = "workbench_intake"


def validate_submission(payload: object, projection) -> CanvasSubmission:
    """Bind values to a server-published activity, never a client registration.

    Content tools mint fresh activity identities; layout moves retain them.
    The source identity therefore follows the published content version.
    """
    submission = CanvasSubmission.model_validate(payload)
    action = submission.userAction
    record = projection.content.get(submission.activityMessageId)
    if record is None or record["surfaceId"] != action.surfaceId:
        raise ValueError("action surface was not published in this thread")
    if record["component"] == "PlaceForm" and action.name == "submit_intake":
        if action.sourceComponentId not in (None, "submit"):
            raise ValueError("action source component does not match intake Submit")
        context = IntakeSubmit.model_validate(action.context)
    elif record["component"] == "PythonRepl" and action.name == "workbench.program.run_result":
        if action.sourceComponentId not in (None, "root"):
            raise ValueError("action source component does not match PythonRepl")
        context = RunResult.model_validate(action.context)
    else:
        raise ValueError("action name does not match its published component")
    submission.userAction.context = context.model_dump(mode="json")
    return submission


def synthetic_intake_messages(envelope: Mapping[str, object]) -> list[dict[str, object]]:
    """One deterministic, non-callable intake pair, with untrusted values."""
    submission_id = envelope["submissionId"]
    context = envelope["userAction"]["context"]
    digest = hashlib.sha256(submission_id.encode()).hexdigest()[:24]
    call_id = f"workbench-intake-{digest}"
    result = {
        "kind": "untrusted_user_submitted_data",
        "actionSchemaVersion": "intake.submit@1",
        "submissionId": submission_id,
        "context": context,
    }
    return [
        {"id": f"{call_id}-assistant", "role": "assistant", "toolCalls": [{
            "id": call_id, "type": "function", "function": {
                "name": WORKBENCH_INTAKE_TOOL_NAME,
                "arguments": json.dumps({"submissionId": submission_id}, separators=(",", ":")),
            },
        }]},
        {"id": f"{call_id}-result", "role": "tool", "toolCallId": call_id,
         "content": json.dumps(result, sort_keys=True, separators=(",", ":"), ensure_ascii=False)},
    ]


def submission_messages(submission: CanvasSubmission) -> list[Message]:
    envelope = submission.model_dump(mode="json", exclude_none=True)
    if submission.userAction.name == "submit_intake":
        wire = synthetic_intake_messages(envelope)
    else:
        wire = [{
            "id": "workbench-result-" + hashlib.sha256(submission.submissionId.encode()).hexdigest()[:24],
            "role": "user",
            "content": json.dumps({"kind": "untrusted_user_submitted_data", **envelope}, ensure_ascii=False),
        }]
    return TypeAdapter(list[Message]).validate_python(wire)


class SubmissionDedup:
    """Router-local race guard; stored run inputs also suppress accepted IDs.

    Keys include authenticated actor/server/room/thread and submission ID.
    At capacity we fail closed instead of evicting accepted IDs. This is a
    single-worker preview guard, not a distributed exactly-once promise.
    """
    def __init__(self, capacity=4096):
        self._keys = set()
        self._lock = Lock()
        self.capacity = capacity

    def claim(self, scope, submission_id, persisted_ids):
        key = (*scope.key(), submission_id)
        with self._lock:
            if submission_id in persisted_ids or key in self._keys:
                raise ValueError("workbench submission was already accepted")
            if len(self._keys) >= self.capacity:
                raise ValueError("workbench submission capacity reached")
            self._keys.add(key)
