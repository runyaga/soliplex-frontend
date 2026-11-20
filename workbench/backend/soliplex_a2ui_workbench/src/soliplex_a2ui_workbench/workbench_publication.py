"""Closed catalog validation and full-replacement A2UI wire emission."""

from __future__ import annotations

import math
import re
from collections.abc import Mapping, Sequence
from typing import Protocol, TypedDict, runtime_checkable

from ag_ui.core import ActivitySnapshotEvent

from .chart_validation import validate_chart
from .workbench_forms import custom_form_components
from .workbench_schemas import LayoutSnapshot, PlaceForm, validate_registered_mounts

BASIC_CATALOG = "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
GRAPHICS_CATALOG = "urn:soliplex:catalog:graphics:2"
LAB_CATALOG = "urn:soliplex:catalog:lab:1"
WORKBENCH_CATALOG = "urn:soliplex:catalog:workbench:1"

BASIC_COMPONENTS = frozenset({"Text", "Card", "Column", "Row", "List", "CheckBox", "TextField", "DateTimeInput", "ChoicePicker", "Slider", "Button"})
_IDENTIFIER = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{0,63}$")
BUILTIN_CATALOG_MANIFESTS: dict[str, frozenset[str]] = {
    BASIC_CATALOG: BASIC_COMPONENTS,
    GRAPHICS_CATALOG: frozenset({"Chart"}),
    LAB_CATALOG: frozenset({"PythonRepl"}),
    WORKBENCH_CATALOG: frozenset({"PlaceForm"}),
}


@runtime_checkable
class CatalogValidator(Protocol):
    def validate(self, records: Sequence[Mapping[str, object]], negotiated_manifests: Mapping[str, object]) -> None: ...


