# Curated explorer: data is quoted with repr, never inserted as executable code.
import csv

import ui
import ui.workbench

raw = ui.workbench.read_file("anomalies.csv")
if not raw:
    raw = "batch,latency_ms\nA,40\nB,45\nC,240\nD,50\n"
    ui.workbench.write_file("anomalies.csv", raw)
rows = [
    {"batch": r["batch"], "latency_ms": int(r["latency_ms"])}
    for r in csv.DictReader(raw.splitlines())
][:12]
DATA = {
    "rows": rows,
    "selected": [],
    "target": 100,
    "notice": "Click the C bar to inspect its outlier, then Spawn reproducer.",
}
# A second Run keeps the child's identity, closing it until the next spawn.
try:
    if child:  # ty: ignore[unresolved-reference]
        ui.workbench.close_window(child)  # ty: ignore[unresolved-reference]
except NameError:
    child = ""


def draw():
    ui.show(
        ui.Column(
            [
                ui.Text("Anomaly explorer · make the evidence executable"),
                ui.Text(
                    "Latency target: 100 ms. The child script stays inert until you press its Run."
                ),
                ui.BarChart(
                    [
                        {"label": str(r["batch"])[:60], "value": int(r["latency_ms"])}
                        for r in rows
                    ],
                    title="Batch latency (ms)",
                    action=ui.Event("select", {}),
                ),
                ui.Text("Selected rows: " + str(DATA["selected"])),
                ui.Button(ui.Text("Spawn reproducer"), action=ui.Event("spawn", {})),
                ui.Text(DATA["notice"]),
            ]
        ),
        data=DATA,
    )


def handle_event(name, context):
    global child
    if name == "select":
        DATA["selected"] = [
            r for r in rows if str(r["batch"])[:60] == context.get("label", "")
        ]
        DATA["notice"] = "Selection captured. Spawn a reproducer of these exact rows."
    elif name == "spawn":
        selected = DATA["selected"]
        if not selected:
            DATA["notice"] = "Select a bar first."
        else:
            source = (
                "# Selected rows from anomalies.csv; Run to verify.\nrows = "
                + repr(selected)
                + "\ntarget = 100\npeak = max(int(r['latency_ms']) for r in rows)\n"
                + "print('Selected peak:', peak, 'ms; target:', target, 'ms')\n"
                + "assert peak > target, 'Select an outlier that breaches the 100 ms target'\n"
            )
            if child:
                ui.workbench.update_window(child, source)
            else:
                child = ui.workbench.open_window("Anomaly reproducer", "python", source)
            DATA["notice"] = (
                "Reproducer ready. Press Run in Anomaly reproducer, then ask the assistant to compare."
            )
    draw()


draw()
