"""Offline checks of scripted operations, with no backend imports or model."""

import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "seed", Path(__file__).resolve().parents[1] / "deterministic" / "seed.py"
)
seed = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(seed)


class RecipesTest(unittest.IsolatedAsyncioTestCase):
    async def test_replacement_uses_repair_on_the_original_program(self):
        calls = []
        async def call(tool, **arguments):
            calls.append((tool, arguments))
            return {"nodeId": f"node-{len(calls)}"}
        await seed.scripted_tools("fix_program_in_window", call)
        self.assertEqual([tool for tool, _ in calls], ["create_container", "run_python_client", "repair_program"])
        self.assertEqual(calls[-1][1], {"node_id": "node-2", "source": seed.FIXED_SOURCE})

    async def test_reload_fixture_matches_original_form_sequence(self):
        sequences = []
        for name in ("form_in_left_sidebar", "reload_replay"):
            calls = []

            async def call(tool, calls=calls, **arguments):
                calls.append((tool, arguments))

            await seed.scripted_tools(name, call)
            sequences.append(calls)
        self.assertEqual(sequences[0], sequences[1])

    async def test_unknown_scenario_is_rejected(self):
        with self.assertRaises(ValueError):
            await seed.scripted_tools("invented", None)


if __name__ == "__main__":
    unittest.main()