class WorkbenchCatalogValidator:
    """Validate only the immutable minimum catalogs known to this package."""

    def validate(self, records: Sequence[Mapping[str, object]], negotiated_manifests: Mapping[str, object]) -> None:
        for record in records:
            catalog_id = record.get("catalogId")
            component = record.get("component")
            if not isinstance(catalog_id, str) or catalog_id not in BUILTIN_CATALOG_MANIFESTS:
                raise ValueError("catalog has no package validator")
            negotiated = negotiated_manifests.get(catalog_id)
            if not isinstance(negotiated, (Mapping, set, frozenset, list, tuple)):
                raise ValueError("catalog was not negotiated")  # noqa: TRY004 - retryable payload validation
            negotiated_components = negotiated.keys() if isinstance(negotiated, Mapping) else negotiated
            if component not in BUILTIN_CATALOG_MANIFESTS[catalog_id] or component not in negotiated_components:
                raise ValueError("component is absent from negotiated catalog")
            self._validate_record(catalog_id, str(component), record)
            operations = _content_operations(record)
            self._validate_emitted_components(operations, negotiated_manifests)

    @staticmethod
    def _validate_emitted_components(operations: Sequence[Mapping[str, object]], negotiated_manifests: Mapping[str, object]) -> None:
        """Validate the exact component objects the emitter will publish."""
        for operation in operations:
            update = operation.get("updateComponents")
            if not isinstance(update, dict):
                continue
            components = update.get("components")
            if not isinstance(components, list):
                raise ValueError("emitted component list is invalid")  # noqa: TRY004 - retryable payload validation
            component_ids: set[str] = set()
            for item in components:
                if not isinstance(item, dict):
                    raise ValueError("emitted component must be an object")  # noqa: TRY004 - retryable payload validation
                component_id = item.get("id")
                if not isinstance(component_id, str) or not component_id or component_id in component_ids:
                    raise ValueError("emitted component IDs must be unique")
                component_ids.add(component_id)
                name = item.get("component")
                catalog_id = item.get("@catalogId", BASIC_CATALOG)
                negotiated = negotiated_manifests.get(catalog_id)
                negotiated_components = negotiated.keys() if isinstance(negotiated, Mapping) else negotiated
                if (
                    not isinstance(catalog_id, str)
                    or not isinstance(name, str)
                    or catalog_id not in negotiated_manifests
                    or (catalog_id in BUILTIN_CATALOG_MANIFESTS and name not in BUILTIN_CATALOG_MANIFESTS[catalog_id])
                    or not isinstance(negotiated_components, (set, frozenset, list, tuple, dict))
                    or name not in negotiated_components
                ):
                    raise ValueError("emitted component is not in a negotiated catalog")
                if catalog_id == BASIC_CATALOG:
                    _validate_basic_component(item)
            for item in components:
                if "child" in item and item["child"] not in component_ids:
                    raise ValueError("emitted component reference does not resolve in its surface")
                if item.get("component") in {"Card", "Column", "Row", "List"}:
                    children = item.get("children")
                    if not isinstance(children, list) or any(child not in component_ids for child in children):
                        raise ValueError("emitted component reference does not resolve in its surface")

    @staticmethod
    def _validate_record(catalog_id: str, component: str, record: Mapping[str, object]) -> None:
        common = {"activityMessageId", "surfaceId", "catalogId", "component", "surfaceRevision"}
        if "surfaceRevision" in record:
            revision = record["surfaceRevision"]
            if type(revision) is not int or revision < 0:
                raise ValueError("surfaceRevision must be a non-negative integer")
        record_shapes = {
            (GRAPHICS_CATALOG, "Chart"): common | {"spec", "selection", "description", "height"},
            (LAB_CATALOG, "PythonRepl"): common | {"source", "title", "output", "typeCheck"},
            (WORKBENCH_CATALOG, "PlaceForm"): common | {"template", "title", "fields"},
        }
        allowed_record_keys = record_shapes.get((catalog_id, component), common | {"properties"})
        if set(record) - allowed_record_keys:
            raise ValueError("content record contains fields the emitter does not use")
        for key in ("activityMessageId", "surfaceId"):
            value = record.get(key)
            if not isinstance(value, str) or not _IDENTIFIER.fullmatch(value):
                raise ValueError(f"{key} must be a valid identifier")
        if catalog_id == GRAPHICS_CATALOG and component == "Chart":
            validate_chart({key: record[key] for key in ("spec", "selection", "description", "height") if key in record})
        elif catalog_id == LAB_CATALOG and component == "PythonRepl":
            if "typeCheck" in record and type(record["typeCheck"]) is not bool:
                raise ValueError("typeCheck must be boolean")
            source = record.get("source")
            output = record.get("output", "")
            if not isinstance(source, str) or not source or len(source.encode("utf-8")) > 12_000:
                raise ValueError("invalid PythonRepl source")
            if not isinstance(output, str) or len(output) > 4_000:
                raise ValueError("invalid PythonRepl output")
        elif catalog_id == WORKBENCH_CATALOG and component == "PlaceForm":
            PlaceForm.model_validate({"title": record.get("title"), "parent_id": "r_left",
                                      "template": record.get("template"), "fields": record.get("fields")})
        elif catalog_id == BASIC_CATALOG:
            props = record.get("properties", {})
            if not isinstance(props, dict):
                raise ValueError("basic component properties must be an object")
            allowed = {
                "Text": {"text"},
                "Card": {"children"},
                "Column": {"children"},
                "Row": {"children"},
                "List": {"children"},
                "CheckBox": {"label", "value"},
                "TextField": {"label", "value"},
                "ChoicePicker": {"label", "variant", "options", "value", "displayStyle", "filterable"},
                "Slider": {"min", "max", "value", "label"},
                "Button": {"label", "action"},
            }
            if component not in allowed or set(props) - allowed[component]:
                raise ValueError("unsupported or malformed basic component")
            if component == "Text":
                text = props.get("text")
                if not isinstance(text, (str, dict)):
                    raise ValueError("basic Text requires a string or binding")
                if isinstance(text, dict) and (set(text) != {"@path"} or not isinstance(text["@path"], str)):
                    raise ValueError("invalid basic Text binding")
            if component in {"Card", "Column", "Row", "List"}:
                children = props.get("children")
                if not isinstance(children, list) or any(not isinstance(child, str) for child in children):
                    raise ValueError("basic container requires child IDs")
            if component in {"CheckBox", "TextField"}:
                label = props.get("label")
                value = props.get("value")
                if not isinstance(label, str) or not isinstance(value, (bool, str, dict)):
                    raise ValueError("invalid basic input properties")
                if isinstance(value, dict) and (set(value) != {"@path"} or not isinstance(value["@path"], str)):
                    raise ValueError("invalid basic input binding")
            if component == "Slider":
                low, high = props.get("min"), props.get("max")
                if not all(isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) for value in (low, high)) or low >= high:
                    raise ValueError("invalid basic Slider range")
            if component == "ChoicePicker":
                options, value = props.get("options"), props.get("value")
                if (not isinstance(props.get("label"), str) or props.get("variant") != "multipleSelection"
                    or not isinstance(options, list) or not options or any(not isinstance(option, dict) or set(option) != {"label", "value"} or not isinstance(option.get("label"), str) or not option["label"] or not isinstance(option.get("value"), str) or not option["value"] for option in options)
                    or not isinstance(value, dict) or set(value) != {"@path"} or not isinstance(value["@path"], str)):
                    raise ValueError("invalid basic ChoicePicker properties")
            if component == "Button":
                label, action = props.get("label"), props.get("action")
                if not isinstance(label, str) or not isinstance(action, dict) or not isinstance(action.get("name"), str) or not action["name"] or set(action) - {"name", "context"} or ("context" in action and not isinstance(action["context"], dict)):
                    raise ValueError("invalid basic Button action")


