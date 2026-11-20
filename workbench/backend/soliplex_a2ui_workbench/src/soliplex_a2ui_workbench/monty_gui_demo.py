# Script -> GUI: Run builds the counter, buttons and chart, then opens a result window.
# GUI -> script: each button calls handle_event; Python changes state and redraws.
# The last-event line makes the round trip visible. Nothing runs until you press Run.
import chart
import ui

count = 0
points = [{"id": "p0", "label": "Start", "value": 0}]
last_event = "run"
# A second Run replaces the previous log in this retained REPL session.
try:
    if log_window:
        ui.workbench.close_window(log_window)
except NameError:
    pass
log_window = ""


def draw():
    # The embeddable bar chart shows the latest 32 samples beside the controls.
    spec = chart.bar(points[-32:], title="Counter samples")
    ui.show(
        ui.Column(
            [
                ui.Text("Python drives the GUI"),
                ui.Text(f"Count: {count}"),
                ui.Text(f"last event: {last_event}, count {count}"),
                ui.Row(
                    [
                        ui.Button(ui.Text("+1"), action=ui.Event("plus", {})),
                        ui.Button(ui.Text("-1"), action=ui.Event("minus", {})),
                        ui.Button(ui.Text("Reset"), action=ui.Event("reset", {})),
                    ]
                ),
                ui.Button(ui.Text("Add point"), action=ui.Event("add_point", {})),
                ui.Row(
                    [
                        ui.Button(
                            ui.Text("Open log window"), action=ui.Event("open_log", {})
                        ),
                        ui.Button(
                            ui.Text("Close log window"),
                            action=ui.Event("close_log", {}),
                        ),
                    ]
                ),
                ui.BarChart(
                    [
                        {"label": point["label"], "value": point["value"]}
                        for point in spec["points"]
                    ],
                    title=spec["title"],
                ),
            ]
        ),
        data=DATA,
    )


def open_log():
    global log_window
    # Replace the old log before opening another: two ordinary windows plus the app stay open.
    if log_window:
        ui.workbench.close_window(log_window)
    log_window = ui.workbench.open_window(
        "Monty event log", "text", f"last event: {last_event}, count {count}"
    )
    ui.workbench.move_window(log_window, 1)


def handle_event(name, context):
    global count, last_event, log_window
    last_event = name
    if name == "plus":
        count += 1
    elif name == "minus":
        count = max(0, count - 1)
    elif name == "reset":
        count = 0
    elif name == "add_point":
        sample = len(points)
        points.append({"id": f"p{sample}", "label": f"Sample {sample}", "value": count})
    elif name == "open_log":
        open_log()
    elif name == "close_log" and log_window:
        ui.workbench.close_window(log_window)
        log_window = ""
    draw()


DATA = {}
draw()
open_log()
