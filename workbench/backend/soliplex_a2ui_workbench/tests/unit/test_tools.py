"""Tests for :mod:`soliplex_a2ui_workbench.tools`."""

from soliplex_a2ui_workbench import tools


def test_greeting_includes_name():
    result = tools.greeting("Ada")

    assert "Ada" in result
