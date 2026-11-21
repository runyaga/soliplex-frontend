# Curated hot-patch: preserve STATE and fix only the export division line.
# Export sets pending before failing. Re-running the repaired module retries it.
from typing import Any

import ui
import ui.workbench

try:
    STATE.setdefault("samples", [40, 50])  # ty: ignore[unresolved-reference]
except NameError:
    STATE: dict[str, Any] = {
        "samples": [40, 50],
        "target": 100,
        "pending": False,
        "report": "No report yet.",
    }
DATA = {}


def export_report():
    samples = STATE["samples"]
    average = sum(samples) / 0  # Deliberate bug: divide by len(samples), not zero.
    report = f"Samples: {len(samples)}; peak: {max(samples)}; target: {STATE['target']}; average: {average}"
    ui.workbench.write_file("traffic-report.txt", report)
    STATE["report"] = "Saved traffic-report.txt · " + report
    STATE["pending"] = False
    print(report)


def draw():
    DATA.update(STATE)
    DATA["breached"] = max(STATE["samples"]) > STATE["target"]
    ui.show(
        ui.Column(
            [
                ui.Text("Traffic lab · repair without losing the experiment"),
                ui.Text(
                    f"{len(STATE['samples'])} samples · peak {max(STATE['samples'])} req/s · target {STATE['target']} req/s"
                ),
                ui.Text(
                    "Enable AI Fix. Build traffic, then Export report to trigger the one-line bug."
                ),
                ui.Row(
                    [
                        ui.Button(
                            ui.Text("Normal traffic"), action=ui.Event("normal", {})
                        ),
                        ui.Button(ui.Text("Burst"), action=ui.Event("burst", {})),
                        ui.Button(
                            ui.Text("Export report"), action=ui.Event("export", {})
                        ),
                    ]
                ),
                ui.LineChart(
                    [str(i + 1) for i in range(len(STATE["samples"]))],
                    [
                        {"label": "Traffic", "values": STATE["samples"]},
                        {
                            "label": "Target",
                            "values": [STATE["target"] for _ in STATE["samples"]],
                        },
                    ],
                    title="Request rate (req/s)",
                ),
                ui.Text(STATE["report"]),
            ]
        ),
        data=DATA,
    )


def handle_event(name, context):
    if name in ["normal", "burst"]:
        STATE["samples"] = (STATE["samples"] + [60 if name == "normal" else 140])[-24:]
    elif name == "export":
        STATE["pending"] = True
        export_report()
    draw()


if STATE["pending"]:
    export_report()
draw()
