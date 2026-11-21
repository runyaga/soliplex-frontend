# Repair the return expression: adding one item must produce a number.
def add_one(value: int) -> int:
    return value + "1"


print(f"Stock after delivery: {add_one(3)}")
