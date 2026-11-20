# Fix the misspelled builtin, then read the value from the run log.
prnt(pow(7, 12345, 1000003))  # noqa: F821 - deliberate repair example
