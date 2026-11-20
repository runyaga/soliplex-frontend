"""The workbench routes serve the paths soliplex_client's WorkbenchClient calls."""
import pytest

pytest.importorskip("soliplex")

from soliplex_a2ui_workbench.views import router  # noqa: E402

# Mounted under the installation prefix /api, these become /api/v1/...
CLIENT_PATHS = {
    ("GET", "/v1/rooms/{room_id}/threads/{thread_id}/workbench"),
    ("POST", "/v1/rooms/{room_id}/threads/{thread_id}/workbench/actions"),
    ("POST", "/v1/rooms/{room_id}/threads/{thread_id}/workbench/actions/restore"),
}


def test_workbench_routes_match_client_paths() -> None:
    served = {(method, route.path) for route in router.routes for method in getattr(route, "methods", set())}
    assert CLIENT_PATHS <= served, sorted(served)
