from soliplex_a2ui_workbench.workbench_repository import SQLiteWorkbenchRepository, default_layout
from soliplex_a2ui_workbench.workbench_schemas import LayoutSnapshot


def test_default_layout_is_a_valid_frozen_snapshot() -> None:
    LayoutSnapshot.model_validate(default_layout(), context={"authenticated_program_surfaces": set()})


def test_new_thread_snapshot_carries_the_default_layout(tmp_path) -> None:
    from soliplex_a2ui_workbench.workbench_repository import WorkbenchScope
    repo = SQLiteWorkbenchRepository(tmp_path / "wb.sqlite3")
    scope = WorkbenchScope(actor_id="alice", server_id="server", room_id="room-a", thread_id="thread-new")
    snapshot = repo.load_snapshot(scope)
    assert snapshot["revision"] == 0
    assert snapshot["layout"] == default_layout()
