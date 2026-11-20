"""Fixed declarative content templates and the minimum callable table."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable
from types import MappingProxyType

from .workbench_schemas import MINIMUM_ROOM_TOOL_MANIFEST

WORKBENCH_CATALOG = "urn:soliplex:catalog:workbench:1"
GRAPHICS_CATALOG = "urn:soliplex:catalog:graphics:2"
LAB_CATALOG = "urn:soliplex:catalog:lab:1"
BASIC_CATALOG = "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"


def form_record(activity_id: str, surface_id: str, title: str) -> dict[str, object]:
    return {"activityMessageId": activity_id, "surfaceId": surface_id, "catalogId": WORKBENCH_CATALOG,
            "component": "PlaceForm", "template": "intake", "title": title}


def chart_record(activity_id: str, surface_id: str, title: str, kind: str, points: list[dict[str, object]]) -> dict[str, object]:
    return {"activityMessageId": activity_id, "surfaceId": surface_id, "catalogId": GRAPHICS_CATALOG,
            "component": "Chart", "spec": {"kind": kind, "series": [{"id": "values", "label": title, "points": points}]}}


def python_record(activity_id: str, surface_id: str, title: str, source: str) -> dict[str, object]:
    return {"activityMessageId": activity_id, "surfaceId": surface_id, "catalogId": LAB_CATALOG,
            "component": "PythonRepl", "title": title, "source": source, "output": ""}


def text_record(activity_id: str, surface_id: str, title: str, text: str) -> dict[str, object]:
    return {"activityMessageId": activity_id, "surfaceId": surface_id, "catalogId": BASIC_CATALOG,
            "component": "Text", "properties": {"text": text}}


@dataclass(frozen=True)
class ToolRegistration:
    function: Callable[..., object]
    input_model: type


def _build_tool_table():
    from . import workbench_tools as impl
    return {name: ToolRegistration(getattr(impl, name), schema) for name, schema in MINIMUM_ROOM_TOOL_MANIFEST.items()}


_TOOL_TABLE: MappingProxyType | None = None


def __getattr__(name: str) -> object:
    """Build the tool table on first use.

    workbench_tools imports this module, so building the table at import time
    is a circular import whenever workbench_tools is imported first, which is
    how Soliplex resolves configured tool names.
    """
    global _TOOL_TABLE
    if name not in ("MINIMUM_ROOM_TOOLS", "MINIMUM_ROOM_REGISTRATIONS"):
        raise AttributeError(name)
    if _TOOL_TABLE is None:
        _TOOL_TABLE = MappingProxyType(_build_tool_table())
    if name == "MINIMUM_ROOM_TOOLS":
        return _TOOL_TABLE
    # Both configured minimum rooms consume this very same immutable mapping.
    return (_TOOL_TABLE, _TOOL_TABLE)


def validate_room_registrations(registrations=None) -> None:
    if registrations is None:
        registrations = __getattr__("MINIMUM_ROOM_REGISTRATIONS")
    """Fail startup/tests if either actual callable registration drifts from U01."""
    expected = set(MINIMUM_ROOM_TOOL_MANIFEST)
    for tools in registrations:
        if set(tools) != expected:
            raise ValueError("minimum room tool registration does not match manifest")
        if any(tools[name].input_model is not schema for name, schema in MINIMUM_ROOM_TOOL_MANIFEST.items()):
            raise ValueError("minimum room tool schema does not match manifest")
