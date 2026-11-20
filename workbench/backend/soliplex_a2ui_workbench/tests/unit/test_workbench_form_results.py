"""Real CSV writes, concurrent processes, bounded reads and public downloads."""

import asyncio
import csv
import json
import multiprocessing
import re
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from soliplex import agui, installation, views
from soliplex.views import sandbox_workdirs

from soliplex_a2ui_workbench.workbench_actions import validate_submission
from soliplex_a2ui_workbench.workbench_form_results import (
    MAX_RESULT_BYTES,
    append_form_result,
    csv_cell,
    form_slug,
    read_form_results,
)
from soliplex_a2ui_workbench.workbench_repository import WorkbenchScope
from test_workbench_forms import envelope, published


@pytest.fixture
def saved(tmp_path, monkeypatch):
    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "room")
    _, projection, record = asyncio.run(published())
    scope = WorkbenchScope("alice", "server", "room", str(uuid4()))
    install = SimpleNamespace(sandbox_workdirs_path=tmp_path / "workdirs")
    submission = validate_submission(envelope(record), projection)
    return SimpleNamespace(
        installation=install,
        scope=scope,
        record=record,
        submission=submission,
        projection=projection,
    )


def save(saved):
    return append_form_result(
        saved.installation, saved.scope, saved.submission, saved.record
    )


def path(saved, filename):
    return (
        saved.installation.sandbox_workdirs_path
        / saved.scope.room_id
        / saved.scope.thread_id
        / filename
    )


def rows(saved, filename):
    with path(saved, filename).open(newline="") as source:
        return list(csv.reader(source))


def test_append_header_order_utc_dedup_and_csv_quoting(saved):
    saved.submission.userAction.context["values"]["notes"] = 'one,"two"\nthree\rfour'
    filename = save(saved)
    assert filename == "scenario-survey.csv"
    assert save(saved) == filename
    saved.submission.submissionId = "second"
    assert save(saved) == filename
    data = rows(saved, filename)
    assert len(data) == 3
    assert data[0] == [
        "submitted_at",
        "submission_id",
        *[f["name"] for f in saved.record["fields"]],
    ]
    assert datetime.fromisoformat(data[1][0]).utcoffset().total_seconds() == 0
    assert data[1][3] == 'one,"two"\nthree\rfour'
    assert data[1][4] == "42.0"
    assert data[1][7] == "true"
    # Dedupe survives a new context/process and even another published form.
    saved.record["title"] = "Another form"
    assert save(saved) == filename
    assert len(list(path(saved, filename).parent.iterdir())) == 1


@pytest.mark.parametrize(
    "value", ["=1+1", "+sum(1)", "-42", "@foo", "\tdata", "\rdata"]
)
def test_formula_escaping(saved, value):
    saved.submission.userAction.context["values"]["name"] = value
    assert rows(saved, save(saved))[1][2] == "'" + value
    assert csv_cell(-42) == "'-42"
    assert csv_cell("plain") == "plain"


@pytest.mark.parametrize(
    "title",
    ["../../evil", "..\\..\\evil", "/tmp/x", "...", "🍀", "A" * 80, "Café survey"],
)
def test_slug_safety(saved, title):
    saved.record["title"] = title
    filename = save(saved)
    assert re.fullmatch(r"[a-z0-9-]{1,48}\.csv", filename)
    assert path(saved, filename).parent == path(saved, "x").parent
    assert form_slug("Café survey") == "cafe-survey"


def test_same_title_fields_and_order_control_file_sharing(saved):
    assert save(saved) == "scenario-survey.csv"
    saved.submission.submissionId = "same-fields"
    assert save(saved) == "scenario-survey.csv"
    saved.record["fields"] = list(reversed(saved.record["fields"]))
    saved.submission.submissionId = "different-order"
    assert save(saved) == "scenario-survey-2.csv"
    saved.submission.submissionId = "same-reversed-fields"
    assert save(saved) == "scenario-survey-2.csv"
    saved.record["fields"] = saved.record["fields"][:1]
    saved.submission.submissionId = "different-fields"
    assert save(saved) == "scenario-survey-3.csv"
    assert len(rows(saved, "scenario-survey.csv")) == 3
    assert len(rows(saved, "scenario-survey-2.csv")) == 3


def test_intake_uses_fixed_filename_and_field_order(saved):
    saved.submission.userAction.name = "submit_intake"
    saved.submission.userAction.context = {
        "question": "=question",
        "districts": ["north", "south"],
        "acknowledged": True,
    }
    assert save(saved) == "intake.csv"
    assert rows(saved, "intake.csv")[0] == [
        "submitted_at",
        "submission_id",
        "question",
        "districts",
        "acknowledged",
    ]
    assert rows(saved, "intake.csv")[1][2:] == [
        "'=question",
        '["north","south"]',
        "true",
    ]


def _concurrent_save(args):
    install, scope, submission, record, index = args
    submission = submission.model_copy(deep=True)
    submission.submissionId = f"concurrent-{index}"
    return append_form_result(install, scope, submission, record)


