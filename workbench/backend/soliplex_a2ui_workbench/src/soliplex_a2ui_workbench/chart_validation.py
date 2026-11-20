"""Validate chart properties against the schema exported by the Flutter catalog."""

from __future__ import annotations

import json
import math
from functools import lru_cache
from pathlib import Path

from jsonschema import Draft202012Validator


@lru_cache(maxsize=1)
def chart_validator() -> Draft202012Validator:
    teaching = json.loads(Path(__file__).with_name("catalog_teaching.json").read_text())
    catalog = next(c for c in teaching["catalogs"] if c["catalogId"] == "urn:soliplex:catalog:graphics:2")
    return Draft202012Validator(catalog["components"]["Chart"])


def validate_chart(properties: dict[str, object]) -> None:
    errors = list(chart_validator().iter_errors(properties))
    if errors:
        # Schema diagnostics can include the entire submitted spec. Report only
        # locations and the failed constraint, without echoing submitted input.
        error = errors[0]
        path = ".".join(map(str, error.absolute_path)) or "Chart"
        raise ValueError(f"{path} violates catalog constraint {error.validator}")
    spec = properties["spec"]

    def walk(value):
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            if not math.isfinite(value) or abs(value) > 9007199254740991:
                raise ValueError("Chart values must be finite JSON-safe numbers")
        elif isinstance(value, list):
            ids = [item["id"] for item in value if isinstance(item, dict) and "id" in item]
            if len(ids) != len(set(ids)):
                raise ValueError("Chart ids must be unique within each series")
            for item in value:
                walk(item)
        elif isinstance(value, dict):
            for item in value.values():
                walk(item)

    walk(spec)
    if spec["kind"] == "gauge":
        low, high = spec["min_value"], spec["max_value"]
        if low >= high or any(not low <= spec[key] <= high for key in ("value", "target") if key in spec):
            raise ValueError("Gauge requires min_value < max_value and value/target on that scale")
    elif spec["kind"] == "pie":
        if any(item["value"] < 0 for item in spec["slices"]):
            raise ValueError("Pie values must be nonnegative")
    elif spec["kind"] == "line":
        categories = None
        for series in spec["series"]:
            current = [(p["id"], p["label"]) for p in series["points"]]
            if categories is not None and categories != current:
                raise ValueError("Line series must share ordered point ids and labels")
            categories = current
