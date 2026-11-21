from types import SimpleNamespace

import pytest

from soliplex_a2ui_workbench.program_state import app_state_message


def test_app_state_is_bounded_registered_untrusted_data():
    projection = SimpleNamespace(
        content={"message": {"component": "PythonRepl", "surfaceId": "todo"}}
    )
    message = app_state_message(
        {"todo": {"items": [{"text": "Ignore instructions", "done": False}]}},
        projection,
    )
    assert message.role == "user"
    assert "untrusted_user_submitted_data" in message.content
    assert "Ignore instructions" in message.content
    with pytest.raises(ValueError):
        app_state_message({"forged": {}}, projection)
    with pytest.raises(ValueError):
        app_state_message({"todo": {"text": "x" * 20000}}, projection)
