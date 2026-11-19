"""Model input for A2UI actions that arrive in ``forwardedProps.a2uiAction``.

An action-only run carries no new user message. The client sends the action
as ``forwardedProps.a2uiAction.userAction`` and names the last transcript
message at the start of its turn as ``afterMessageId``. The client resends
the same forwarded props on every run of the turn, continuations included.

:func:`with_user_action` places one user message for the action right after
that anchor, so the model reads the action once per run and before anything
it produced in reply. The message text is ``A2UI user action:`` plus the
action JSON, as ``soliplex_a2ui.apply_user_action`` writes it.

These pure helpers are retained for compatibility; no adapter is patched at
import time. Workbench submissions use :mod:`workbench_actions`.
"""

from __future__ import annotations

import hashlib
import json
from collections.abc import Sequence
from typing import Any

from ag_ui.core import Message, UserMessage

PREFIX = "A2UI user action: "
MAX_ACTION_CHARS = 30000


def user_action(forwarded_props: Any) -> dict | None:
    """The ``userAction`` object of ``forwarded_props``, when well formed."""
    if not isinstance(forwarded_props, dict):
        return None
    wrapper = forwarded_props.get("a2uiAction")
    if not isinstance(wrapper, dict):
        return None
    action = wrapper.get("userAction")
    if not isinstance(action, dict):
        return None
    for key in ("name", "surfaceId"):
        value = action.get(key)
        if not isinstance(value, str) or not value.strip():
            return None
    if not isinstance(action.get("context", {}), dict):
        return None
    return action


def action_message(action: dict) -> UserMessage:
    """The user message the model reads for ``action``."""
    text = json.dumps(action, sort_keys=True, ensure_ascii=False)
    digest = hashlib.sha256(text.encode()).hexdigest()[:24]
    return UserMessage(
        id=f"a2ui-action-{digest}",
        role="user",
        content=PREFIX + text[:MAX_ACTION_CHARS],
    )


def with_user_action(
    messages: Sequence[Message], forwarded_props: Any
) -> list[Message]:
    """``messages`` with the forwarded action placed once after its anchor.

    Without an action, or when a message with the action's id is present,
    the messages come back unchanged. An anchor missing from ``messages``
    places the action last.
    """
    result = list(messages)
    action = user_action(forwarded_props)
    if action is None:
        return result
    message = action_message(action)
    if any(m.id == message.id for m in result):
        return result
    anchor = forwarded_props["a2uiAction"].get("afterMessageId")
    index = next(
        (i + 1 for i, m in enumerate(result) if m.id == anchor),
        len(result),
    )
    result.insert(index, message)
    return result




