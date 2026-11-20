"""Closed wire models for the first workbench contract."""

from __future__ import annotations

import json
from types import MappingProxyType
from typing import Annotated, Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    TypeAdapter,
    ValidationInfo,
    field_validator,
    model_validator,
)

Id = Annotated[str, Field(min_length=1, max_length=64, pattern=r"^[A-Za-z][A-Za-z0-9_-]*$")]
Title = Annotated[str, Field(min_length=1, max_length=80)]
Source = Annotated[str, Field(min_length=1, max_length=12_000)]
Engine = Annotated[
    str,
    Field(
        min_length=1,
        max_length=128,
        pattern=r"^[A-Za-z][A-Za-z0-9_.-]*-[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$",
    ),
]
PINNED_ENGINE_MANIFEST = frozenset({"monty-1.3.0"})
_ID_ADAPTER = TypeAdapter(Id)


class Closed(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, allow_inf_nan=False)


class Point(Closed):
    id: Id
    label: Annotated[str, Field(min_length=1, max_length=80)]
    value: Annotated[float, Field(ge=-1_000_000_000, le=1_000_000_000)]


Points = Annotated[list[Point], Field(min_length=1, max_length=32)]


class LayoutNode(Closed):
    id: Id
    parentId: Id | None
    children: list[Id]
    kind: Literal["workspace", "region", "split", "tabs", "panel", "window", "surface"]
    title: Title
    size: Literal["small", "medium", "large"]
    visibility: Literal["open", "minimized", "closed"]
    payload: dict[str, object]


