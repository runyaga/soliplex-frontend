"""Bounded UTF-8 files in the authenticated thread's existing sandbox workdir."""

from __future__ import annotations

import csv
import io
import os
import re
import secrets
import stat

from .workbench_form_results import METADATA_COLUMNS, _thread_directory

MAX_BYTES = 8 * 1024 * 1024
# JSON may escape each UTF-8 byte as six ASCII bytes (e.g. \u0000),
# plus the filename and object framing. The decoded text is checked separately.
MAX_REQUEST_BYTES = 6 * MAX_BYTES + 1024
_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,79}\.(?:csv|md|txt|json)")


def _name(filename):
    if not isinstance(filename, str) or not _NAME.fullmatch(filename):
        raise ValueError("Use a plain filename with extension .csv, .md, .txt or .json")


def _read(directory, filename):
    descriptor = os.open(
        filename, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory
    )
    with os.fdopen(descriptor, "rb") as source:
        info = os.fstat(source.fileno())
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_nlink != 1
            or info.st_size > MAX_BYTES
        ):
            raise ValueError(
                f"File must be a regular, unlinked file of at most {MAX_BYTES} bytes"
            )
        content = source.read(MAX_BYTES + 1)
        if len(content) > MAX_BYTES:
            raise ValueError(f"File exceeds {MAX_BYTES} bytes")
        return content.decode("utf-8")


def read_file(installation, scope, filename):
    """Missing files are empty, so a new app can start without a saved file."""
    _name(filename)
    try:
        with _thread_directory(installation, scope, create=False) as directory:
            return _read(directory, filename)
    except FileNotFoundError:
        return ""


def write_file(installation, scope, filename, text):
    """Atomic replacement under the form writer's directory lock; never edit receipts."""
    _name(filename)
    if not isinstance(text, str) or len(text.encode("utf-8")) > MAX_BYTES:
        raise ValueError(f"Write exceeds {MAX_BYTES} UTF-8 bytes")
    # read_form_results trusts the metadata header as server-validated rows.
    if (
        filename.endswith(".csv")
        and next(csv.reader(io.StringIO(text)), [])[:2] == METADATA_COLUMNS
    ):
        raise ValueError("Programs cannot write form-result columns; rename them")
    with _thread_directory(installation, scope, create=True) as directory:
        try:
            existing = _read(directory, filename)
        except FileNotFoundError:
            existing = None
        if (
            filename.endswith(".csv")
            and existing is not None
            and next(csv.reader(io.StringIO(existing)), [])[:2] == METADATA_COLUMNS
        ):
            raise ValueError("Validated form CSVs are read-only to programs")
        temporary = ".program-" + secrets.token_hex(16)
        descriptor = os.open(
            temporary,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
            dir_fd=directory,
        )
        try:
            with os.fdopen(descriptor, "wb") as target:
                target.write(text.encode("utf-8"))
                target.flush()
                os.fsync(target.fileno())
            os.replace(temporary, filename, src_dir_fd=directory, dst_dir_fd=directory)
            os.fsync(directory)
        finally:
            try:
                os.unlink(temporary, dir_fd=directory)
            except FileNotFoundError:
                pass