def _validate_basic_component(item: Mapping[str, object]) -> None:
    """Check an emitted basic-catalog definition as a closed object."""
    component = item.get("component")
    common = {"id", "component", "@catalogId"}
    shapes = {
        "Text": common | {"text"},
        "Card": common | {"children"},
        "Column": common | {"children"},
        "Row": common | {"children"},
        "List": common | {"children"},
        "CheckBox": common | {"label", "value"},
        "TextField": common | {"label", "value", "variant"},
        "DateTimeInput": common | {"label", "value", "enableDate", "enableTime"},
        "ChoicePicker": common | {"label", "variant", "options", "value", "displayStyle", "filterable"},
        "Slider": common | {"min", "max", "value", "label"},
        "Button": common | {"label", "child", "action"},
    }
    allowed = shapes.get(component)
    if allowed is None or set(item) - allowed or not isinstance(item.get("id"), str) or not _IDENTIFIER.fullmatch(item["id"]):
        raise ValueError("invalid emitted basic component shape")
    required = {
        "Text": {"text"},
        "Card": {"children"},
        "Column": {"children"},
        "Row": {"children"},
        "List": {"children"},
        "CheckBox": {"label", "value"},
        "TextField": {"label", "value"},
        "DateTimeInput": {"label", "value", "enableDate", "enableTime"},
        "ChoicePicker": {"label", "variant", "options", "value"},
        "Slider": {"min", "max", "value"},
        "Button": {"action"},
    }[component]
    if required - set(item):
        raise ValueError("emitted component is missing required properties")
    if component == "Button":
        action = item.get("action")
        event = action.get("event", action) if isinstance(action, dict) else None
        if (not isinstance(item.get("label", item.get("child")), str) or not isinstance(event, dict) or not isinstance(event.get("name"), str) or not event["name"] or set(event) - {"name", "context"} or ("context" in event and not isinstance(event["context"], dict))):
            raise ValueError("invalid emitted Button action")
    if component == "Text":
        text = item["text"]
        if not isinstance(text, (str, dict)) or (isinstance(text, dict) and (set(text) != {"@path"} or not isinstance(text["@path"], str))):
            raise ValueError("emitted Text requires string or path binding")
    if component in {"Card", "Column", "Row", "List"} and (
        not isinstance(item["children"], list)
        or any(not isinstance(child, str) or not child for child in item["children"])
    ):
        raise ValueError("emitted container children must be component IDs")
    if component == "CheckBox":
        value = item["value"]
        if not isinstance(item["label"], str) or not isinstance(value, (bool, dict)) or (isinstance(value, dict) and (set(value) != {"@path"} or not isinstance(value["@path"], str))):
            raise ValueError("invalid emitted CheckBox properties")
    if component in {"TextField", "DateTimeInput"}:
        value = item["value"]
        if not isinstance(item["label"], str) or not isinstance(value, (str, dict)) or (isinstance(value, dict) and (set(value) != {"@path"} or not isinstance(value["@path"], str))):
            raise ValueError("invalid emitted TextField properties")
    if component == "TextField" and item.get("variant", "shortText") not in {"shortText", "longText", "number"}:
        raise ValueError("invalid emitted TextField variant")
    if component == "DateTimeInput" and (item["enableDate"] is not True or item["enableTime"] is not False):
        raise ValueError("forms support date only")
    if component == "ChoicePicker":
        options, value = item["options"], item["value"]
        if (not isinstance(item["label"], str) or item["variant"] not in {"multipleSelection", "mutuallyExclusive"}
            or not isinstance(options, list) or not options or any(not isinstance(option, dict) or set(option) != {"label", "value"} or not isinstance(option.get("label"), str) or not option["label"] or not isinstance(option.get("value"), str) or not option["value"] for option in options)
            or not isinstance(value, dict) or set(value) != {"@path"} or not isinstance(value["@path"], str)
            or ("displayStyle" in item and item["displayStyle"] not in {"checkbox", "chips"})
            or ("filterable" in item and not isinstance(item["filterable"], bool))):
            raise ValueError("invalid emitted ChoicePicker properties")
    if component == "Slider":
        low, high, value = item["min"], item["max"], item["value"]
        if not all(isinstance(number, (int, float)) and not isinstance(number, bool) and math.isfinite(number) for number in (low, high, value)) or low >= high or not low <= value <= high:
            raise ValueError("invalid emitted Slider properties")
        if "label" in item and not isinstance(item["label"], str):
            raise ValueError("invalid emitted Slider label")


