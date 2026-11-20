"""Pure Compose transformation shared by setup-stack.sh and its unit tests."""

from __future__ import annotations

import shutil
import tomllib
from typing import Any
from pathlib import Path

import yaml


WORKBENCH_DB_PATH = "/data/workbench/workbench.sqlite3"
WORKBENCH_DATA_TARGET = "/data/workbench"
WORKBENCH_WORKDIRS_PATH = "/data/workbench/workdirs"


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


def install_workbench_backend(target: str | Path, source_project: str | Path) -> str:
    """Copy this local Python project into generated src and wire its router."""
    generated = Path(target)
    source = Path(source_project)
    metadata_path = source / "pyproject.toml"
    package_path = source / "src" / "soliplex_a2ui_workbench"
    router_file = package_path / "workbench_routes.py"
    if not metadata_path.is_file() or not router_file.is_file():
        raise ValueError("workbench backend source is incomplete; guarded router was not configured")
    metadata = tomllib.loads(metadata_path.read_text())
    dependencies = metadata.get("project", {}).get("dependencies", [])
    if not dependencies or not all(isinstance(item, str) and item.strip() for item in dependencies):
        raise ValueError("workbench backend runtime dependencies are missing")

    destination = generated / "src" / "soliplex_a2ui_workbench"
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(metadata_path, destination / "pyproject.toml")
    shutil.copytree(package_path, destination / "src" / "soliplex_a2ui_workbench", dirs_exist_ok=True)

    requirements_path = generated / "backend" / "requirements.txt"
    if not requirements_path.is_file():
        raise ValueError("generated backend requirements.txt is missing")
    requirements = requirements_path.read_text()
    existing_requirements = {line.strip().lower() for line in requirements.splitlines() if line.strip() and not line.lstrip().startswith("#")}
    additions = [dependency for dependency in dependencies if dependency.strip().lower() not in existing_requirements]
    if additions:
        with requirements_path.open("a") as output:
            if requirements and not requirements.endswith("\n"):
                output.write("\n")
            output.write("\n# Runtime dependencies for the local workbench backend package.\n")
            output.writelines(f"{dependency}\n" for dependency in additions)

    router_name = "soliplex_a2ui_workbench.workbench_routes.guarded_router"
    installed_router = destination / "src" / "soliplex_a2ui_workbench" / "workbench_routes.py"
    if not installed_router.is_file():
        raise ValueError("workbench backend package install failed; guarded router was not configured")
    installation_path = generated / "backend" / "environment" / "installation.yaml"
    if not installation_path.is_file():
        raise ValueError("generated installation.yaml is missing")
    installation = yaml.safe_load(installation_path.read_text()) or {}
    installation.setdefault("sandbox_config", {"environments_path": "environments"})["workdirs_path"] = WORKBENCH_WORKDIRS_PATH
    operations = installation.setdefault("app_router_operations", [])
    operations[:] = [item for item in operations if item.get("group_name") != "agui"]
    operations.append({
        "kind": "add",
        "group_name": "agui",
        "router_name": router_name,
        "replace_existing": True,
        "prefix": "/api",
    })
    installation_path.write_text(yaml.safe_dump(installation, sort_keys=False))
    return router_name
