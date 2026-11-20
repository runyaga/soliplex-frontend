import subprocess
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parents[2] / "src"


def _import_first(module: str) -> subprocess.CompletedProcess[str]:
    code = f"import sys; sys.path.insert(0, {str(SRC)!r}); import {module}"
    return subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, check=False)


def test_tools_module_imports_first_as_soliplex_resolves_it() -> None:
    result = _import_first("soliplex_a2ui_workbench.workbench_tools")
    assert result.returncode == 0, result.stderr


def test_templates_module_imports_first() -> None:
    result = _import_first("soliplex_a2ui_workbench.workbench_templates")
    assert result.returncode == 0, result.stderr
