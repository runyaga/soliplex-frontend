"""Basic-catalog form emission and validation against stored definitions."""

from __future__ import annotations

import math
import re
from datetime import date

from .workbench_schemas import FormField


def custom_form_components(record):
    fields = [FormField.model_validate(field) for field in record["fields"]]
    values = {
        field.name: (
            False if field.kind == "checkbox" else [] if field.kind == "choice" else ""
        )
        for field in fields
    }
    controls = []
    for index, field in enumerate(fields):
        control = {
            "id": f"field_{index}",
            "label": field.label,
            "value": {"@path": f"/values/{field.name}"},
        }
        if field.kind == "checkbox":
            control["component"] = "CheckBox"
        elif field.kind == "choice":
            control.update(
                component="ChoicePicker",
                variant="multipleSelection" if field.multiple else "mutuallyExclusive",
                options=[option.model_dump() for option in field.options],
                displayStyle="checkbox",
            )
        elif field.kind == "date":
            control.update(component="DateTimeInput", enableDate=True, enableTime=False)
        else:
            control.update(
                component="TextField",
                variant={"textarea": "longText", "number": "number"}.get(
                    field.kind, "shortText"
                ),
            )
        controls.append(control)
    components = [
        {
            "id": "root",
            "component": "Column",
            "children": ["title", "provenance", *[c["id"] for c in controls], "submit"],
        },
        {"id": "title", "component": "Text", "text": record["title"]},
        {
            "id": "provenance",
            "component": "Text",
            "text": "Form created by the assistant",
        },
        *controls,
        {
            "id": "submit",
            "component": "Button",
            "child": "submit_label",
            "action": {
                "event": {
                    "name": "submit_form",
                    "context": {"values": {"@path": "/values"}},
                }
            },
        },
        {"id": "submit_label", "component": "Text", "text": "Submit"},
    ]
    # Persist the definition in the activity, separate from mutable input values.
    return {
        "title": record["title"],
        "fields": record["fields"],
        "values": values,
    }, components


def validate_form_values(context, record):
    """Accept catalog wire types, normalize them, and never echo submitted data."""
    if set(context) != {"values"} or not isinstance(context["values"], dict):
        raise ValueError("Form submission must contain a values object")
    values = context["values"]
    fields = [FormField.model_validate(field) for field in record["fields"]]
    if set(values) - {field.name for field in fields}:
        raise ValueError(
            "Form contains unknown fields; reload the form and submit only its displayed fields"
        )
    clean = {}
    for field in fields:
        value = values.get(field.name)

        # Labels and names have already passed publication validation. Do not
        # echo the value: a user may have pasted a credential into any input.
        def invalid(fix, label=field.label):
            raise ValueError(f"Form field {label}: {fix}")

        if value == "" and field.kind not in {"text", "textarea", "date", "number"}:
            invalid("use the displayed control's value type")
        if value == [] and field.kind != "choice":
            invalid("use the displayed control's value type")
        if value is None or value == "" or value == []:
            if field.required:
                invalid("a value is required")
            continue
        if field.kind in {"text", "textarea", "date"}:
            if not isinstance(value, str):
                invalid("enter text")
            if len(value) > (field.max_length or 4000):
                invalid(f"use at most {field.max_length or 4000} characters")
            if field.required and not value.strip():
                invalid("a value is required")
            if field.kind == "date":
                try:
                    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
                        raise ValueError
                    date.fromisoformat(value)
                except ValueError:
                    invalid("choose a valid date (YYYY-MM-DD)")
        elif field.kind == "number":
            if isinstance(value, str):
                if not re.fullmatch(r"-?(?:\d+(?:\.\d*)?|\.\d+)", value):
                    invalid("enter a finite number")
                value = float(value)
            try:
                finite = type(value) in (int, float) and math.isfinite(value)
            except OverflowError:
                finite = False
            if not finite:
                invalid("enter a finite number")
            if field.min is not None and value < field.min:
                invalid(f"enter a number at least {field.min:g}")
            if field.max is not None and value > field.max:
                invalid(f"enter a number at most {field.max:g}")
        elif field.kind == "checkbox":
            if type(value) is not bool:
                invalid("use a checkbox value (true or false)")
            if field.required and not value:
                invalid("check this required box")
        elif field.kind == "choice":
            if not isinstance(value, list) or any(
                not isinstance(item, str) for item in value
            ):
                invalid("choose options from the displayed list")
            if len(value) != len(set(value)) or any(
                item not in {option.value for option in field.options} for item in value
            ):
                invalid("choose only allowed options, once each")
            if not field.multiple and len(value) != 1:
                invalid("choose exactly one option")
            value = value if field.multiple else value[0]
        clean[field.name] = value
    return {"surfaceId": record["surfaceId"], "title": record["title"], "values": clean}
