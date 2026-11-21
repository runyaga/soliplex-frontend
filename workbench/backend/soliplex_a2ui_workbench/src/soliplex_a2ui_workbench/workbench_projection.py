"""Disposable working state folded from server-persisted workbench activities.

Only fixed tool publications issue roles. Client state and model messages are
never inputs to this projection. SQLite snapshot/reservation routes remain a
separate legacy path and are not read or written here.
"""

from __future__ import annotations

import copy
import hashlib
import logging
from collections.abc import Iterable

from ag_ui.core import ActivitySnapshotEvent
from pydantic import ValidationError
from soliplex.agui.persistence import ThreadStorage
from sqlalchemy.ext.asyncio import AsyncSession

from .workbench_publication import (
    BASIC_CATALOG,
    BUILTIN_CATALOG_MANIFESTS,
    GRAPHICS_CATALOG,
    LAB_CATALOG,
    WORKBENCH_CATALOG,
    WorkbenchCatalogValidator,
    build_publication,
)
from .workbench_repository import (
    PublicationConflict,
    PublicationResult,
    WorkbenchScope,
    default_layout,
)
from .workbench_schemas import LayoutSnapshot, validate_registered_mounts


class RunWorkbenchProjection:
    """Repository-shaped, in-memory source for synchronous tool mutations."""

    def __init__(self, scope: WorkbenchScope, events: Iterable[object] = ()):
        self.scope = scope
        digest = hashlib.sha256("/".join(scope.key()).encode()).hexdigest()[:24]
        self.layout_activity_id = f"wb-layout-{digest}"
        self.layout_surface_id = f"wb-control-{digest}"
        self.layout = default_layout()
        self.content: dict[str, dict] = {}
        self.submission_ids = set()
        self.submission_history = []
        for event in events:
            try:
                self._fold(event)
            except (ValueError, KeyError, TypeError, StopIteration) as exc:
                # Validation errors can contain source/input. Log identities
                # and failure type, never the exception's echoed payload.
                logging.getLogger(__name__).warning(
                    "Invalid workbench publication: scope=%s message_id=%s failure=%s",
                    scope.key(),
                    getattr(event, "message_id", None),
                    type(exc).__name__,
                )

    @property
    def programs(self):
        return {
            record["surfaceId"]
            for record in self.content.values()
            if record["component"] == "PythonRepl"
        }

    @property
    def mounts(self):
        return {
            (record["activityMessageId"], record["surfaceId"])
            for record in self.content.values()
        }

    def _fold(self, event):
        if (
            not isinstance(event, ActivitySnapshotEvent)
            or event.activity_type != "a2ui-surface"
        ):
            return
        content = event.content
        if not isinstance(content, dict):
            return
        registration = content.get("workbenchPublication")
        if not isinstance(registration, dict) or set(registration) != {
            "role",
            "activityMessageId",
            "surfaceId",
        }:
            return
        activity, surface, role = (
            registration[key] for key in ("activityMessageId", "surfaceId", "role")
        )
        if activity != event.message_id or role not in {"layout", "content", "program"}:
            return
        operations = content.get("a2ui_operations")
        if not isinstance(operations, list) or not operations:
            return
        bodies = [
            body
            for operation in operations
            for key, body in operation.items()
            if key != "version"
        ]
        if any(
            not isinstance(body, dict) or body.get("surfaceId") != surface
            for body in bodies
        ):
            return
        data = next(
            (
                op["updateDataModel"]["value"]
                for op in operations
                if "updateDataModel" in op and op["updateDataModel"].get("path") == "/"
            ),
            {},
        )
        if role == "layout":
            if activity != self.layout_activity_id or surface != self.layout_surface_id:
                return
            candidate = LayoutSnapshot.model_validate(
                data["workbench"],
                context={"authenticated_program_surfaces": self.programs},
            )
            validate_registered_mounts(candidate, self.mounts)
            if candidate.layoutRevision >= self.layout["layoutRevision"]:
                self.layout = candidate.model_dump(mode="json")
                self.submission_ids.update(
                    self.layout["shared"].get("programSubmissions", [])
                )
            return
        components = next(
            op["updateComponents"]["components"]
            for op in operations
            if "updateComponents" in op
        )
        root = next(component for component in components if component["id"] == "root")
        component = root["component"]
        record = {
            "activityMessageId": activity,
            "surfaceId": surface,
            "component": component,
        }
        if component == "PythonRepl" and role == "program":
            record.update(
                catalogId=LAB_CATALOG,
                source=data["source"],
                title=data["title"],
                output=data.get("output", ""),
            )
            if "typeCheck" in root:
                record["typeCheck"] = root["typeCheck"]
        elif component == "Chart" and role == "content":
            record.update(
                catalogId=GRAPHICS_CATALOG,
                spec=data["spec"],
                selection=root["selection"],
                description=root["description"],
            )
            if "height" in root:
                record["height"] = root["height"]
        elif component == "Column" and role == "content":
            record.update(
                catalogId=WORKBENCH_CATALOG,
                component="PlaceForm",
                title=data["title"],
                **(
                    {"fields": data["fields"]}
                    if "fields" in data
                    else {"template": "intake"}
                ),
            )
            receipt = next(
                (c.get("text") for c in components if c.get("id") == "receipt"), None
            )
            if receipt:
                record["receipt"] = receipt
        elif component == "Text" and role == "content":
            record.update(catalogId=BASIC_CATALOG, properties={"text": root["text"]})
        else:
            raise ValueError("unsupported server workbench content publication")
        WorkbenchCatalogValidator().validate([record], BUILTIN_CATALOG_MANIFESTS)
        self.content[activity] = record

    def load_snapshot(self, scope):
        if scope != self.scope:
            raise PermissionError("workbench projection scope mismatch")
        return copy.deepcopy(
            {
                "revision": self.layout["layoutRevision"],
                "layout": self.layout,
                "content": list(self.content.values()),
            }
        )

    def publish(
        self,
        scope,
        publication_key,
        expected_revision,
        layout,
        content,
        *,
        registered_program_surfaces,
        registered_mounts,
    ):
        current = self.load_snapshot(scope)
        if (
            expected_revision != current["revision"]
            or layout["layoutRevision"] != expected_revision + 1
        ):
            raise PublicationConflict("stale run-local workbench revision")
        clean = [
            {key: value for key, value in record.items() if key != "workbenchCommit"}
            for record in content
        ]
        changed = [
            record
            for record in clean
            if record != self.content.get(record["activityMessageId"])
        ]
        plan = build_publication(
            changed,
            WorkbenchCatalogValidator(),
            BUILTIN_CATALOG_MANIFESTS,
            layout=layout,
            sequence=layout["layoutRevision"],
            publication_id=publication_key,
            layout_activity_message_id=self.layout_activity_id,
            layout_surface_id=self.layout_surface_id,
            registered_program_surfaces=registered_program_surfaces,
            registered_mounts=registered_mounts,
            legacy_journal=False,
        )
        # Commit working state only after every candidate and emitted component validates.
        self.layout = copy.deepcopy(layout)
        self.content = {
            record["activityMessageId"]: copy.deepcopy(record) for record in clean
        }
        return PublicationResult(
            publication_key, layout["layoutRevision"], "", self.layout, plan["events"]
        )


