"""Client app snapshots are data, never agent instructions or authority."""

import json

from ag_ui.core import UserMessage


def app_state_message(apps, projection):
    registered = {
        record["surfaceId"]
        for record in projection.content.values()
        if record["component"] == "PythonRepl"
    }
    if not isinstance(apps, dict) or len(apps) > 12 or not set(apps) <= registered:
        raise ValueError("Invalid program app snapshot")
    content = json.dumps(
        {
            "kind": "untrusted_user_submitted_data",
            "source": "current_program_apps",
            "apps": apps,
        },
        ensure_ascii=False,
        allow_nan=False,
    )
    if len(content.encode()) > 16_384:
        raise ValueError("Program app snapshot exceeds 16384 bytes")
    return UserMessage(id="current-program-apps", content=content)
