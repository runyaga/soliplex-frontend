"""Package-owned SQLite repository for scoped workbench snapshots."""

from __future__ import annotations

import hashlib
import json
import sqlite3
import threading
from dataclasses import dataclass
from functools import wraps
from pathlib import Path
from typing import Callable, Mapping, Sequence

from .workbench_publication import BUILTIN_CATALOG_MANIFESTS, CatalogValidator, WorkbenchCatalogValidator, build_publication
from .workbench_schemas import LayoutSnapshot, validate_registered_mounts


class PublicationConflict(ValueError):
    """A publication key or expected revision conflicts with stored state."""


def _serialized(method):
    """Serialize every access to the repository's shared SQLite connection."""
    @wraps(method)
    def call(self, *args, **kwargs):
        with self._lock:
            return method(self, *args, **kwargs)
    return call


@dataclass(frozen=True)
class WorkbenchScope:
    actor_id: str
    server_id: str
    room_id: str
    thread_id: str

    def __post_init__(self) -> None:
        if not all((self.actor_id, self.server_id, self.room_id, self.thread_id)):
            raise ValueError("all authenticated scope identifiers are required")

    def key(self) -> tuple[str, str, str, str]:
        return self.actor_id, self.server_id, self.room_id, self.thread_id


@dataclass(frozen=True)
class PublicationResult:
    publication_key: str
    sequence: int
    receipt_id: str
    snapshot: dict[str, object]
    events: list[dict[str, object]]


