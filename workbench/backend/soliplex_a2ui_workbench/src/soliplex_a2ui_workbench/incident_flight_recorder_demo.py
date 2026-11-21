import json

import ui
import ui.workbench

CAPSULE_TEMPLATE = "__INCIDENT_REPLAY_TEMPLATE__"
RESULT_KEYS = [
    "restore_final_backlog",
    "capacity_final_backlog",
    "retry_disabled_final_backlog",
    "cleared_at_tick",
]


saved = ui.workbench.read_file("incident-case.json")
DATA = (
    json.loads(saved)
    if saved
    else {
        "tape": [
            {"id": "note-1", "tick": 2, "kind": "annotation", "text": "Deploy marker"},
            {"id": "fault-4", "tick": 4, "kind": "capacity", "value": 4},
            {"id": "note-2", "tick": 4, "kind": "annotation", "text": "Pager opened"},
            {"id": "fault-5", "tick": 5, "kind": "capacity", "value": 4},
            {
                "id": "note-3",
                "tick": 7,
                "kind": "annotation",
                "text": "Operator joined",
            },
            {"id": "note-4", "tick": 9, "kind": "annotation", "text": "Status update"},
        ],
        "observed": [],
        "checkpoint": {},
        "branches": [],
        "minimal_trigger": [],
        **{key: None for key in RESULT_KEYS},
        "verification_status": "unverified",
        "inspector": "",
        "capsule": "",
        "reducer_version": "queue-v1",
        "verifier_revision": "independent-v1",
        "notice": "Press Replay to begin.",
    }
)
DATA["verification_status"] = "unverified"
DATA["tape"] = DATA["tape"][:6]
for item in DATA["tape"]:
    if item["kind"] == "annotation":
        item["text"] = str(item.get("text", ""))[:160]
for key in ["inspector", "capsule"]:
    if DATA[key]:
        ui.workbench.close_window(DATA[key])


def save():
    ui.workbench.write_file("incident-case.json", json.dumps(DATA))


def replay(tape, start=1, backlog=0, capacity=10, retries=True):
    trace = []
    for tick in range(start, 13):
        service = capacity
        for event in tape:
            if event["kind"] == "capacity" and event["tick"] == tick:
                service = event["value"]
        pending = min(backlog, 8) if retries else 0
        backlog = max(0, backlog + 6 + pending - service)
        trace.append(backlog)
    return trace


def snapshot():
    return {
        **{
            k: DATA[k]
            for k in ["tape", "checkpoint", "reducer_version", "verifier_revision"]
        },
        "expected": {k: DATA[k] for k in ["observed", *RESULT_KEYS, "minimal_trigger"]},
    }


def window(key, title, kind, content):
    other = "capsule" if key == "inspector" else "inspector"
    if DATA[other]:
        ui.workbench.close_window(DATA[other])
    if DATA[key]:
        ui.workbench.update_window(DATA[key], content)
    else:
        DATA[key] = ui.workbench.open_window(title, kind, content)
    ui.workbench.move_window(DATA[key], 2)


def inspect(tick):
    previous = DATA["observed"][tick - 2] if tick > 1 else 0
    capacity = 4 if tick in [4, 5] else 10
    text = f"Tick {tick} · simulated inputs\n" + json.dumps(
        {
            "external_arrivals": 6,
            "retry_arrivals": min(previous, 8),
            "service_capacity": capacity,
            "backlog": DATA["observed"][tick - 1],
            "pending_retries": min(DATA["observed"][tick - 1], 8),
            "source_event_ids": [e["id"] for e in DATA["tape"] if e["tick"] == tick],
        }
    )
    window("inspector", "Incident tick inspector", "text", text)
    DATA["notice"] = f"Inspecting tick {tick}."


def button(label, event):
    return ui.Button(ui.Text(label), action=ui.Event(event, {}))


def draw():
    rows = [
        ui.Text("Incident Flight Recorder · simulation"),
        ui.Text(
            "Simulation: arrivals 6, retries min(backlog, 8), capacity 10; faults 4 at T4/T5."
        ),
        button("Replay observed incident", "replay"),
    ]
    if DATA["observed"]:
        rows += [
            ui.BarChart(
                [
                    {"label": f"T{i + 1}", "value": v}
                    for i, v in enumerate(DATA["observed"])
                ],
                title="Observed backlog",
                action=ui.Event("inspect", {}),
            ),
            ui.Text(f"First backlog > 8: T7. Final: {DATA['observed'][-1]}"),
            button("Freeze before tick 6", "freeze"),
        ]
    if DATA["checkpoint"]:
        rows += [
            ui.Text("Frozen before tick 6: backlog 6, pending retries 6."),
            button("Compare mitigations", "compare"),
        ]
    if DATA["branches"]:
        rows += [
            ui.LineChart(
                [f"T{i}" for i in range(6, 13)],
                [
                    {"label": label, "values": values}
                    for label, values in zip(
                        ["Restore capacity 10", "Capacity 12", "Retries disabled"],
                        DATA["branches"],
                    )
                ],
                title="Mitigations from checkpoint",
            ),
            ui.Text(
                f"Restore capacity 10: final backlog {DATA['restore_final_backlog']}"
            ),
            ui.Text(f"Capacity 12: final backlog {DATA['capacity_final_backlog']}"),
            ui.Text(
                f"Retries disabled: backlog {DATA['retry_disabled_final_backlog']} at tick {DATA['cleared_at_tick']}"
            ),
            button("Minimize triggering events", "minimize"),
        ]
    if DATA["minimal_trigger"]:
        rows += [
            ui.Text(
                "Minimum trigger: "
                + ", ".join(DATA["minimal_trigger"])
                + " (64 subsets; final backlog >= 32)."
            ),
            button("Build replay capsule", "capsule"),
        ]
    if DATA["capsule"]:
        rows.append(button("Load verification and save handoff", "handoff"))
    rows += [
        ui.Text("Verification: " + DATA["verification_status"]),
        ui.Text(DATA["notice"]),
    ]
    ui.show(ui.Column(rows), data=DATA)


