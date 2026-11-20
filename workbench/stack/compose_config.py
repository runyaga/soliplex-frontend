"""Pure Compose transformation shared by setup-stack.sh and its unit tests."""

from __future__ import annotations

from typing import Any


WORKBENCH_DB_PATH = "/data/workbench/workbench.sqlite3"
WORKBENCH_DATA_TARGET = "/data/workbench"


def configure_workbench_storage(compose: dict[str, Any]) -> dict[str, Any]:
    """Persist the package database and pass explicit room/path configuration."""
    services = compose.setdefault("services", {})
    backend = services.get("backend")
    if not isinstance(backend, dict):
        raise ValueError("generated Compose has no backend service")
    volumes = backend.setdefault("volumes", [])
    if not any(
        isinstance(item, dict) and item.get("target") == WORKBENCH_DATA_TARGET
        for item in volumes
    ):
        volumes.append({"type": "volume", "source": "workbench_data", "target": WORKBENCH_DATA_TARGET})
    environment = backend.setdefault("environment", {})
    if isinstance(environment, list):
        environment = {item.split("=", 1)[0]: item.split("=", 1)[1] if "=" in item else None for item in environment}
        backend["environment"] = environment
    if not isinstance(environment, dict):
        raise ValueError("backend environment must be a mapping or list")
    environment["SOLIPLEX_WORKBENCH_DB"] = WORKBENCH_DB_PATH
    environment["SOLIPLEX_WORKBENCH_ROOMS"] = "${SOLIPLEX_WORKBENCH_ROOMS:-}"
    compose.setdefault("volumes", {})["workbench_data"] = {}
    return compose
