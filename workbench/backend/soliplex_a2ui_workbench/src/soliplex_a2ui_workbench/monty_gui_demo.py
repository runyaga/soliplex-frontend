# Run builds a small stock counter. Buttons and bars call handle_event.
# Each event updates Python state and redraws the app; the log keeps 8 events.
import chart
import ui
import ui.workbench

count = 3
points: "list[chart.BarPointsItem]" = [{"id": "p0", "label": "Start", "value": 3}]
last_event = "run"
history = ["last event: run, count 3"]
notice = "Stock starts at 3. +1 adds stock; -1 removes stock until empty."
# A new Run resets the app and closes the previous snapshot, if present.
try:
    if log_window and log_open:  # ty: ignore[unresolved-reference]
        ui.workbench.close_window(log_window)  # ty: ignore[unresolved-reference]
except NameError:
    log_window = ""
log_open = False


def draw():
    spec = chart.bar(points[-32:], title="Stock samples (click a bar to restore)")
    ui.show(
        ui.Column(
            [
                ui.Text("Python drives the GUI"),
                ui.Text(f"Count: {count}"),
                ui.Text(f"last event: {last_event}, count {count}"),
                ui.Text(notice),
                ui.Text(
                    "Add point records stock; Reset restores 3 and clears samples."
                ),
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
                    action=ui.Event("restore", {}),
                ),
                ui.Text("Recent events (last 8):\n" + "\n".join(history)),
            ]
        ),
        data=DATA,
    )


def open_log():
    global log_window, log_open
    content = "Recent events (snapshot; reopen to refresh):\n" + "\n".join(history)
    if log_window:
        ui.workbench.update_window(log_window, content)
    else:
        log_window = ui.workbench.open_window("Monty event log", "text", content)
    log_open = True
    ui.workbench.move_window(log_window, 1)


def handle_event(name, context):
    global count, points, last_event, history, notice, log_open
    last_event = name
    if name == "plus":
        count += 1
        notice = "Added one item of stock."
    elif name == "minus":
        if count > 0:
            count -= 1
            notice = "Removed one item of stock."
        else:
            notice = "Stock is empty; add an item with +1 before removing one."
    elif name == "reset":
        count = 3
        points = [{"id": "p0", "label": "Start", "value": 3}]
        notice = "Reset stock to 3 and cleared recorded samples."
    elif name == "add_point":
        sample = len(points)
        points.append({"id": f"p{sample}", "label": f"Sample {sample}", "value": count})
        notice = f"Recorded Sample {sample}: {count}. Click its bar to restore stock."
    elif name == "restore":
        label = context.get("label", "")
        for point in points:
            if point["label"] == label:
                count = int(point["value"])
                notice = f"Restored stock from {label}: {count}."
    history = (history + [f"last event: {name}, count {count}"])[-8:]
    if name == "open_log":
        open_log()
    elif name == "close_log" and log_window and log_open:
        ui.workbench.close_window(log_window)
        log_open = False
    draw()


DATA = {}
draw()
