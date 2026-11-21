# Fix the misspelled builtin to show the total cost of three tickets.
tickets = 3
price = 8
prnt(f"Ticket total: {tickets * price}")  # noqa: F821 - deliberate repair example
