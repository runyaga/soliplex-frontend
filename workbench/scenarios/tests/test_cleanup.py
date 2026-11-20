"""Cleanup uses only recorded identities, with no enumeration or SQL deletes."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("cleanup", Path(__file__).parents[1] / "deterministic/cleanup.py")
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)


class CleanupTest(unittest.IsolatedAsyncioTestCase):
    async def test_only_recorded_threads_are_deleted_with_owner_and_room(self):
        calls = []
        class Storage:
            async def delete_thread(self, **kwargs):
                calls.append(kwargs)
        await cleanup.delete_created(Storage(), "owner", [{"room": "workbench", "thread_id": "id-one"}, {"room": "workbench-e4b", "thread_id": "id-two"}])
        self.assertEqual(calls, [
            {"user_name": "owner", "room_id": "workbench", "thread_id": "id-one"},
            {"user_name": "owner", "room_id": "workbench-e4b", "thread_id": "id-two"},
        ])

    async def test_public_storage_deletion_leaves_an_unrecorded_thread(self):
        from soliplex.agui.persistence import ThreadStorage
        from soliplex.agui.schema import metadata
        from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
        engine = create_async_engine('sqlite+aiosqlite:///:memory:')
        try:
            async with engine.begin() as connection:
                await connection.run_sync(metadata.create_all)
            async with AsyncSession(engine, expire_on_commit=False) as session:
                storage = ThreadStorage(session)
                threads = [await storage.new_thread(user_name='owner', email='@'.join(('owner', 'example.invalid')), room_id='workbench') for _ in range(3)]
                ids = [thread.thread_id for thread in threads]
                await session.commit()
                await cleanup.delete_created(storage, 'owner', [{'room':'workbench', 'thread_id':id_} for id_ in ids[:2]])
                await session.commit()
                retained = await storage.get_thread(user_name='owner', room_id='workbench', thread_id=ids[2])
                self.assertEqual(retained.thread_id, ids[2])
                for id_ in ids[:2]:
                    with self.assertRaises(Exception):
                        await storage.get_thread(user_name='owner', room_id='workbench', thread_id=id_)
        finally:
            await engine.dispose()
