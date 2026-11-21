# Each button is one bounded user gesture. Run only loads receipts and controls.
# No monotonic clock is available through the app's OS policy: the browser
# supplies click-to-redraw timings with Save observation, including VM failures.
import json
from typing import Any

import ui
import ui.workbench

FILE = "probe-results.json"
BUTTONS = [
    ("Compute", "compute"),
    ("Redraw", "redraw"),
    ("Charts", "charts"),
    ("Events", "events"),
    ("Long session", "long"),
    ("Files", "files"),
    ("App state", "state"),
    ("Type check", "types"),
    ("Windows", "windows"),
    ("Window cycles", "cycles"),
    ("Close probe windows", "close"),
]
book: dict[str, Any] = {}
try:
    book = json.loads(ui.workbench.read_file(FILE))
except ValueError:
    book = {"version": 1, "results": [], "next": {}, "windows": [], "long": 0}
DATA = {"receipt": "", "largest_field": "", "sentinel": "probe-visible"}


def save():
    ui.workbench.write_file(FILE, json.dumps(book))


def begin(probe, size):
    row = {
        "id": len(book["results"]) + 1,
        "probe": probe,
        "size": size,
        "status": "started",
        "wall_ms": None,
        "clock": "browser click to visible result (harness)",
    }
    book["results"].append(row)
    save()  # A cancellation must leave the attempted size on disk.
    return row


def draw(chart_node=None, nodes=0):
    buttons = [
        ui.Button(ui.Text(label), action=ui.Event(event, {}))
        for label, event in BUTTONS
    ]
    rows = [ui.Row(buttons[i : i + 2]) for i in range(0, len(buttons), 2)]
    children = (
        [ui.Text(book.get("message", "Probe ready")), ui.Text("Platform probe")]
        + rows
        + [
            ui.TextField("Probe receipt", value=ui.bind("/receipt")),
            ui.Button(ui.Text("Save observation"), action=ui.Event("receipt", {})),
        ]
    )
    # Count *all* components: labels, buttons, rows, field, texts and root.
    used = 6 + 2 * len(buttons) + len(rows)
    if chart_node is not None:
        children.insert(2, chart_node)
        used += 1
    for i in range(max(0, nodes - used)):
        children.append(ui.Text(f"node {i}"))
    ui.show(ui.Column(children), data=DATA)


def handle_event(name, context):
    if name == "receipt":
        receipt = json.loads(DATA.get("receipt", "{}"))
        for result in book["results"]:
            if result["id"] == receipt.get("id"):
                # Keep the program outcome separate from browser observations.
                result["observation"] = receipt
                result["wall_ms"] = receipt.get("wall_ms")
                if (
                    receipt.get("server_rejected")
                    and result.get("window_id") in book["windows"]
                ):
                    book["windows"].remove(result["window_id"])
        DATA["receipt"] = ""
        save()
        draw()
        return
    if name == "close":
        # One close per gesture avoids the eight-action transaction bound.
        if book["windows"]:
            ui.workbench.close_window(book["windows"].pop())
        save()
        draw()
        return
    index = book["next"].get(name, 0)
    sizes = {
        "redraw": [50, 20_000, 20_001],
        "charts": [8, 32, 50, 200, 500],
        "files": [1024, 8 * 1024 * 1024, 8 * 1024 * 1024 + 1],
        "state": [1024, 8192, 14000, 14800, 15000, 16000, 16384, 16385],
    }
    size = sizes[name][index % len(sizes[name])] if name in sizes else index + 1
    if name == "compute":
        size = 10000 * (2**index)
    book["next"][name] = index + 1
    if name == "long" and book["long"]:
        row = [r for r in book["results"] if r["probe"] == "long"][-1]
    else:
        row = begin(name, size)
    marker = f"PROBE {row['id']} {name}"
    chart_node = None
    try:
        if name == "compute":
            checksum = 0
            for i in range(size):
                checksum = (checksum + i) % 1000003
            row["checksum"] = checksum
        elif name == "charts":
            if index % 5 < 2:
                chart_node = ui.BarChart(
                    [{"label": f"B{i}", "value": i + 1} for i in range(size)],
                    title=f"Probe bars {size}",
                )
                row["kind"] = "bar"
            else:
                chart_node = ui.LineChart(
                    [str(i) for i in range(size)],
                    [
                        {
                            "label": f"S{s}",
                            "values": [(i + s) % 19 for i in range(size)],
                        }
                        for s in range(6)
                    ],
                    title=f"Probe lines 6 x {size}",
                )
                row["kind"] = "line"
                row["series"] = 6
        elif name == "events":
            row["count"] = index + 1
        elif name == "long":
            book["long"] += 1
            row["count"] = book["long"]
            marker += f" count {book['long']}"
        elif name == "files":
            payload = "x" * size  # ASCII: characters == UTF-8 bytes.
            ui.workbench.write_file("probe-payload.txt", payload)
            read_back = ui.workbench.read_file("probe-payload.txt")
            row["read_bytes"] = len(read_back)
            row["matches"] = read_back == payload
        elif name == "windows":
            window = ui.workbench.open_window(
                f"Probe window {index + 1}", "text", "probe"
            )
            book["windows"].append(window)
            row["window_id"] = window
            row["requested_count"] = len(book["windows"])
            row["status"] = "requested"  # Server acceptance is measured by the harness.
        elif name == "cycles":
            window = ui.workbench.open_window(
                f"Probe cycle {index + 1}", "text", "probe"
            )
            ui.workbench.close_window(window)
            row["cycle"] = index + 1
            row["status"] = "requested"
        elif name == "state":
            tail = f"probe-tail-{size}-739201!"
            DATA["largest_field"] = "x" * (size - len(tail)) + tail
            row["field_bytes"] = len(DATA["largest_field"])
            row["data_bytes"] = len(json.dumps(DATA).encode("utf-8"))
        elif name == "types":
            source = 'print("PROBE padded type check")\n#'
            source += "x" * (1_000_000 - 1 - len(source)) + "\n"
            row["source_bytes"] = len(source.encode("utf-8"))
            row["window_id"] = ui.workbench.open_window(
                "Probe type check 1000000", "python", source
            )
            book["windows"].append(row["window_id"])
            row["status"] = "requested"
        if row["status"] != "requested":
            row["status"] = "completed"
        row["message"] = marker + " done"
        book["message"] = row["message"]
        draw(chart_node, size if name == "redraw" else 0)
    except (ValueError, TypeError) as error:
        row["status"] = "error"
        row["error"] = str(error)
        row["message"] = marker + " error"
        book["message"] = row["message"]
        # At 20,001 nodes even the fallback controls cannot be allocated. Keep the
        # last accepted app and expose the rejection in the run transcript.
    save()
    print(marker + " " + row["status"] + " " + row.get("error", ""))


save()
draw()
