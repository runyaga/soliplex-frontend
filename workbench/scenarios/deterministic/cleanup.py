"""Delete only the run's recorded thread ids using authenticated public storage."""
from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path


async def delete_created(storage, user, threads):
    for item in threads:
        await storage.delete_thread(user_name=user, room_id=item["room"], thread_id=item["thread_id"])


async def cleanup(config):
    from soliplex.cli.cli_util import get_installation
    from soliplex.agui.persistence import ThreadStorage
    from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

    installation = get_installation(Path(config.get("installation", "/environment")))
    installation.resolve_secrets()
    installation.resolve_environment()
    engine = create_async_engine(installation.thread_persistence_async_dburi, echo=False)
    try:
        # Separate transactions let cleanup continue if one thread disappeared.
        failed = 0
        for item in config["threads"]:
            try:
                async with AsyncSession(engine) as session, session.begin():
                    await delete_created(ThreadStorage(session), config["user"], [item])
            except Exception:
                failed += 1
        return failed
    finally:
        await engine.dispose()


if __name__ == "__main__":
    import contextlib
    import io
    import logging
    import warnings
    logging.disable(logging.CRITICAL)
    warnings.filterwarnings("ignore")
    try:
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            failed = asyncio.run(cleanup(globals().get("SCENARIO_CONFIG") or json.loads(sys.stdin.readline())))
        print(json.dumps({"failed": failed}))
        sys.exit(bool(failed))
    except Exception:
        sys.exit(1)
