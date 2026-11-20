"""JSON parsing helpers that reject ambiguous duplicate object keys."""

from __future__ import annotations

import json
from typing import Any


class DuplicateJSONKey(ValueError):
    pass


def _object_without_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateJSONKey(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def parse_json_no_duplicates(body: bytes) -> Any:
    return json.loads(
        body,
        object_pairs_hook=_object_without_duplicates,
        parse_constant=lambda value: (_ for _ in ()).throw(ValueError(f"invalid JSON constant: {value}")),
    )