class ContentPublication(TypedDict):
    record_id: str
    activity_message_id: str
    surface_id: str
    sequence: int
    part_index: int
    part_count: int
    record: dict[str, object]


def _operation(surface_id: str, key: str, fields: Mapping[str, object]) -> dict[str, object]:
    return {"version": "1.0", key: {"surfaceId": surface_id, **dict(fields)}}


def _content_operations(record: Mapping[str, object]) -> list[dict[str, object]]:
    sid = str(record["surfaceId"])
    catalog_id = str(record["catalogId"])
    component = str(record["component"])
    data = {key: record[key] for key in ("spec", "source", "title", "template", "output", "typeCheck") if key in record}
    if component == "Chart":
        component_def = {"id": "root", "component": component, "@catalogId": catalog_id, "spec": record["spec"], "selection": record["selection"], "description": record["description"], **({"height": record["height"]} if "height" in record else {})}
    elif component == "PythonRepl":
        component_def = {"id": "root", "component": component, "@catalogId": catalog_id, "source": {"@path": "/source"}, "outputPath": "/output", **({"typeCheck": record["typeCheck"]} if "typeCheck" in record else {}), "onFailure": {"event": {
            "name": "workbench.program.repair", "context": {"result": {"@path": "/output"}},
        }}, "onWorkbench": {"event": {
            "name": "workbench.program.layout", "context": {
                "invocationId": {"@path": "/output/invocationId"}, "actions": {"@path": "/output/actions"},
            },
        }}, "onRun": {"event": {
            "name": "workbench.program.run_result", "context": {
                "side": "client", "engine": "monty-1.3.0",
                **{key: {"@path": f"/output/{key}"} for key in ("invocationId", "chainId", "outcome", "output")},
            },
        }}}
    elif component == "PlaceForm" and "fields" in record:
        data, components = custom_form_components(record)
        return [
            _operation(sid, "createSurface", {"catalogId": BASIC_CATALOG}),
            _operation(sid, "updateDataModel", {"path": "/", "value": data}),
            _operation(sid, "updateComponents", {"components": components}),
        ]
    elif component == "PlaceForm":
        catalog_id = BASIC_CATALOG
        data = {"title": record["title"], "question": "", "districts": [], "acknowledged": False}
        component_def = {
            "id": "root", "component": "Column", "children": ["title", "provenance", "question", "districts", "acknowledged", "submit"],
        }
        extra = [
            {"id": "provenance", "component": "Text", "text": "Form created by the assistant"},
            {"id": "title", "component": "Text", "text": str(record["title"])},
            {"id": "question", "component": "TextField", "label": "Question", "value": {"@path": "/question"}},
            {"id": "districts", "component": "ChoicePicker", "label": "Districts", "variant": "multipleSelection", "options": [{"value": "north", "label": "North"}, {"value": "south", "label": "South"}], "value": {"@path": "/districts"}, "displayStyle": "chips"},
            {"id": "acknowledged", "component": "CheckBox", "label": "Acknowledged", "value": {"@path": "/acknowledged"}},
            {"id": "submit", "component": "Button", "child": "submit_label", "action": {"event": {"name": "submit_intake", "context": {"question": {"@path": "/question"}, "districts": {"@path": "/districts"}, "acknowledged": {"@path": "/acknowledged"}}}}},
            {"id": "submit_label", "component": "Text", "text": "Submit"},
        ]
        return [
            _operation(sid, "createSurface", {"catalogId": catalog_id}),
            _operation(sid, "updateDataModel", {"path": "/", "value": data}),
            _operation(sid, "updateComponents", {"components": [component_def, *extra]}),
        ]
    else:
        properties = record.get("properties", {})
        if not isinstance(properties, dict):
            raise ValueError("component properties must be an object")
        component_def = {"id": "root", "component": component, "@catalogId": catalog_id, **properties}
    return [
        _operation(sid, "createSurface", {"catalogId": BASIC_CATALOG}),
        _operation(sid, "updateDataModel", {"path": "/", "value": data}),
        _operation(sid, "updateComponents", {"components": [component_def]}),
    ]


