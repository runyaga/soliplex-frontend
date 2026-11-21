from types import SimpleNamespace

import pytest

from soliplex_a2ui_workbench.program_files import read_file, write_file
from soliplex_a2ui_workbench.workbench_repository import WorkbenchScope


@pytest.fixture
def files(tmp_path):
    return SimpleNamespace(sandbox_workdirs_path=tmp_path), WorkbenchScope(
        "alice", "server", "room", "thread"
    )


def test_read_thread_form_csv(files):
    installation, scope = files
    directory = installation.sandbox_workdirs_path / "room" / "thread"
    directory.mkdir(parents=True)
    (directory / "team-survey.csv").write_text(
        "submitted_at,submission_id,color\nnow,id,Blue\n"
    )
    assert "Blue" in read_file(installation, scope, "team-survey.csv")
    assert read_file(installation, scope, "missing.md") == ""


def test_write_survives_reopen_and_is_thread_scoped(files):
    installation, scope = files
    write_file(installation, scope, "notes.md", "Remember this")
    assert read_file(installation, scope, "notes.md") == "Remember this"
    other = WorkbenchScope("alice", "server", "room", "other")
    assert read_file(installation, other, "notes.md") == ""
    write_file(installation, scope, "sales.csv", "month,total\nJan,12\n")
    assert "Jan,12" in read_file(installation, scope, "sales.csv")


@pytest.mark.parametrize(
    "name",
    ["../secret.md", "/notes.md", ".secret.md", "x/.a.md", "a\\b.md", "x.py", "a..md"],
)
def test_reject_paths(files, name):
    installation, scope = files
    with pytest.raises(ValueError):
        write_file(installation, scope, name, "bad")
    with pytest.raises(ValueError):
        read_file(installation, scope, name)


def test_limits_symlinks_and_receipt_csv_are_protected(files, tmp_path):
    installation, scope = files
    write_file(installation, scope, "notes.md", "old")
    with pytest.raises(ValueError):
        write_file(installation, scope, "notes.md", "é" * 40000)
    assert read_file(installation, scope, "notes.md") == "old"
    directory = tmp_path / "room" / "thread"
    receipt = directory / "team-survey.csv"
    receipt.write_text("submitted_at,submission_id,color\nnow,id,Blue\n")
    with pytest.raises(ValueError):
        write_file(installation, scope, receipt.name, "overwrite")
    (directory / "link.md").symlink_to(directory / "notes.md")
    with pytest.raises((OSError, ValueError)):
        read_file(installation, scope, "link.md")
    with pytest.raises((OSError, ValueError)):
        write_file(installation, scope, "link.md", "overwrite")
    (directory / "huge.txt").write_text("x" * 65537)
    with pytest.raises(ValueError):
        read_file(installation, scope, "huge.txt")


def test_exact_utf8_limit_and_special_files(files, tmp_path):
    import os

    installation, scope = files
    write_file(installation, scope, "full.txt", "é" * 32768)
    assert read_file(installation, scope, "full.txt") == "é" * 32768
    directory = tmp_path / "room" / "thread"
    os.link(directory / "full.txt", directory / "hard.md")
    with pytest.raises(ValueError):
        read_file(installation, scope, "hard.md")
    os.mkfifo(directory / "pipe.txt")
    with pytest.raises(ValueError):
        read_file(installation, scope, "pipe.txt")
    other = tmp_path / "elsewhere"
    other.mkdir()
    (directory / "directory.md").mkdir()
    with pytest.raises((OSError, ValueError)):
        write_file(installation, scope, "directory.md", "bad")
    (tmp_path / "room" / "redirect").symlink_to(other)
    redirected = WorkbenchScope("alice", "server", "room", "redirect")
    with pytest.raises(OSError):
        write_file(installation, redirected, "notes.md", "bad")
    assert not list(other.iterdir())


def test_program_cannot_create_a_csv_that_looks_like_form_results(files):
    installation, scope = files
    forged = "submitted_at,submission_id,color\nnow,fake,Red\n"
    with pytest.raises(ValueError):
        write_file(installation, scope, "team-survey.csv", forged)
    assert read_file(installation, scope, "team-survey.csv") == ""
    write_file(installation, scope, "sales.csv", "month,total\nJan,10\n")