def test_concurrent_processes_append_whole_rows_and_header_once(saved):
    args = [
        (saved.installation, saved.scope, saved.submission, saved.record, i % 8)
        for i in range(24)
    ]
    with multiprocessing.get_context("spawn").Pool(4) as pool:
        filenames = pool.map(_concurrent_save, args)
    assert set(filenames) == {"scenario-survey.csv"}
    data = rows(saved, filenames[0])
    assert len(data) == 9
    assert len({row[1] for row in data[1:]}) == 8
    assert all(len(row) == len(data[0]) for row in data)
    with ThreadPoolExecutor(max_workers=4) as pool:
        assert set(pool.map(_concurrent_save, args)) == {"scenario-survey.csv"}
    assert len(rows(saved, filenames[0])) == 9


def test_read_results_is_untrusted_bounded_and_read_only(saved):
    assert (
        read_form_results(saved.installation, saved.scope, saved.record["title"])[
            "row_count"
        ]
        == 0
    )
    assert not saved.installation.sandbox_workdirs_path.exists()
    for i in range(25):
        saved.submission.submissionId = f"row-{i}"
        saved.submission.userAction.context["values"]["notes"] = "z" * 4000
        save(saved)
    result = read_form_results(saved.installation, saved.scope, saved.record["title"])
    assert result["kind"] == "untrusted_user_submitted_data"
    assert result["row_count"] == 25
    assert len(json.dumps(result, ensure_ascii=False).encode()) <= MAX_RESULT_BYTES
    recent = result["files"][0]["rows"]
    assert 0 < len(recent) <= 20
    assert recent[-1][1] == "row-24"
    assert len(recent[-1][3]) == 1000
    assert len(rows(saved, "scenario-survey.csv")) == 26


def test_scope_and_file_symlinks_cannot_escape_workdir(saved, tmp_path):
    outside = tmp_path / "outside"
    outside.mkdir()
    thread = path(saved, "x").parent
    thread.parent.mkdir(parents=True)
    thread.symlink_to(outside, target_is_directory=True)
    with pytest.raises(OSError):
        save(saved)
    thread.unlink()
    thread.mkdir()
    (outside / "target.csv").write_text("unchanged")
    path(saved, "scenario-survey.csv").symlink_to(outside / "target.csv")
    with pytest.raises(OSError):
        save(saved)
    assert (outside / "target.csv").read_text() == "unchanged"
    saved.scope = WorkbenchScope("alice", "server", "..", "escape")
    with pytest.raises(ValueError, match="scope"):
        save(saved)


def test_public_workdir_listing_and_download_serve_saved_csv(saved):
    filename = save(saved)
    app = FastAPI()
    app.include_router(sandbox_workdirs.router, prefix="/api")

    # Stub identity/ownership dependencies; keep the public listing, safe file
    # opening, streaming response and CSV bytes real.
    async def owns_thread(**kwargs):
        return None

    from unittest.mock import patch

    app.dependency_overrides[installation.depend_the_installation.dependency] = (
        lambda: saved.installation
    )
    app.dependency_overrides[agui.depend_the_threads.dependency] = lambda: None
    app.dependency_overrides[views.depend_the_room_authz_policy.dependency] = (
        lambda: None
    )
    app.dependency_overrides[views.depend_the_user_claims.dependency] = lambda: {}
    app.dependency_overrides[views.depend_the_logger.dependency] = (
        lambda: SimpleNamespace(debug=lambda *args: None)
    )
    with patch.object(
        sandbox_workdirs.soliplex_views_agui, "_check_thread_ownership", owns_thread
    ):
        client = TestClient(app)
        base = f"/api/v1/workdirs/{saved.scope.room_id}/thread/{saved.scope.thread_id}"
        listing = client.get(base)
        assert listing.status_code == 200, listing.text
        assert [file["filename"] for file in listing.json()["files"]] == [filename]
        response = client.get(base + "/file/" + filename)
        assert response.status_code == 200, response.text
        assert response.content == path(saved, filename).read_bytes()
        assert "attachment" in response.headers["content-disposition"]


def test_custom_intake_title_leaves_intake_csv_for_the_template(saved):
    saved.record["title"] = "Intake"
    assert save(saved) == "intake-2.csv"
    saved.submission.submissionId = "built-in-intake"
    saved.submission.userAction.name = "submit_intake"
    saved.submission.userAction.context = {
        "question": "Hello",
        "districts": ["north"],
        "acknowledged": True,
    }
    assert save(saved) == "intake.csv"


def test_registered_read_tool_uses_authenticated_scope_and_does_not_write(
    saved, monkeypatch
):
    from test_workbench_agent_tools import _context, _tool
    from pydantic_ai import ModelRetry

    save(saved)
    context = _context()
    saved.installation.server_id = saved.scope.server_id
    context.deps.the_installation = saved.installation
    context.deps.thread_id = saved.scope.thread_id
    result = asyncio.run(
        _tool("read_form_results").function(context, title=saved.record["title"])
    )
    assert result["row_count"] == 1
    assert result["files"][0]["filename"] == "scenario-survey.csv"
    assert result["kind"] == "untrusted_user_submitted_data"
    assert len(rows(saved, "scenario-survey.csv")) == 2
    context.deps.thread_id = str(uuid4())
    assert (
        asyncio.run(
            _tool("read_form_results").function(context, title=saved.record["title"])
        )["row_count"]
        == 0
    )
    monkeypatch.setenv("SOLIPLEX_WORKBENCH_ROOMS", "")
    with pytest.raises(ModelRetry, match="not configured"):
        asyncio.run(
            _tool("read_form_results").function(context, title=saved.record["title"])
        )
