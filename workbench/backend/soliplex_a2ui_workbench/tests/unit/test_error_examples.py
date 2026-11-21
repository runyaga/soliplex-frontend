"""Each deliberate error has a one-line repair and a result tied to that repair."""

import contextlib
import io
from pathlib import Path

import pytest

BASE = Path(__file__).parents[2] / "src/soliplex_a2ui_workbench"


@pytest.mark.parametrize(
    "filename,error,before,after,expected",
    [
        (
            "type_check_demo.py",
            TypeError,
            'value + "1"',
            "value + 1",
            "Stock after delivery: 4\n",
        ),
        (
            "name_error_demo.py",
            NameError,
            "prnt(",
            "print(",
            "Ticket total: 24\n",
        ),
        (
            "syntax_error_demo.py.txt",
            SyntaxError,
            'print(f"Route distance: {sum(legs)} km"',
            'print(f"Route distance: {sum(legs)} km")',
            "Route distance: 14 km\n",
        ),
    ],
)
def test_examples_require_the_repair(filename, error, before, after, expected):
    source = (BASE / filename).read_text()
    with pytest.raises(error):
        exec(source, {})  # noqa: S102 - curated repository example
    assert source.count(before) == 1
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        exec(source.replace(before, after), {})  # noqa: S102 - one-line curated repair
    assert output.getvalue() == expected


def test_deleting_broken_function_does_not_repair_type_example():
    source = (BASE / "type_check_demo.py").read_text()
    body = source[source.index('print(f"Stock') :]
    with pytest.raises(NameError, match="add_one"):
        exec(body, {})  # noqa: S102 - curated example with its function removed