async def projection_from_thread(deps, scope):
    """Read authenticated stored events, never client state or the model transcript."""
    if deps.thread_persistence_engine is None:
        return RunWorkbenchProjection(scope)
    async with AsyncSession(deps.thread_persistence_engine) as session:
        storage = ThreadStorage(session)
        thread = await storage.get_thread(
            user_name=scope.actor_id, room_id=scope.room_id, thread_id=scope.thread_id
        )
        events = []
        stored_inputs = []
        for run in sorted(
            await thread.list_runs(), key=lambda run: (run.created, run.id_)
        ):
            events.extend(await run.list_events())
            stored = await run.awaitable_attrs.run_agent_input
            if stored is not None:
                stored_inputs.append(stored.to_agui_model())
        projection = RunWorkbenchProjection(scope, events)
        for run_input in stored_inputs:
            restore_submission_history(projection, run_input)
        return projection


def restore_submission_history(projection, run_input):
    """Restore only pairs already accepted and persisted by our adapter hook."""
    from .workbench_actions import CanvasSubmission, submission_messages

    props = run_input.forwarded_props
    envelope = props.get("a2uiAction") if isinstance(props, dict) else None
    if not isinstance(envelope, dict) or "submissionId" not in envelope:
        return
    try:
        submission = CanvasSubmission.model_validate(envelope)
    except ValidationError:
        # Historical reservation envelopes are not action-turn submissions.
        return
    if submission.submissionId in projection.submission_ids:
        return
    receipt = props.get("workbenchFormReceipt", {})
    messages = submission_messages(submission, saved_file=receipt.get("filename"))
    # Presence of the exact server projection distinguishes accepted inputs
    # from historical legacy/unvalidated action envelopes.
    index = next(
        (
            i
            for i in range(len(run_input.messages))
            if run_input.messages[i : i + len(messages)] == messages
        ),
        None,
    )
    if index is None:
        return
    anchor = run_input.messages[index - 1].id if index else None
    projection.submission_ids.add(submission.submissionId)
    projection.submission_history.append((anchor, messages))