class SQLiteWorkbenchRepository:
    """Single-backend transactional store; caller supplies authenticated scope."""

    def __init__(
        self,
        path: str | Path,
        *,
        catalog_validator: CatalogValidator | None = None,
        negotiated_manifests: Mapping[str, object] | None = None,
    ):
        self._catalog_validator = catalog_validator or WorkbenchCatalogValidator()
        self._negotiated_manifests = negotiated_manifests or BUILTIN_CATALOG_MANIFESTS
        self._lock = threading.RLock()
        self._db = sqlite3.connect(str(path), isolation_level=None, check_same_thread=False)
        self._db.row_factory = sqlite3.Row
        self._db.execute("PRAGMA foreign_keys=ON")
        self._db.execute("PRAGMA journal_mode=WAL")
        self._db.executescript("""
            CREATE TABLE IF NOT EXISTS workbench_snapshot (
                actor TEXT NOT NULL, server TEXT NOT NULL, room TEXT NOT NULL, thread TEXT NOT NULL,
                revision INTEGER NOT NULL, sequence INTEGER NOT NULL, layout_json TEXT NOT NULL,
                PRIMARY KEY(actor, server, room, thread)
            );
            CREATE TABLE IF NOT EXISTS workbench_content (
                actor TEXT NOT NULL, server TEXT NOT NULL, room TEXT NOT NULL, thread TEXT NOT NULL,
                record_id TEXT NOT NULL, sequence INTEGER NOT NULL, part_index INTEGER NOT NULL,
                part_count INTEGER NOT NULL, record_json TEXT NOT NULL,
                PRIMARY KEY(actor, server, room, thread, record_id)
            );
            CREATE TABLE IF NOT EXISTS workbench_receipt (
                actor TEXT NOT NULL, server TEXT NOT NULL, room TEXT NOT NULL, thread TEXT NOT NULL,
                publication_key TEXT NOT NULL, digest TEXT NOT NULL, receipt_json TEXT NOT NULL,
                PRIMARY KEY(actor, server, room, thread, publication_key)
            );
            CREATE TABLE IF NOT EXISTS workbench_action (
                actor TEXT NOT NULL, server TEXT NOT NULL, room TEXT NOT NULL, thread TEXT NOT NULL,
                submission_id TEXT NOT NULL, digest TEXT NOT NULL, envelope_json TEXT NOT NULL,
                state TEXT NOT NULL, layout_revision INTEGER NOT NULL, receipt_json TEXT NOT NULL,
                PRIMARY KEY(actor, server, room, thread, submission_id)
            );
            CREATE TABLE IF NOT EXISTS workbench_invocation (
                actor TEXT NOT NULL, server TEXT NOT NULL, room TEXT NOT NULL, thread TEXT NOT NULL,
                invocation_id TEXT NOT NULL, digest TEXT NOT NULL, receipt_json TEXT NOT NULL,
                PRIMARY KEY(actor, server, room, thread, invocation_id)
            );
            CREATE TABLE IF NOT EXISTS workbench_trace_outbox (
                actor TEXT NOT NULL, server TEXT NOT NULL, room TEXT NOT NULL, thread TEXT NOT NULL,
                invocation_id TEXT NOT NULL, event_json TEXT NOT NULL, emitted INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY(actor, server, room, thread, invocation_id)
            );
        """)

    @_serialized
    def publish(
        self,
        scope: WorkbenchScope,
        publication_key: str,
        expected_revision: int,
        layout: Mapping[str, object],
        content: Sequence[Mapping[str, object]],
        *,
        registered_program_surfaces: set[str],
        registered_mounts: set[tuple[str, str]],
        before_commit: Callable[[], None] | None = None,
    ) -> PublicationResult:
        if not publication_key:
            raise ValueError("publication key is required")
        key = scope.key()
        # U01 owns limits and tree rules; this package only supplies auth-derived context.
        snapshot = LayoutSnapshot.model_validate(layout, context={
            "authenticated_program_surfaces": registered_program_surfaces,
        })
        mounts = {
            (str(node.payload["activityMessageId"]), str(node.payload["surfaceId"]))
            for node in snapshot.nodes if node.kind == "surface"
        }
        validate_registered_mounts(snapshot, registered_mounts)
        by_surface = {str(record.get("surfaceId")): record for record in content}
        if not mounts <= {(str(item.get("activityMessageId")), sid) for sid, item in by_surface.items()}:
            raise ValueError("layout references content absent from publication")
        encoded_layout = json.dumps(snapshot.model_dump(mode="json"), separators=(",", ":"), ensure_ascii=False)
        content_rows = []
        content_record_ids: set[str] = set()
        content_surface_ids: set[str] = set()
        for index, item in enumerate(content):
            data = dict(item)
            record_id = data.get("activityMessageId")
            if not isinstance(record_id, str) or not record_id or not isinstance(data.get("surfaceId"), str):
                raise ValueError("content requires stable activity and surface IDs")
            if record_id in content_record_ids or data["surfaceId"] in content_surface_ids:
                raise ValueError("content publication identities must be unique")
            content_record_ids.add(record_id)
            content_surface_ids.add(data["surfaceId"])
            content_rows.append((record_id, index, len(content), json.dumps(data, separators=(",", ":"), ensure_ascii=False)))
        digest = hashlib.sha256(json.dumps([expected_revision, encoded_layout, content_rows], separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
        self._db.execute("BEGIN IMMEDIATE")
        try:
            receipt = self._db.execute("SELECT digest, receipt_json FROM workbench_receipt WHERE actor=? AND server=? AND room=? AND thread=? AND publication_key=?", (*key, publication_key)).fetchone()
            if receipt:
                if receipt["digest"] != digest:
                    raise PublicationConflict("publication key reused with different body")
                self._db.execute("COMMIT")
                return PublicationResult(**json.loads(receipt["receipt_json"]))
            current = self._db.execute("SELECT revision, sequence FROM workbench_snapshot WHERE actor=? AND server=? AND room=? AND thread=?", key).fetchone()
            revision = current["revision"] if current else 0
            sequence = current["sequence"] if current else 0
            if revision != expected_revision:
                raise PublicationConflict("stale layout revision")
            if snapshot.layoutRevision != expected_revision + 1:
                raise PublicationConflict("layout revision must advance by one")
            next_sequence = sequence + 1
            scope_digest = hashlib.sha256("/".join(key).encode()).hexdigest()[:24]
            plan = build_publication(
                content,
                self._catalog_validator,
                self._negotiated_manifests,
                layout=snapshot.model_dump(mode="json"),
                sequence=next_sequence,
                publication_id=publication_key,
                layout_activity_message_id=f"wb-layout-{scope_digest}",
                layout_surface_id=f"wb-control-{scope_digest}",
                registered_program_surfaces=registered_program_surfaces,
            )
            committed_rows = []
            for item in plan["content_records"]:
                metadata = item["workbenchCommit"]
                committed_rows.append((item["activityMessageId"], metadata["index"], metadata["count"], json.dumps(item, separators=(",", ":"), ensure_ascii=False)))
            self._db.execute("INSERT INTO workbench_snapshot VALUES(?,?,?,?,?,?,?) ON CONFLICT(actor,server,room,thread) DO UPDATE SET revision=excluded.revision, sequence=excluded.sequence, layout_json=excluded.layout_json", (*key, snapshot.layoutRevision, next_sequence, encoded_layout))
            # Each publication is a complete snapshot; do not retain removed content.
            self._db.execute("DELETE FROM workbench_content WHERE actor=? AND server=? AND room=? AND thread=?", key)
            for record_id, part_index, part_count, record_json in committed_rows:
                self._db.execute("INSERT INTO workbench_content VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(actor,server,room,thread,record_id) DO UPDATE SET sequence=excluded.sequence, part_index=excluded.part_index, part_count=excluded.part_count, record_json=excluded.record_json", (*key, record_id, next_sequence, part_index, part_count, record_json))
            receipt_id = hashlib.sha256(("/".join(key) + ":" + publication_key).encode()).hexdigest()[:32]
            result = PublicationResult(publication_key, next_sequence, receipt_id, snapshot.model_dump(mode="json"), plan["events"])
            receipt_json = json.dumps({"publication_key": result.publication_key, "sequence": result.sequence, "receipt_id": result.receipt_id, "snapshot": result.snapshot, "events": result.events}, separators=(",", ":"), ensure_ascii=False)
            self._db.execute("INSERT INTO workbench_receipt VALUES(?,?,?,?,?,?,?)", (*key, publication_key, digest, receipt_json))
            if before_commit:
                before_commit()
            self._db.execute("COMMIT")
            return result
        except BaseException:
            if self._db.in_transaction:
                self._db.execute("ROLLBACK")
            raise

    @_serialized
    def load(self, scope: WorkbenchScope) -> dict[str, object] | None:
        row = self._db.execute("SELECT layout_json FROM workbench_snapshot WHERE actor=? AND server=? AND room=? AND thread=?", scope.key()).fetchone()
        return json.loads(row["layout_json"]) if row else None

    @_serialized
    def load_snapshot(self, scope: WorkbenchScope) -> dict[str, object]:
        self._db.execute("BEGIN")
        try:
            row = self._db.execute(
                "SELECT revision, sequence, layout_json FROM workbench_snapshot WHERE actor=? AND server=? AND room=? AND thread=?",
                scope.key(),
            ).fetchone()
            content_rows = self._db.execute(
                "SELECT record_json FROM workbench_content WHERE actor=? AND server=? AND room=? AND thread=? ORDER BY sequence, part_index",
                scope.key(),
            ).fetchall()
            result = {
                "revision": row["revision"] if row else 0,
                "sequence": row["sequence"] if row else 0,
                "layout": json.loads(row["layout_json"]) if row else None,
                "content": [json.loads(item["record_json"]) for item in content_rows],
            }
            self._db.execute("COMMIT")
            return result
        except BaseException:
            if self._db.in_transaction:
                self._db.execute("ROLLBACK")
            raise

    @_serialized
    def restore_node(self, scope: WorkbenchScope, node_id: str) -> dict[str, object]:
        """Clear one accepted ancestor close while retaining every descendant."""
        key = scope.key()
        self._db.execute("BEGIN IMMEDIATE")
        try:
            row = self._db.execute("SELECT revision, sequence, layout_json FROM workbench_snapshot WHERE actor=? AND server=? AND room=? AND thread=?", key).fetchone()
            if row is None:
                raise ValueError("workbench layout is not registered")
            layout = json.loads(row["layout_json"])
            target = next((node for node in layout["nodes"] if node["id"] == node_id), None)
            if target is None or target["visibility"] != "closed":
                raise ValueError("restore target is not a closed registered node")
            target["visibility"] = "open"
            layout["layoutRevision"] = row["revision"] + 1
            content = self.load_content(scope)
            registered_mounts = {(str(item["activityMessageId"]), str(item["surfaceId"])) for item in content}
            program_surfaces = {str(item["surfaceId"]) for item in content if item.get("component") in {"Program", "PythonRepl"}}
            snapshot = LayoutSnapshot.model_validate(layout, context={"authenticated_program_surfaces": program_surfaces})
            validate_registered_mounts(snapshot, registered_mounts)
            encoded = json.dumps(snapshot.model_dump(mode="json"), separators=(",", ":"), ensure_ascii=False)
            sequence = row["sequence"] + 1
            self._db.execute("UPDATE workbench_snapshot SET revision=?, sequence=?, layout_json=? WHERE actor=? AND server=? AND room=? AND thread=?", (layout["layoutRevision"], sequence, encoded, *key))
            self._db.execute("UPDATE workbench_action SET layout_revision=? WHERE actor=? AND server=? AND room=? AND thread=? AND state='reserved'", (layout["layoutRevision"], *key))
            self._db.execute("COMMIT")
            return {"status": "restored", "nodeId": node_id, "revision": layout["layoutRevision"], "sequence": sequence}
        except BaseException:
            if self._db.in_transaction:
                self._db.execute("ROLLBACK")
            raise

    @_serialized
    def existing_action(self, scope: WorkbenchScope, submission_id: str, digest: str) -> dict[str, object] | None:
        row = self._db.execute(
            "SELECT digest, receipt_json FROM workbench_action WHERE actor=? AND server=? AND room=? AND thread=? AND submission_id=?",
            (*scope.key(), submission_id),
        ).fetchone()
        if row is None:
            return None
        if row["digest"] != digest:
            raise PublicationConflict("submission ID reused with different body")
        return json.loads(row["receipt_json"])

    @_serialized
    def reserve_action(self, scope: WorkbenchScope, submission_id: str, digest: str, envelope: Mapping[str, object], *, expected_revision: int, activity_message_id: str, receipt_details: Mapping[str, object] | None = None) -> dict[str, object]:
        key = (*scope.key(), submission_id)
        encoded = json.dumps(envelope, separators=(",", ":"), ensure_ascii=False)
        self._db.execute("BEGIN IMMEDIATE")
        try:
            row = self._db.execute("SELECT digest, receipt_json FROM workbench_action WHERE actor=? AND server=? AND room=? AND thread=? AND submission_id=?", key).fetchone()
            if row:
                if row["digest"] != digest:
                    raise PublicationConflict("submission ID reused with different body")
                self._db.execute("COMMIT")
                return json.loads(row["receipt_json"])
            snapshot = self._db.execute("SELECT revision FROM workbench_snapshot WHERE actor=? AND server=? AND room=? AND thread=?", scope.key()).fetchone()
            records = self._db.execute("SELECT record_json FROM workbench_content WHERE actor=? AND server=? AND room=? AND thread=?", scope.key()).fetchall()
            is_registered = any(json.loads(record["record_json"]).get("activityMessageId") == activity_message_id for record in records)
            if snapshot is None or snapshot["revision"] != expected_revision or not is_registered:
                raise PublicationConflict("action revision or registration became stale")
            details = dict(receipt_details or {})
            invocation_id = details.pop("invocationId", None)
            invocation_digest = details.pop("invocationDigest", None)
            existing_invocation = False
            if invocation_id is not None:
                invocation = self._db.execute("SELECT digest, receipt_json FROM workbench_invocation WHERE actor=? AND server=? AND room=? AND thread=? AND invocation_id=?", (*scope.key(), invocation_id)).fetchone()
                if invocation:
                    if invocation["digest"] != invocation_digest:
                        raise PublicationConflict("invocation ID reused with different result")
                    existing_invocation = True
            receipt = {"status": "reserved", "submissionId": submission_id, **details}
            self._db.execute("INSERT INTO workbench_action VALUES(?,?,?,?,?,?,?,?,?,?)", (*key, digest, encoded, "reserved", expected_revision, json.dumps(receipt)))
            if invocation_id is not None and not existing_invocation:
                self._db.execute("INSERT INTO workbench_invocation VALUES(?,?,?,?,?,?,?)", (*scope.key(), invocation_id, invocation_digest, json.dumps(receipt)))
                if "trace" in details:
                    self._db.execute("INSERT INTO workbench_trace_outbox VALUES(?,?,?,?,?,?,0)", (*scope.key(), invocation_id, json.dumps(details["trace"], separators=(",", ":"))))
            self._db.execute("COMMIT")
            return receipt
        except BaseException:
            if self._db.in_transaction:
                self._db.execute("ROLLBACK")
            raise

    @_serialized
    def consume_action(self, scope: WorkbenchScope, submission_id: str, digest: str) -> dict[str, object] | None:
        key = (*scope.key(), submission_id)
        self._db.execute("BEGIN IMMEDIATE")
        try:
            row = self._db.execute("SELECT digest, envelope_json, state, layout_revision FROM workbench_action WHERE actor=? AND server=? AND room=? AND thread=? AND submission_id=?", key).fetchone()
            if not row or row["digest"] != digest or row["state"] != "reserved":
                self._db.execute("ROLLBACK")
                return None
            envelope = json.loads(row["envelope_json"])
            current = self._db.execute("SELECT revision FROM workbench_snapshot WHERE actor=? AND server=? AND room=? AND thread=?", scope.key()).fetchone()
            records = self._db.execute("SELECT record_json FROM workbench_content WHERE actor=? AND server=? AND room=? AND thread=?", scope.key()).fetchall()
            registered = any(json.loads(record["record_json"]).get("activityMessageId") == envelope.get("activityMessageId") for record in records)
            if current is None or current["revision"] != row["layout_revision"] or not registered:
                self._db.execute("UPDATE workbench_action SET state='unresolved' WHERE actor=? AND server=? AND room=? AND thread=? AND submission_id=?", key)
                self._db.execute("COMMIT")
                return None
            self._db.execute("UPDATE workbench_action SET state='dispatching' WHERE actor=? AND server=? AND room=? AND thread=? AND submission_id=?", key)
            self._db.execute("COMMIT")
            return envelope
        except BaseException:
            if self._db.in_transaction:
                self._db.execute("ROLLBACK")
            raise

    @_serialized
    def issued_intake_submissions(self, scope: WorkbenchScope) -> list[dict[str, object]]:
        """Return intake reservations handed to the downstream handler."""
        rows = self._db.execute(
            "SELECT envelope_json FROM workbench_action WHERE actor=? AND server=? AND room=? AND thread=? AND state='issued'",
            scope.key(),
        ).fetchall()
        return [json.loads(row["envelope_json"]) for row in rows]

    @_serialized
    def mark_action_issued(self, scope: WorkbenchScope, submission_id: str) -> bool:
        """Record the guard's completed handoff after the body is ready."""
        cursor = self._db.execute(
            "UPDATE workbench_action SET state='issued' WHERE actor=? AND server=? AND room=? AND thread=? AND submission_id=? AND state='dispatching'",
            (*scope.key(), submission_id),
        )
        return cursor.rowcount == 1

    @_serialized
    def emit_trace_once(self, scope: WorkbenchScope, invocation_id: str, sink) -> bool:
        """Deliver one accepted invocation event and mark it emitted atomically."""
        key = (*scope.key(), invocation_id)
        self._db.execute("BEGIN IMMEDIATE")
        try:
            row = self._db.execute("SELECT event_json, emitted FROM workbench_trace_outbox WHERE actor=? AND server=? AND room=? AND thread=? AND invocation_id=?", key).fetchone()
            if row is None or row["emitted"]:
                self._db.execute("COMMIT")
                return False
            sink.emit(json.loads(row["event_json"]))
            self._db.execute("UPDATE workbench_trace_outbox SET emitted=1 WHERE actor=? AND server=? AND room=? AND thread=? AND invocation_id=?", key)
            self._db.execute("COMMIT")
            return True
        except BaseException:
            if self._db.in_transaction:
                self._db.execute("ROLLBACK")
            raise

    @_serialized
    def load_content(self, scope: WorkbenchScope) -> list[dict[str, object]]:
        rows = self._db.execute("SELECT record_json FROM workbench_content WHERE actor=? AND server=? AND room=? AND thread=? ORDER BY sequence, part_index", scope.key()).fetchall()
        return [json.loads(row["record_json"]) for row in rows]

    @_serialized
    def get_receipt(self, scope: WorkbenchScope, publication_key: str) -> PublicationResult | None:
        row = self._db.execute("SELECT receipt_json FROM workbench_receipt WHERE actor=? AND server=? AND room=? AND thread=? AND publication_key=?", (*scope.key(), publication_key)).fetchone()
        return PublicationResult(**json.loads(row["receipt_json"])) if row else None

    @_serialized
    def close(self) -> None:
        self._db.close()
