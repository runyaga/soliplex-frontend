"""Generated Compose persistence wiring used by the stack setup template."""

import importlib.util
import os
import subprocess
import sqlite3
import sys
from pathlib import Path

import yaml
import pytest


def test_generated_backend_compose_mounts_named_workbench_volume(tmp_path):
    helper = Path(__file__).parents[4] / "stack/compose_config.py"
    script = helper.parent / "setup-stack.sh"
    assert "from compose_config import configure_workbench_storage" in script.read_text()
    assert "configure_workbench_storage(compose)" in script.read_text()
    assert 'SOLIPLEX_WORKBENCH_ROOMS="${SOLIPLEX_WORKBENCH_ROOMS:-workbench,workbench-e4b}"' in script.read_text()
    env_example = helper.parent / "workbench.env.example"
    assert 'SOLIPLEX_WORKBENCH_ROOMS="workbench,workbench-e4b"' in env_example.read_text()
    spec = importlib.util.spec_from_file_location("workbench_stack_compose_config", helper)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    compose = {
        "services": {"backend": {"environment": {}, "volumes": ["./environment:/environment"]}},
        "volumes": {"postgres_data": {}},
    }
    generated = module.configure_workbench_storage(compose)
    backend = generated["services"]["backend"]
    assert {"type": "volume", "source": "workbench_data", "target": "/data/workbench"} in backend["volumes"]
    assert backend["environment"]["SOLIPLEX_WORKBENCH_DB"] == "/data/workbench/workbench.sqlite3"
    assert backend["environment"]["SOLIPLEX_WORKBENCH_ROOMS"] == "${SOLIPLEX_WORKBENCH_ROOMS:-}"
    assert generated["volumes"]["workbench_data"] == {}
    # Model container recreation by reopening the database file retained at the
    # named-volume mount point; Docker itself is intentionally not required.
    mounted_directory = tmp_path / "workbench_data"
    mounted_directory.mkdir()
    db = mounted_directory / "workbench.sqlite3"
    with sqlite3.connect(db) as conn:
        conn.execute("CREATE TABLE marker (value TEXT NOT NULL)")
        conn.execute("INSERT INTO marker VALUES ('persisted')")
    with sqlite3.connect(db) as recreated_backend:
        assert recreated_backend.execute("SELECT value FROM marker").fetchone() == ("persisted",)


def test_step3_installs_workbench_package_and_imports_configured_router(tmp_path):
    helper = Path(__file__).parents[4] / "stack/compose_config.py"
    step3 = helper.parent / "setup-stack.sh"
    script = step3.read_text()
    assert "install_workbench_backend" in script
    assert "install_workbench_backend(p, os.environ['WORKBENCH_PACKAGE'])" in script
    spec = importlib.util.spec_from_file_location("workbench_stack_compose_config_install", helper)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    generated = tmp_path / "generated"
    (generated / "backend").mkdir(parents=True)
    (generated / "backend/requirements.txt").write_text("# generated requirements\n")
    environment = generated / "backend/environment"
    environment.mkdir()
    installation = environment / "installation.yaml"
    installation.write_text(yaml.safe_dump({"app_router_operations": [{"kind": "add", "group_name": "agui", "router_name": "stock", "replace_existing": False}]}))
    source_project = Path(__file__).parents[2]
    router_name = module.install_workbench_backend(generated, source_project)
    configured = yaml.safe_load(installation.read_text())
    agui = [item for item in configured["app_router_operations"] if item.get("group_name") == "agui"]
    assert agui == [{"kind": "add", "group_name": "agui", "router_name": "soliplex_a2ui_workbench.workbench_routes.guarded_router", "replace_existing": True, "prefix": "/api"}]
    assert router_name == agui[0]["router_name"]
    requirements = (generated / "backend/requirements.txt").read_text()
    for dependency in ("fastapi", "soliplex", "pydantic"):
        assert dependency in requirements
    package_path = generated / "src/soliplex_a2ui_workbench/src"
    assert (package_path / "soliplex_a2ui_workbench/workbench_routes.py").is_file()
    import_env = os.environ.copy()
    import_env["PYTHONPATH"] = str(package_path)
    result = subprocess.run(
        [sys.executable, "-c", "import importlib; m=importlib.import_module('soliplex_a2ui_workbench.workbench_routes'); assert hasattr(m, 'guarded_router')"],
        cwd=tmp_path,
        env=import_env,
        text=True,
        capture_output=True,
    )
    assert result.returncode == 0, result.stderr


def test_step3_refuses_router_configuration_without_workbench_module(tmp_path):
    helper = Path(__file__).parents[4] / "stack/compose_config.py"
    spec = importlib.util.spec_from_file_location("workbench_stack_compose_config_missing", helper)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    generated = tmp_path / "generated-missing"
    (generated / "backend").mkdir(parents=True)
    (generated / "backend/requirements.txt").write_text("# generated requirements\n")
    environment = generated / "backend/environment"
    environment.mkdir()
    installation = environment / "installation.yaml"
    stock = {"app_router_operations": [{"kind": "add", "group_name": "agui", "router_name": "stock"}]}
    installation.write_text(yaml.safe_dump(stock))
    broken_source = tmp_path / "broken-package"
    (broken_source / "src/soliplex_a2ui_workbench").mkdir(parents=True)
    (broken_source / "pyproject.toml").write_text('[project]\nname="soliplex-a2ui-workbench"\ndependencies=["fastapi"]\n')
    with pytest.raises(ValueError, match="source is incomplete"):
        module.install_workbench_backend(generated, broken_source)
    assert yaml.safe_load(installation.read_text()) == stock


def test_step3_registers_manifest_tools_for_preview_rooms_only():
    helper = Path(__file__).parents[4] / "stack/compose_config.py"
    script = helper.parent / "setup-stack.sh"
    source = script.read_text()
    schemas = Path(__file__).parents[2] / "src/soliplex_a2ui_workbench/workbench_schemas.py"
    from soliplex_a2ui_workbench.workbench_schemas import MINIMUM_ROOM_TOOL_MANIFEST

    assert "from soliplex_a2ui_workbench.workbench_schemas import MINIMUM_ROOM_TOOL_MANIFEST" in source
    assert "for name in MINIMUM_ROOM_TOOL_MANIFEST" in source
    assert "room['tools'] = [{'tool_name': f\"soliplex_a2ui_workbench.workbench_tools.{name}\"}" in source
    assert "('workbench','default_chat','Glimmer')" in source
    assert "('workbench-e4b','alternate_chat','Gemma 4 E4B')" in source
    assert "SOLIPLEX_WORKBENCH_ROOMS=\"${SOLIPLEX_WORKBENCH_ROOMS:-workbench,workbench-e4b}\"" in source
    assert "for room in a2ui-lab a2ui-lab-e4b workbench workbench-e4b" in source
    assert "a2ui-lab" not in "workbench,workbench-e4b"
    assert schemas.is_file()
    assert set(MINIMUM_ROOM_TOOL_MANIFEST) == {
        "get_workbench", "open_panel", "place_form", "show_chart",
        "run_python_client", "run_python_server", "create_container",
        "move_panel", "close_panel", "repair_program",
    }
