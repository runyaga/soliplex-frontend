"""Optional offline seam check with installed backend deps and in-memory SQLite."""

import importlib.util
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

try:
    from pydantic_ai import ToolReturn
    from soliplex.agui.persistence import ThreadStorage
    from soliplex.agui.schema import metadata
    from soliplex_a2ui_workbench import workbench_agent_tools as wrappers
    from soliplex_a2ui_workbench.workbench_projection import RunWorkbenchProjection
    from soliplex_a2ui_workbench.workbench_routes import workbench_scope
    from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

    BACKEND_AVAILABLE = True
except ModuleNotFoundError:
    BACKEND_AVAILABLE = False

SPEC = importlib.util.spec_from_file_location(
    "scenario_seed", Path(__file__).resolve().parents[1] / "deterministic" / "seed.py"
)
seed = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(seed)


@unittest.skipUnless(
    BACKEND_AVAILABLE, "Optional installed backend dependencies required"
)
class SeedPersistenceTest(unittest.IsolatedAsyncioTestCase):
    async def test_all_scenarios_persist_unmodified_real_wrapper_events_and_replay(
        self,
    ):
        engine = create_async_engine("sqlite+aiosqlite:///:memory:")
        config = {
            "user": "scenario-fixture",
            "email": "@".join(("scenario", "example.invalid")),
            "room": "workbench",
        }
        installation = SimpleNamespace(server_id="offline-scenarios")
        try:
            async with engine.begin() as connection:
                await connection.run_sync(metadata.create_all)
            for name in seed.SCENARIOS:
                with self.subTest(scenario=name):
                    emitted = []
                    original = wrappers._call

                    async def capture(
                        function, ctx, original=original, emitted=emitted, **kwargs
                    ):
                        result = await original(function, ctx, **kwargs)
                        if isinstance(result, ToolReturn):
                            emitted.extend(
                                event.model_dump(mode="json")
                                for event in result.metadata
                            )
                        return result

                    with (
                        patch.dict(
                            "os.environ", {"SOLIPLEX_WORKBENCH_ROOMS": "workbench"}
                        ),
                        patch.object(wrappers, "_call", capture),
                    ):
                        thread_id = await seed.seed_one(
                            config, installation, engine, name
                        )
                    async with AsyncSession(engine) as session:
                        thread = await ThreadStorage(session).get_thread(
                            user_name=config["user"],
                            room_id=config["room"],
                            thread_id=thread_id,
                        )
                        runs = await thread.list_runs()
                        self.assertEqual(len(runs), 1)
                        self.assertIsNotNone(runs[0].finished)
                        stored = await runs[0].list_events()
                        self.assertEqual(stored[0].type, "RUN_STARTED")
                        self.assertEqual(stored[-1].type, "RUN_FINISHED")
                        self.assertEqual(
                            [event.model_dump(mode="json") for event in stored[1:-1]],
                            emitted,
                        )
                    scope = workbench_scope(
                        installation, config["user"], config["room"], thread_id
                    )
                    replay = RunWorkbenchProjection(scope, stored)
                    self.assertGreater(replay.layout["layoutRevision"], 0)
                    self.assertTrue(replay.content)
                    if name == "fix_program_in_window":
                        window = next(
                            node
                            for node in replay.layout["nodes"]
                            if node["kind"] == "window"
                        )
                        visible_sources = []
                        for node in replay.layout["nodes"]:
                            if node["id"] in window["children"]:
                                visible_sources.append(
                                    replay.content[
                                        node["payload"]["activityMessageId"]
                                    ]["source"]
                                )
                        self.assertEqual(visible_sources, [seed.FIXED_SOURCE])
        finally:
            await engine.dispose()


if __name__ == "__main__":
    unittest.main()
