"""Validated, ordered content publication primitives for the workbench."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Protocol, TypedDict, runtime_checkable


@runtime_checkable
class CatalogValidator(Protocol):
    """Injected adapter for the negotiated emitter/catalog implementation.

    Implementations must reject records not valid for the exact negotiated
    manifests. No built-in adapter is provided while the selected emitter is
    unavailable; callers must supply a reviewed implementation.
    """

    def validate(
        self,
        records: Sequence[Mapping[str, object]],
        negotiated_manifests: Mapping[str, object],
    ) -> None: ...


class ContentPublication(TypedDict):
    record_id: str
    activity_message_id: str
    surface_id: str
    sequence: int
    part_index: int
    part_count: int
    record: dict[str, object]


def build_publication(
    records: Sequence[Mapping[str, object]],
    validator: CatalogValidator,
    negotiated_manifests: Mapping[str, object],
    *,
    sequence: int = 1,
) -> list[ContentPublication]:
    """Validate all content first, then assign stable identity and part order."""
    if validator is None:
        raise TypeError("a CatalogValidator is required")
    if sequence < 1:
        raise ValueError("sequence must be positive")
    frozen = [dict(record) for record in records]
    validator.validate(frozen, negotiated_manifests)
    count = len(frozen)
    result: list[ContentPublication] = []
    for index, record in enumerate(frozen):
        activity_id = record.get("activityMessageId")
        surface_id = record.get("surfaceId")
        if not isinstance(activity_id, str) or not activity_id:
            raise ValueError("content requires stable activityMessageId")
        if not isinstance(surface_id, str) or not surface_id:
            raise ValueError("content requires stable surfaceId")
        result.append(ContentPublication(
            record_id=activity_id,
            activity_message_id=activity_id,
            surface_id=surface_id,
            sequence=sequence,
            part_index=index,
            part_count=count,
            record=record,
        ))
    if len({item["record_id"] for item in result}) != count or len({item["surface_id"] for item in result}) != count:
        raise ValueError("publication identities must be unique")
    return result
