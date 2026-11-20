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

from .workbench_forms import validate_form_values
from .workbench_schemas import ActionEnvelope as CanvasSubmission
from .workbench_schemas import IntakeSubmit, ProgramRepair, RunResult

WORKBENCH_INTAKE_TOOL_NAME = "workbench_intake"
WORKBENCH_FORM_TOOL_NAME = "workbench_form"


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
    if record["component"] == "PlaceForm" and "fields" in record and action.name == "submit_form":
        if action.sourceComponentId not in (None, "submit"):
            raise ValueError("action source component does not match form Submit")
        action.context = validate_form_values(action.context, record)
        # Added authoritative metadata must still fit the persisted envelope;
        # otherwise history could not restore an accepted submission.
        if len(json.dumps(submission.model_dump(mode="json"), separators=(",", ":"), ensure_ascii=False).encode("utf-8")) > 16_384:
            raise ValueError("Form submission exceeds 16 KiB; shorten text fields")
        return submission
    if record["component"] == "PlaceForm" and record.get("template") == "intake" and action.name == "submit_intake":
        if action.sourceComponentId not in (None, "submit"):
            raise ValueError("action source component does not match intake Submit")
        context = IntakeSubmit.model_validate(action.context)
    elif record["component"] == "PythonRepl" and action.name == "workbench.program.repair":
        if action.sourceComponentId not in (None, "root"):
            raise ValueError("action source component does not match PythonRepl")
        context = ProgramRepair.model_validate(action.context)
    elif record["component"] == "PythonRepl" and action.name == "workbench.program.run_result":
        if action.sourceComponentId not in (None, "root"):
            raise ValueError("action source component does not match PythonRepl")
        context = RunResult.model_validate(action.context)
    else:
        raise ValueError("action name does not match its published component")
    submission.userAction.context = context.model_dump(mode="json")
    return submission


def synthetic_intake_messages(envelope: Mapping[str, object], *, saved_file=None) -> list[dict[str, object]]:
    """One deterministic, non-callable form pair, preserving the intake wire shape."""
    submission_id = envelope["submissionId"]
    context = envelope["userAction"]["context"]
    digest = hashlib.sha256(submission_id.encode()).hexdigest()[:24]
    custom = envelope["userAction"]["name"] == "submit_form"
    call_id = f"workbench-form-{digest}" if custom else f"workbench-intake-{digest}"
    result = {
        "kind": "untrusted_user_submitted_data",
        "actionSchemaVersion": "form.submit@1" if custom else "intake.submit@1",
        "submissionId": submission_id,
        "context": context,
        **({"savedFile": saved_file} if saved_file else {}),
    }
    return [
        {"id": f"{call_id}-assistant", "role": "assistant", "toolCalls": [{
            "id": call_id, "type": "function", "function": {
                "name": WORKBENCH_FORM_TOOL_NAME if custom else WORKBENCH_INTAKE_TOOL_NAME,
                "arguments": json.dumps({"submissionId": submission_id}, separators=(",", ":")),
            },
        }]},
        {"id": f"{call_id}-result", "role": "tool", "toolCallId": call_id,
         "content": json.dumps(result, sort_keys=True, separators=(",", ":"), ensure_ascii=False)},
    ]


def submission_messages(submission: CanvasSubmission, *, saved_file=None) -> list[Message]:
    envelope = submission.model_dump(mode="json", exclude_none=True)
    if submission.userAction.name in {"submit_intake", "submit_form"}:
        wire = synthetic_intake_messages(envelope, saved_file=saved_file)
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

    def release(self, scope, submission_id):
        """A failed disk write is retryable, without releasing accepted IDs."""
        with self._lock:
            self._keys.discard((*scope.key(), submission_id))
