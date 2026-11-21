"""Large programs pass every wire validator while finite limits still hold."""

import json

import pytest
from pydantic import ValidationError
from soliplex_a2ui_workbench.workbench_limits import (
    MAX_ACTION_BYTES,
    MAX_EDITOR_SOURCE_CHARS,
    MAX_OUTPUT_CHARS,
    MAX_PROGRAM_SOURCE_BYTES,
)
from soliplex_a2ui_workbench.workbench_publication import (
    LAB_CATALOG,
    WorkbenchCatalogValidator,
)
from soliplex_a2ui_workbench.workbench_schemas import (
    ActionEnvelope,
    ProgramRepairResult,
    RepairProgram,
    RunPythonClient,
    RunPythonServer,
    RunResult,
)


@pytest.mark.parametrize(
    ("model", "fields"),
    [
        (RunPythonClient, {"title": "Large", "parent_id": "panel"}),
        (RunPythonServer, {"surface_id": "surface"}),
        (RepairProgram, {"node_id": "node"}),
    ],
)
def test_published_source_accepts_exact_utf8_cap_and_rejects_one_byte_more(model, fields):
    source = "é" * (MAX_PROGRAM_SOURCE_BYTES // 2)
    assert model.model_validate({**fields, "source": source}).source == source
    with pytest.raises(ValidationError):
        model.model_validate({**fields, "source": source + "x"})


def test_publication_uses_the_same_source_and_output_caps():
    record = {
        "activityMessageId": "activity",
        "surfaceId": "surface",
        "catalogId": LAB_CATALOG,
        "component": "PythonRepl",
        "title": "Large",
        "source": "é" * (MAX_PROGRAM_SOURCE_BYTES // 2),
        "output": "x" * MAX_OUTPUT_CHARS,
    }
    validator = WorkbenchCatalogValidator()
    manifests = {LAB_CATALOG: {"PythonRepl"}}
    validator.validate([record], manifests)
    with pytest.raises(ValueError, match="source"):
        validator.validate([{**record, "source": record["source"] + "x"}], manifests)
    with pytest.raises(ValueError, match="output"):
        validator.validate([{**record, "output": record["output"] + "x"}], manifests)


def test_run_result_accepts_the_complete_client_output():
    result = {
        "side": "client",
        "engine": "monty-1.3.0",
        "invocationId": "invocation",
        "chainId": "chain",
        "outcome": "success",
        "output": "é" * MAX_OUTPUT_CHARS,
    }
    assert RunResult.model_validate(result).output == result["output"]
    with pytest.raises(ValidationError):
        RunResult.model_validate({**result, "output": result["output"] + "x"})


def test_repair_source_and_error_context_have_separate_budgets():
    result = {
        "run": 1,
        "source": "x" * MAX_EDITOR_SOURCE_CHARS,
        "output": "error",
        "error": "error",
        "ok": False,
        "attempt": 1,
        "chainId": "chain",
        "aiFix": True,
        "autoRun": True,
        "instruction": "Repair",
    }
    assert ProgramRepairResult.model_validate(result).source == result["source"]
    with pytest.raises(ValidationError):
        ProgramRepairResult.model_validate({**result, "source": result["source"] + "x"})
    with pytest.raises(ValidationError):
        ProgramRepairResult.model_validate({**result, "output": "x" * 2001})


def test_action_envelope_carries_full_source_and_counts_utf8_bytes():
    envelope = {
        "submissionId": "repair",
        "activityMessageId": "activity",
        "userAction": {
            "name": "workbench.program.repair",
            "surfaceId": "surface",
            "context": {"source": "x" * MAX_PROGRAM_SOURCE_BYTES},
        },
    }
    assert ActionEnvelope.model_validate(envelope).userAction.context == envelope["userAction"]["context"]
    context = envelope["userAction"]["context"]
    context["source"] = ""
    # Validation includes the optional null fields in its wire size.
    normalized = ActionEnvelope.model_validate(envelope).model_dump(mode="json")
    overhead = len(json.dumps(normalized, separators=(",", ":"), ensure_ascii=False).encode())
    available = MAX_ACTION_BYTES - overhead
    context["source"] = "é" * (available // 2) + "x" * (available % 2)
    ActionEnvelope.model_validate(envelope)
    context["source"] += "x"
    with pytest.raises(ValidationError, match="workbench action exceeds"):
        ActionEnvelope.model_validate(envelope)
