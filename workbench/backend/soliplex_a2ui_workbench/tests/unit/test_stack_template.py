"""Generated Compose persistence wiring used by the stack setup template."""

import importlib.util
import sqlite3
from pathlib import Path


def test_generated_backend_compose_mounts_named_workbench_volume(tmp_path):
    helper = Path(__file__).parents[4] / "stack/compose_config.py"
    script = helper.parent / "setup-stack.sh"
    assert "from compose_config import configure_workbench_storage" in script.read_text()
    assert "configure_workbench_storage(compose)" in script.read_text()
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
    assert backend["environment"]["SOLIPLEX_WORKBENCH_ROOMS"] == "${SOLIPLEX_WORKBENCH_ROOMS:-a2ui-lab,a2ui-lab-e4b}"
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