class LayoutSnapshot(Closed):
    schemaVersion: Literal[1]
    layoutRevision: Annotated[int, Field(ge=0)]
    rootId: Id
    nodes: Annotated[list[LayoutNode], Field(min_length=6, max_length=64)]
    shared: dict[str, object]

    @model_validator(mode="after")
    def validate_tree(self, info: ValidationInfo) -> LayoutSnapshot:
        if info.context is None or "authenticated_program_surfaces" not in info.context:
            raise ValueError("authenticated program registration metadata is required")
        program_surfaces = info.context["authenticated_program_surfaces"]
        if not isinstance(program_surfaces, set):
            raise ValueError("registered program surfaces must be a set of IDs")
        for surface_id in program_surfaces:
            _ID_ADAPTER.validate_python(surface_id, strict=True)
        by_id = {node.id: node for node in self.nodes}
        if len(by_id) != len(self.nodes) or self.rootId not in by_id:
            raise ValueError("duplicate or missing root id")
        root = by_id[self.rootId]
        if root.kind != "workspace" or root.parentId is not None:
            raise ValueError("invalid workspace root")
        if root.children != ["r_chat", "r_left", "r_right", "r_canvas", "r_tray"]:
            raise ValueError("reserved region order mismatch")
        mounts: set[tuple[str, str]] = set()
        surface_ids: set[str] = set()
        for node in self.nodes:
            if len(node.children) != len(set(node.children)):
                raise ValueError("duplicate child")
            if node.kind == "region":
                if set(node.payload) != {"role"}:
                    raise ValueError("invalid region payload")
            elif node.kind == "split":
                axis = node.payload.get("axis")
                if (
                    node.payload.keys() != {"axis"}
                    or not isinstance(axis, str)
                    or axis not in {"horizontal", "vertical"}
                ):
                    raise ValueError("invalid split payload")
            elif node.kind == "surface":
                if set(node.payload) != {"activityMessageId", "surfaceId"}:
                    raise ValueError("invalid surface payload")
                activity_id = _ID_ADAPTER.validate_python(
                    node.payload["activityMessageId"], strict=True
                )
                surface_id = _ID_ADAPTER.validate_python(
                    node.payload["surfaceId"], strict=True
                )
                mount = (activity_id, surface_id)
                if mount in mounts:
                    raise ValueError("duplicate mount")
                if mount[1] in surface_ids:
                    raise ValueError("duplicate surface id")
                mounts.add(mount)
                surface_ids.add(mount[1])
            elif node.payload:
                raise ValueError("unexpected payload")
            for child_id in node.children:
                child = by_id.get(child_id)
                if child is None or child.parentId != node.id:
                    raise ValueError("inconsistent child edge")
                if not self._allows_child(node.kind, child.kind):
                    raise ValueError("wrong parent kind")
            if node.kind == "split" and len(node.children) > 3:
                raise ValueError("split capacity exceeded")
            if node.kind == "tabs" and len(node.children) > 12:
                raise ValueError("tabs capacity exceeded")
            if node.kind in {"panel", "window"} and len(node.children) > 1:
                raise ValueError("panel capacity exceeded")
            if node.kind in {"workspace", "region"} and node.id in {"wb_root", "r_chat", "r_left", "r_right", "r_canvas", "r_tray"}:
                if node.id != "wb_root" and node.kind != "region":
                    raise ValueError("reserved node kind changed")
        seen: set[str] = set()
        visiting: set[str] = set()

        def walk(node_id: str, depth: int) -> None:
            if depth > 8:
                raise ValueError("maximum depth exceeded")
            if node_id in visiting:
                raise ValueError("cycle")
            if node_id in seen:
                raise ValueError("multiple parents")
            visiting.add(node_id)
            seen.add(node_id)
            for child_id in by_id[node_id].children:
                walk(child_id, depth + 1)
            visiting.remove(node_id)

        walk(self.rootId, 1)
        reachable = set(seen)
        for node_id in by_id:
            if node_id not in seen:
                walk(node_id, 1)
        if seen != set(by_id):
            raise ValueError("orphan node")
        if reachable != set(by_id):
            raise ValueError("orphan node")
        for node in self.nodes:
            ancestors = self._ancestors(node, by_id)
            if node.kind == "window":
                if any(parent.kind == "window" for parent in ancestors):
                    raise ValueError("nested windows are forbidden")
                if not any(parent.id == "r_canvas" for parent in ancestors):
                    raise ValueError("windows require canvas ancestry")
            if (
                node.kind == "surface"
                and node.payload["surfaceId"] in program_surfaces
                and not any(parent.kind == "window" for parent in ancestors)
            ):
                raise ValueError("program surface requires window ancestry")
        self._validate_reserved(by_id)
        open_mounts = sum(
            node.kind == "surface" and self._effectively_open(node, by_id)
            for node in self.nodes
        )
        if open_mounts > 12:
            raise ValueError("open content mount capacity exceeded")
        expanded_windows = sum(
            node.kind == "window" and self._effectively_open(node, by_id)
            for node in self.nodes
        )
        if expanded_windows > 2:
            raise ValueError("expanded window capacity exceeded")
        control_data = json.dumps(
            self.model_dump(mode="json"), separators=(",", ":"), ensure_ascii=False
        ).encode("utf-8")
        if len(control_data) > 65_536:
            raise ValueError("layout exceeds 64 KiB")
        return self

    @staticmethod
    def _ancestors(node: LayoutNode, nodes: dict[str, LayoutNode]) -> list[LayoutNode]:
        ancestors: list[LayoutNode] = []
        visited = {node.id}
        parent_id = node.parentId
        while parent_id is not None:
            if parent_id in visited or len(ancestors) >= len(nodes):
                raise ValueError("cycle in parent ancestry")
            visited.add(parent_id)
            parent = nodes[parent_id]
            ancestors.append(parent)
            parent_id = parent.parentId
        return ancestors

    @staticmethod
    def _effectively_open(node: LayoutNode, nodes: dict[str, LayoutNode]) -> bool:
        current = node
        while True:
            if current.visibility != "open":
                return False
            if current.parentId is None:
                return True
            current = nodes[current.parentId]

    @staticmethod
    def _allows_child(parent: str, child: str) -> bool:
        if parent == "workspace":
            return child == "region"
        if parent == "region":
            return child in {"split", "tabs", "panel", "window"}
        if parent in {"split", "tabs"}:
            return child in {"split", "tabs", "panel", "window"}
        if parent in {"panel", "window"}:
            return child in {"split", "tabs", "surface"}
        return False

    @staticmethod
    def _validate_reserved(nodes: dict[str, LayoutNode]) -> None:
        roles = {"r_chat": "chat", "r_left": "left", "r_right": "right", "r_canvas": "canvas", "r_tray": "tray"}
        for node_id, role in roles.items():
            region = nodes.get(node_id)
            if region is None or region.kind != "region" or region.parentId != "wb_root" or region.payload != {"role": role}:
                raise ValueError("reserved region contract mismatch")
        if nodes["wb_root"].visibility != "open" or any(
            nodes[node_id].visibility != "open" for node_id in roles
        ):
            raise ValueError("reserved nodes must remain open")
        if nodes["r_chat"].children:
            raise ValueError("chat cannot have children")


