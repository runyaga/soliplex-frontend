"""Server-owned workbench run-result event sink."""

from __future__ import annotations

from collections.abc import Mapping


class LogfireTraceSink:
    """Emit bounded accepted run-result tags through the configured Logfire SDK."""

    def emit(self, event: Mapping[str, object]) -> None:
        import logfire

        logfire.info("workbench client Python run result", **dict(event))
