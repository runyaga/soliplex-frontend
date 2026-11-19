"""Package-owned SQLite repository for scoped workbench snapshots."""

from __future__ import annotations

import hashlib
import json
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Mapping, Sequence

from .workbench_schemas import LayoutSnapshot, validate_registered_mounts


class PublicationConflict(ValueError):
    """A publication key or expected revision conflicts with stored state."""


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


class SQLiteWorkbenchRepository:
    """Single-backend transactional store; caller supplies authenticated scope."""

    def __init__(self, path: str | Path):
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
        """)

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
            self._db.execute("INSERT INTO workbench_snapshot VALUES(?,?,?,?,?,?,?) ON CONFLICT(actor,server,room,thread) DO UPDATE SET revision=excluded.revision, sequence=excluded.sequence, layout_json=excluded.layout_json", (*key, snapshot.layoutRevision, next_sequence, encoded_layout))
            # Each publication is a complete snapshot; do not retain removed content.
            self._db.execute("DELETE FROM workbench_content WHERE actor=? AND server=? AND room=? AND thread=?", key)
            for record_id, part_index, part_count, record_json in content_rows:
                self._db.execute("INSERT INTO workbench_content VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(actor,server,room,thread,record_id) DO UPDATE SET sequence=excluded.sequence, part_index=excluded.part_index, part_count=excluded.part_count, record_json=excluded.record_json", (*key, record_id, next_sequence, part_index, part_count, record_json))
            receipt_id = hashlib.sha256(("/".join(key) + ":" + publication_key).encode()).hexdigest()[:32]
            result = PublicationResult(publication_key, next_sequence, receipt_id, snapshot.model_dump(mode="json"))
            receipt_json = json.dumps({"publication_key": result.publication_key, "sequence": result.sequence, "receipt_id": result.receipt_id, "snapshot": result.snapshot}, separators=(",", ":"), ensure_ascii=False)
            self._db.execute("INSERT INTO workbench_receipt VALUES(?,?,?,?,?,?,?)", (*key, publication_key, digest, receipt_json))
            if before_commit:
                before_commit()
            self._db.execute("COMMIT")
            return result
        except BaseException:
            if self._db.in_transaction:
                self._db.execute("ROLLBACK")
            raise

    def load(self, scope: WorkbenchScope) -> dict[str, object] | None:
        row = self._db.execute("SELECT layout_json FROM workbench_snapshot WHERE actor=? AND server=? AND room=? AND thread=?", scope.key()).fetchone()
        return json.loads(row["layout_json"]) if row else None

    def load_content(self, scope: WorkbenchScope) -> list[dict[str, object]]:
        rows = self._db.execute("SELECT record_json FROM workbench_content WHERE actor=? AND server=? AND room=? AND thread=? ORDER BY sequence, part_index", scope.key()).fetchall()
        return [json.loads(row["record_json"]) for row in rows]

    def get_receipt(self, scope: WorkbenchScope, publication_key: str) -> PublicationResult | None:
        row = self._db.execute("SELECT receipt_json FROM workbench_receipt WHERE actor=? AND server=? AND room=? AND thread=? AND publication_key=?", (*scope.key(), publication_key)).fetchone()
        return PublicationResult(**json.loads(row["receipt_json"])) if row else None

    def close(self) -> None:
        self._db.close()