class IntakeSubmit(Closed):
    question: Annotated[str, Field(min_length=1, max_length=240)]
    districts: Annotated[list[Literal["north", "south"]], Field(min_length=1, max_length=2)]
    acknowledged: Literal[True]

    @field_validator("districts")
    @classmethod
    def unique_districts(cls, value: list[str]) -> list[str]:
        if len(value) != len(set(value)):
            raise ValueError("districts must be unique")
        return value


class ExportChart(Closed):
    title: Title
    kind: Literal["bar", "line"]
    points: Points

    @field_validator("points")
    @classmethod
    def unique_point_ids(cls, value: list[Point]) -> list[Point]:
        if len({point.id for point in value}) != len(value):
            raise ValueError("point ids must be unique")
        return value


class RunResult(Closed):
    side: Literal["client"]
    engine: Engine
    invocationId: Id
    chainId: Id
    outcome: Literal["success", "error", "timeout", "cancelled", "crashed"]
    output: Annotated[str, Field(max_length=4000)]

    @field_validator("engine")
    @classmethod
    def engine_is_pinned(cls, value: str, info: ValidationInfo) -> str:
        return _validate_pinned_engine(value, info.context)


class ProgramExport(Closed):
    invocationId: Id
    title: Title
    kind: Literal["bar", "line"]
    points: Points

    @field_validator("points")
    @classmethod
    def unique_point_ids(cls, value: list[Point]) -> list[Point]:
        if len({point.id for point in value}) != len(value):
            raise ValueError("point ids must be unique")
        return value


class ServerPythonNotEnabled(Closed):
    status: Literal["not_enabled"] = "not_enabled"
    code: Literal["server_runner_deferred"] = "server_runner_deferred"
    tool: Literal["run_python_server"] = "run_python_server"
    side: Literal["server"] = "server"
    execution: Literal["disabled"] = "disabled"


class InterpreterStatePointer(Closed):
    side: Literal["client", "server"]
    engine: Engine
    dump: Annotated[str, Field(min_length=1, max_length=128, pattern=r"^[A-Za-z0-9_-]+$")]
    sha256: Annotated[str, Field(pattern=r"^[0-9a-f]{64}$")]
    owner: Annotated[str, Field(min_length=1, max_length=128)]
    hop: Annotated[int, Field(ge=0, le=4)]

    @field_validator("engine")
    @classmethod
    def engine_is_pinned(cls, value: str, info: ValidationInfo) -> str:
        return _validate_pinned_engine(value, info.context)


def _validate_pinned_engine(
    value: str, context: dict[str, object] | None
) -> str:
    manifest = PINNED_ENGINE_MANIFEST
    if context is not None and "pinned_engine_manifest" in context:
        manifest = context["pinned_engine_manifest"]
    if not isinstance(manifest, (set, frozenset)) or value not in manifest:
        raise ValueError("engine is not in the pinned engine manifest")
    return value


def validate_pointer_owner(
    pointer: InterpreterStatePointer, expected_owner: str
) -> InterpreterStatePointer:
    """Bind a structurally valid pointer to the authenticated scope owner."""
    if pointer.owner != expected_owner:
        raise ValueError("pointer owner does not match authenticated scope")
    return pointer


