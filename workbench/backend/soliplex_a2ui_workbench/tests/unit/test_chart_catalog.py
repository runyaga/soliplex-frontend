"""The agent, emitter and actual Flutter catalog agree on chart shapes."""

import asyncio
from copy import deepcopy

import pytest
from pydantic_ai import ModelRetry
from soliplex_a2ui_workbench.chart_validation import chart_validator, validate_chart
from soliplex_a2ui_workbench.workbench_agent_tools import show_chart
from soliplex_a2ui_workbench.workbench_teaching import CHART_EXAMPLES, room_skill
from test_workbench_agent_tools import _context as context


@pytest.fixture(autouse=True)
def configured_room(monkeypatch):
    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")


@pytest.mark.parametrize("kind", ["bar", "line", "pie", "gauge"])
def test_show_chart_emits_properties_validated_by_actual_catalog(kind):
    ctx = context()
    arguments = CHART_EXAMPLES[kind]
    result = asyncio.run(show_chart(ctx, **arguments))
    operations = result.metadata[0].content["a2ui_operations"]
    data = operations[1]["updateDataModel"]["value"]
    component = operations[2]["updateComponents"]["components"][0]
    properties = {k: v for k, v in component.items() if k not in {"id", "component", "@catalogId"}}
    properties["spec"] = data["spec"]
    assert properties["spec"]["kind"] == kind
    assert properties["selection"] == []
    chart_validator().validate(properties)
    validate_chart(properties)
    assert f'"kind": "{kind}"' in room_skill("workbench")


@pytest.mark.parametrize("kind,points,scale", [
    ("pie", [{"id": "a", "label": "A", "value": -1}], None),
    ("gauge", [{"id": "a", "label": "A", "value": 101}], None),
    ("gauge", [{"id": "a", "label": "A", "value": 50}], {"min_value": 100, "max_value": 0}),
    ("gauge", [{"id": "a", "label": "A", "value": 50}], {"target": 101}),
    ("gauge", [{"id": "a", "label": "A", "value": 50}, {"id": "b", "label": "B", "value": 60}], None),
    ("bar", [{"id": "a", "label": "A", "value": float("nan")}], None),
    ("bar", [{"id": "a", "label": "A", "value": 1}, {"id": "a", "label": "B", "value": 2}], None),
])
def test_bad_chart_is_corrective_retry_without_publication(kind, points, scale):
    ctx = context()
    with pytest.raises(ModelRetry, match="Gauge takes exactly one point"):
        asyncio.run(show_chart(ctx, title="Counts", kind=kind, points=points, parent_id="r_canvas", scale=scale))
    assert not hasattr(ctx.deps, "_workbench_context") or ctx.deps._workbench_context.snapshot()["revision"] == 0


def test_gauge_custom_scale_and_schema_drift_are_checked():
    ctx = context()
    result = asyncio.run(show_chart(ctx, title="Counts", kind="gauge", points=[{"id": "a", "label": "A", "value": 500}], parent_id="r_canvas", scale={"max_value": 1000, "target": 800}))
    spec = result.metadata[0].content["a2ui_operations"][1]["updateDataModel"]["value"]["spec"]
    assert spec == {"kind": "gauge", "title": "Counts", "value": 500, "min_value": 0, "max_value": 1000, "target": 800}
    bad = {"spec": deepcopy(spec), "selection": [], "description": "Counts"}
    bad["spec"]["invented"] = 1
    with pytest.raises(ValueError, match="catalog constraint"):
        validate_chart(bad)
