# This function is never called: unchecked execution succeeds.
# Fix its return expression so the type checker accepts the whole program.
def add_one(value: int) -> int:
    return value + "1"

print(pow(7, 12345, 1000003))
