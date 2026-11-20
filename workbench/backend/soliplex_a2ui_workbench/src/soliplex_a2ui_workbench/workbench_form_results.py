"""Thread-local CSV results, shared with Soliplex's public workdir endpoints."""

from __future__ import annotations

import csv
import fcntl
import io
import json
import os
import re
import stat
import unicodedata
from collections import deque
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

MAX_SLUG = 48
MAX_ROWS = 20
MAX_CELL = 1000
MAX_RESULT_BYTES = 16_384
METADATA_COLUMNS = ["submitted_at", "submission_id"]


def form_slug(title):
    ascii_title = (
        unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode()
    )
    return (
        re.sub(r"[^a-z0-9]+", "-", ascii_title.lower())
        .strip("-")[:MAX_SLUG]
        .rstrip("-")
        or "form"
    )


def csv_cell(value):
    if isinstance(value, (list, bool)):
        value = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    text = "" if value is None else str(value)
    return "'" + text if text.startswith(("=", "+", "-", "@", "\t", "\r")) else text


@contextmanager
def _thread_directory(installation, scope, *, create):
    root = getattr(installation, "sandbox_workdirs_path", None)
    if root is None:
        raise ValueError(
            "Thread workdirs are not configured; form results cannot be saved"
        )
    # Scope comes from authenticated ownership checks, but never allow it to
    # turn into a path. Follow no symlink in the thread tree or CSV files.
    parts = (scope.room_id, scope.thread_id)
    if any(
        not part or part in {".", ".."} or "/" in part or "\\" in part for part in parts
    ):
        raise ValueError("Invalid form results thread scope")
    root = Path(root)
    if create:
        root.mkdir(parents=True, exist_ok=True)
    descriptors = []
    try:
        fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        descriptors.append(fd)
        for part in parts:
            if create:
                try:
                    os.mkdir(part, mode=0o700, dir_fd=fd)
                except FileExistsError:
                    pass
            fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            descriptors.append(fd)
        # Directory inode lock: serializes workers and threads without exposing
        # a lock file in the user's downloadable file list.
        fcntl.flock(fd, fcntl.LOCK_EX if create else fcntl.LOCK_SH)
        yield fd
    finally:
        for descriptor in reversed(descriptors):
            os.close(descriptor)


@contextmanager
def _csv_file(directory, filename, *, append=False):
    flags = os.O_RDWR | os.O_CREAT | os.O_APPEND if append else os.O_RDONLY
    descriptor = os.open(
        filename, flags | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600, dir_fd=directory
    )
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise ValueError("Form results must be a regular CSV file")
        stream = os.fdopen(
            descriptor, "a+" if append else "r", encoding="utf-8", newline=""
        )
    except BaseException:
        os.close(descriptor)
        raise
    with stream:
        yield stream


def _files(directory, slug):
    pattern = re.compile(re.escape(slug) + r"(?:-[0-9]+)?\.csv")
    return sorted(name for name in os.listdir(directory) if pattern.fullmatch(name))


def append_form_result(installation, scope, submission, record):
    """Save a validated submission; deduplicate on disk even after a restart."""
    intake = submission.userAction.name == "submit_intake"
    fields = (
        ["question", "districts", "acknowledged"]
        if intake
        else [field["name"] for field in record["fields"]]
    )
    values = (
        submission.userAction.context
        if intake
        else submission.userAction.context["values"]
    )
    slug = "intake" if intake else form_slug(record["title"])
    header = METADATA_COLUMNS + fields
    submission_id = csv_cell(submission.submissionId)
    with _thread_directory(installation, scope, create=True) as directory:
        filename = None
        candidates = set(_files(directory, slug))
        # IDs are unique across forms in a thread, including retries after a
        # row was flushed but the run input could not be committed.
        for existing in sorted(
            name
            for name in os.listdir(directory)
            if re.fullmatch(r"[a-z0-9-]+\.csv", name)
        ):
            with _csv_file(directory, existing) as source:
                reader = csv.reader(source)
                columns = next(reader, [])
                if columns[:2] != METADATA_COLUMNS:
                    continue
                for row in reader:
                    if len(row) > 1 and row[1] == submission_id:
                        return existing
                if (
                    existing in candidates
                    and columns == header
                    and (intake or existing != "intake.csv")
                ):
                    filename = filename or existing
        if filename is None:
            filename = f"{slug}.csv"
            suffix = 2
            while filename in os.listdir(directory) or (
                not intake and filename == "intake.csv"
            ):
                filename = f"{slug}-{suffix}.csv"
                suffix += 1
        with _csv_file(directory, filename, append=True) as target:
            output = io.StringIO(newline="")
            writer = csv.writer(output)
            if os.fstat(target.fileno()).st_size == 0:
                writer.writerow(header)
            writer.writerow(
                [
                    datetime.now(timezone.utc).isoformat(),
                    submission_id,
                    *[csv_cell(values.get(field)) for field in fields],
                ]
            )
            target.write(output.getvalue())
            target.flush()
            os.fsync(target.fileno())
        return filename


def read_form_results(installation, scope, title):
    """Count all rows; return at most 20 recent rows and 16 KiB of untrusted data."""
    result = {
        "kind": "untrusted_user_submitted_data",
        "row_count": 0,
        "files": [],
        "truncated": False,
    }
    try:
        with _thread_directory(installation, scope, create=False) as directory:
            for filename in _files(directory, form_slug(title)):
                with _csv_file(directory, filename) as source:
                    reader = csv.reader(source)
                    columns = next(reader, [])
                    if columns[:2] != METADATA_COLUMNS:
                        continue
                    count = 0
                    rows = deque(maxlen=MAX_ROWS)
                    for row in reader:
                        count += 1
                        if len(rows) == MAX_ROWS or any(
                            len(cell) > MAX_CELL for cell in row
                        ):
                            result["truncated"] = True
                        rows.append([cell[:MAX_CELL] for cell in row])
                result["row_count"] += count
                result["files"].append(
                    {
                        "filename": filename,
                        "row_count": count,
                        "columns": columns,
                        "rows": list(rows),
                    }
                )
    except FileNotFoundError:
        return result
    # Apply a global response bound even when a title has many schema variants.
    while len(json.dumps(result, ensure_ascii=False).encode()) > MAX_RESULT_BYTES:
        result["truncated"] = True
        populated = next((item for item in result["files"] if item["rows"]), None)
        if populated:
            populated["rows"].pop(0)
        else:
            result["files"].pop(0)
    return result