def _event(message_id: str, operations: list[dict[str, object]], metadata: dict[str, object]) -> dict[str, object]:
    return ActivitySnapshotEvent(
        messageId=message_id,
        activityType="a2ui-surface",
        replace=True,
        content={"a2ui_operations": operations, **metadata},
    ).model_dump(mode="json", by_alias=True, exclude_none=True)


def build_publication(
    records: Sequence[Mapping[str, object]],
    validator: CatalogValidator | None,
    negotiated_manifests: Mapping[str, object],
    *,
    layout: Mapping[str, object],
    sequence: int = 1,
    publication_id: str = "workbench-publication",
    layout_activity_message_id: str = "workbench-layout",
    layout_surface_id: str = "workbench-layout-surface",
    registered_program_surfaces: set[str] | None = None,
    registered_mounts: set[tuple[str, str]] | None = None,
    legacy_journal: bool = True,
) -> dict[str, object]:
    """Validate then build content-before-layout full replacement events."""
    if validator is None:
        raise TypeError("a CatalogValidator is required")
    if sequence < 1:
        raise ValueError("sequence must be positive")
    frozen = [dict(record) for record in records]
    for record in frozen:
        if "surfaceRevision" in record:
            revision = record["surfaceRevision"]
            if type(revision) is not int or revision < 0:
                raise ValueError("surfaceRevision must be a non-negative integer")
    validator.validate(frozen, negotiated_manifests)
    if len({record.get("activityMessageId") for record in frozen}) != len(frozen):
        raise ValueError("activity message IDs must be unique")
    if len({record.get("surfaceId") for record in frozen}) != len(frozen):
        raise ValueError("surface IDs must be unique")
    validated_layout = LayoutSnapshot.model_validate(layout, context={"authenticated_program_surfaces": registered_program_surfaces or set()})
    if registered_mounts is not None:
        validate_registered_mounts(validated_layout, registered_mounts)
    count = len(frozen) + 1
    content_records: list[dict[str, object]] = []
    events: list[dict[str, object]] = []
    for index, record in enumerate(frozen):
        activity_id = record.get("activityMessageId")
        surface_id = record.get("surfaceId")
        if not isinstance(activity_id, str) or not isinstance(surface_id, str):
            raise ValueError("content requires stable activity and surface IDs")  # noqa: TRY004 - retryable payload validation
        commit = {"recordId": publication_id, "sequence": sequence, "index": index, "count": count}
        content_record = record | {"workbenchCommit": commit} if legacy_journal else dict(record)
        content_records.append(content_record)
        metadata = {"workbenchPublication": {"role": "program" if record["component"] == "PythonRepl" else "content", "activityMessageId": activity_id, "surfaceId": surface_id}}
        if legacy_journal:
            metadata["workbenchCommit"] = commit
        events.append({"kind": "content", "record_id": activity_id, "event": _event(activity_id, _content_operations(record), metadata)})
    layout_index = len(frozen)
    layout_commit = {"recordId": publication_id, "sequence": sequence, "index": layout_index, "count": count}
    operations = [
        _operation(layout_surface_id, "createSurface", {"catalogId": BASIC_CATALOG}),
        _operation(layout_surface_id, "updateDataModel", {"path": "/", "value": {"summary": "Workbench", "workbench": validated_layout.model_dump(mode="json")}}),
        _operation(layout_surface_id, "updateComponents", {"components": [{"id": "root", "component": "Text", "text": {"@path": "/summary"}}]}),
    ]
    for record in frozen:
        WorkbenchCatalogValidator._validate_emitted_components(_content_operations(record), negotiated_manifests)
    WorkbenchCatalogValidator._validate_emitted_components(operations, negotiated_manifests)
    metadata = {"workbenchPublication": {"role": "layout", "activityMessageId": layout_activity_message_id, "surfaceId": layout_surface_id}}
    if legacy_journal:
        metadata["workbenchCommit"] = layout_commit
    events.append({"kind": "layout", "record_id": publication_id, "event": _event(layout_activity_message_id, operations, metadata)})
    return {"content_records": content_records, "events": events}
