# ruff: noqa: F821
# Independent checker; case is literal data.
import json

import ui.workbench


def calculate(events, start=1, queue=0, capacity=10, retries=True):
    values = []
    for tick in range(start, 13):
        incoming = 6 + (min(queue, 8) if retries else 0)
        service = capacity
        for event in events:
            if event["kind"] == "capacity" and event["tick"] == tick:
                service = event["value"]
        queue = max(queue + incoming - service, 0)
        values.append(queue)
    return values


observed = calculate(case["tape"])
branches = [
    calculate(case["tape"], 6, observed[4], 10),
    calculate(case["tape"], 6, observed[4], 12),
    calculate(case["tape"], 6, observed[4], 10, False),
]
clears = [i + 6 for i, value in enumerate(branches[2]) if value == 0]
cleared = clears[0] if clears else None
winners = []
for mask in range(2 ** len(case["tape"])):
    subset = [e for i, e in enumerate(case["tape"]) if (mask // (2**i)) % 2]
    if calculate(subset)[-1] >= 32:
        winners.append(subset)
minimum = min(winners, key=len) if winners else []
results = {
    "observed": observed,
    "restore_final_backlog": branches[0][-1],
    "capacity_final_backlog": branches[1][-1],
    "retry_disabled_final_backlog": branches[2][-1],
    "cleared_at_tick": cleared,
    "minimal_trigger": [e["id"] for e in minimum],
}
passed = (
    case["reducer_version"] == "queue-v1"
    and case["verifier_revision"] == "independent-v1"
    and case["checkpoint"]
    == {
        "before_tick": 6,
        "backlog": observed[4],
        "pending_retries": min(observed[4], 8),
    }
    and case["expected"] == results
)
receipt = {
    "status": "pass" if passed else "failed",
    "case": case,
    "results": results,
    "verifier_revision": "independent-v1",
}
ui.workbench.write_file("replay-verification.json", json.dumps(receipt))
assert passed, "Replay verification failed: captured expectations differ"
print("Verified independent-v1 / queue-v1:", json.dumps(results))
