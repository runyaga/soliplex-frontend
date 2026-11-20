"""Authenticated, turn-scoped dependencies for deterministic workbench tools."""
from __future__ import annotations

import os
import uuid
from dataclasses import dataclass, field

from .workbench_repository import SQLiteWorkbenchRepository, WorkbenchScope


def configured_rooms() -> frozenset[str]:
    """Return the fail-closed room allowlist configured by the backend owner."""
    return frozenset(room.strip() for room in os.environ.get("SOLIPLEX_WORKBENCH_ROOMS", "").split(",") if room.strip())


@dataclass
class WorkbenchToolContext:
    """Dependencies injected by the authenticated room agent for one turn."""
    scope: WorkbenchScope
    repository: SQLiteWorkbenchRepository
    run_id: str
    allowed_rooms: frozenset[str] | None = None
    repair_authorized_node_ids: frozenset[str] = frozenset()
    expected_revision: int | None = field(default=None, init=False)
    _mutation_index: int = field(default=0, init=False)

    def __post_init__(self) -> None:
        if self.allowed_rooms is None:
            self.allowed_rooms = configured_rooms()
        if self.scope.room_id in self.allowed_rooms:
            self.expected_revision = int(self.repository.load_snapshot(self.scope)["revision"])

    def require_room(self) -> None:
        if not self.allowed_rooms or self.scope.room_id not in self.allowed_rooms:
            raise PermissionError("workbench room is not configured in SOLIPLEX_WORKBENCH_ROOMS")

    def snapshot(self) -> dict[str, object]:
        self.require_room()
        snapshot = self.repository.load_snapshot(self.scope)
        revision = int(snapshot["revision"])
        if self.expected_revision is not None and self.expected_revision != revision:
            from .workbench_repository import PublicationConflict
            raise PublicationConflict("workbench turn revision is stale")
        self.expected_revision = revision
        return snapshot

    def publication_key(self) -> str:
        self._mutation_index += 1
        safe_run = "".join(ch if ch.isalnum() or ch in "_-" else "_" for ch in self.run_id)[:48] or "run"
        return f"{safe_run}-{self._mutation_index}-{uuid.uuid4().hex[:12]}"