def validate_registered_mounts(
    snapshot: LayoutSnapshot, registered_mounts: set[tuple[str, str]]
) -> None:
    """Check mounts against the caller's already-authenticated registration set."""
    for node in snapshot.nodes:
        if node.kind != "surface":
            continue
        mount = (
            _ID_ADAPTER.validate_python(node.payload["activityMessageId"], strict=True),
            _ID_ADAPTER.validate_python(node.payload["surfaceId"], strict=True),
        )
        if mount not in registered_mounts:
            raise ValueError("surface mount is not registered in this scope")


def is_effectively_closed(snapshot: LayoutSnapshot, node_id: str) -> bool:
    """Return whether a node or any ancestor stores closed visibility."""
    nodes = {node.id: node for node in snapshot.nodes}
    current = nodes[node_id]
    while True:
        if current.visibility == "closed":
            return True
        if current.parentId is None:
            return False
        current = nodes[current.parentId]


class ActionEnvelope(Closed):
    v: Literal[1]
    submissionId: Annotated[str, Field(min_length=1, max_length=64)]
    activityMessageId: Id
    surfaceRevision: Annotated[int, Field(ge=0, strict=True)]
    actionSchemaVersion: Annotated[str, Field(min_length=1, max_length=128)]
    userAction: IntakeSubmit | ProgramExport | RunResult

    @model_validator(mode="after")
    def within_utf8_limit(self) -> ActionEnvelope:
        encoded = json.dumps(
            self.model_dump(mode="json"), separators=(",", ":"), ensure_ascii=False
        ).encode("utf-8")
        if len(encoded) > 16_384:
            raise ValueError("action envelope exceeds 16 KiB")
        return self


class GetWorkbench(Closed):
    pass


class OpenPanel(Closed):
    title: Title
    text: Annotated[str, Field(min_length=1, max_length=2000)]
    parent_id: Id


class PlaceForm(Closed):
    template: Literal["intake"]
    title: Title
    parent_id: Id


class ShowChart(Closed):
    title: Title
    kind: Literal["bar", "line"]
    points: Points
    parent_id: Id

    @field_validator("points")
    @classmethod
    def unique_point_ids(cls, value: list[Point]) -> list[Point]:
        if len({point.id for point in value}) != len(value):
            raise ValueError("point ids must be unique")
        return value


class RunPythonClient(Closed):
    title: Title
    source: Source
    parent_id: Id

    @field_validator("source")
    @classmethod
    def source_utf8_limit(cls, value: str) -> str:
        if len(value.encode("utf-8")) > 12_000:
            raise ValueError("source exceeds UTF-8 byte limit")
        return value


class RunPythonServer(Closed):
    surface_id: Id
    source: Source

    @field_validator("source")
    @classmethod
    def source_utf8_limit(cls, value: str) -> str:
        if len(value.encode("utf-8")) > 12_000:
            raise ValueError("source exceeds UTF-8 byte limit")
        return value


class CreateContainer(Closed):
    parent_id: Id
    kind: Literal["split", "tabs", "panel", "window"]
    title: Title


class MovePanel(Closed):
    node_id: Id
    parent_id: Id
    order: Annotated[int, Field(ge=0, le=63)]
    size: Literal["small", "medium", "large"]


class ClosePanel(Closed):
    node_id: Id


class RepairProgram(Closed):
    node_id: Id
    source: Source

    @field_validator("source")
    @classmethod
    def source_utf8_limit(cls, value: str) -> str:
        if len(value.encode("utf-8")) > 12_000:
            raise ValueError("source exceeds UTF-8 byte limit")
        return value


# Both minimum room registrations use this immutable callable-name/schema map.
MINIMUM_ROOM_TOOL_MANIFEST = MappingProxyType(
    {
        "get_workbench": GetWorkbench,
        "open_panel": OpenPanel,
        "place_form": PlaceForm,
        "show_chart": ShowChart,
        "run_python_client": RunPythonClient,
        "run_python_server": RunPythonServer,
        "create_container": CreateContainer,
        "move_panel": MovePanel,
        "close_panel": ClosePanel,
        "repair_program": RepairProgram,
    }
)