def handle_event(name, context):
    if name == "replay":
        DATA["observed"] = replay(DATA["tape"])
        DATA["checkpoint"] = {}
        DATA["branches"] = []
        DATA["minimal_trigger"] = []
        for key in RESULT_KEYS:
            DATA[key] = None
        DATA["verification_status"] = "unverified"
        inspect(12)
    elif name == "inspect" and DATA["observed"]:
        label = context.get("label", "")
        labels = ["T" + str(i) for i in range(1, 13)]
        if label in labels:
            inspect(labels.index(label) + 1)
    elif name == "freeze" and DATA["observed"]:
        DATA["checkpoint"] = {
            "before_tick": 6,
            "backlog": DATA["observed"][4],
            "pending_retries": min(DATA["observed"][4], 8),
        }
        DATA["notice"] = "Checkpoint saved."
    elif name == "compare" and DATA["checkpoint"]:
        backlog = DATA["checkpoint"]["backlog"]
        DATA["branches"] = [
            replay(DATA["tape"], 6, backlog),
            replay(DATA["tape"], 6, backlog, 12),
            replay(DATA["tape"], 6, backlog, 10, False),
        ]
        for key, branch in zip(RESULT_KEYS[:3], DATA["branches"]):
            DATA[key] = branch[-1]
        cleared = [i + 6 for i, v in enumerate(DATA["branches"][2]) if v == 0]
        DATA["cleared_at_tick"] = cleared[0] if cleared else None
        DATA["notice"] = "Branches saved."
    elif name == "minimize" and DATA["branches"]:
        best = DATA["tape"]
        for mask in range(2 ** len(DATA["tape"])):
            subset = [e for i, e in enumerate(DATA["tape"]) if (mask // (2**i)) % 2]
            if replay(subset)[-1] >= 32 and len(subset) < len(best):
                best = subset
        DATA["minimal_trigger"] = [e["id"] for e in best]
        DATA["notice"] = "Exhaustive minimum; annotations excluded."
    elif name == "capsule" and DATA["minimal_trigger"]:
        source = "case = " + repr(snapshot()) + "\n" + CAPSULE_TEMPLATE
        window("capsule", "Incident replay capsule", "python", source)
        DATA["verification_status"] = "unverified"
        DATA["notice"] = "Capsule ready; press its Run."
    elif name == "handoff":
        receipt = ui.workbench.read_file("replay-verification.json")
        valid = False
        try:
            parsed = json.loads(receipt) if receipt else {}
            valid = (
                isinstance(parsed, dict)
                and parsed.get("status") == "pass"
                and parsed.get("case") == snapshot()
                and parsed.get("results") == snapshot()["expected"]
                and parsed.get("verifier_revision") == "independent-v1"
            )
        except (ValueError, TypeError):
            valid = False
        DATA["verification_status"] = "verified" if valid else "unverified"
        handoff = f"""# Incident simulation handoff

Status: {DATA["verification_status"]}

Assumptions: 12 ticks; arrivals 6; retries min(previous backlog, 8);
capacity 10 except 4 at ticks 4 and 5.

Restore capacity: {DATA["restore_final_backlog"]}; capacity 12: {DATA["capacity_final_backlog"]};
retries disabled: {DATA["retry_disabled_final_backlog"]}, cleared at tick {DATA["cleared_at_tick"]}.

Minimum trigger: {", ".join(DATA["minimal_trigger"])}.
64 subsets; failure: final backlog >= 32.
Verifier: independent-v1; reducer: queue-v1.
Receipt matches case: {valid}.

Simulation only. Mutable files are not signed evidence.
"""
        ui.workbench.write_file("incident-handoff.md", handoff)
        DATA["notice"] = (
            "Saved incident-handoff.md and incident-case.json; "
            + DATA["verification_status"]
            + "."
        )
    save()
    draw()


if not saved:
    save()
draw()
