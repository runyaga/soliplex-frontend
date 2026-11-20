"""Importing the legacy lab module must not change the process-global adapter."""

import importlib
import inspect

from pydantic_ai.ui.ag_ui import _adapter


def test_lab_import_does_not_install_global_agui_adapter_reader():
    adapter = _adapter.AGUIAdapter
    before = inspect.getattr_static(adapter, "messages")
    importlib.import_module("soliplex_a2ui_workbench.a2ui_lab")
    after = inspect.getattr_static(adapter, "messages")
    assert after is before
    assert not hasattr(adapter, "_soliplex_a2ui_lab_action")
