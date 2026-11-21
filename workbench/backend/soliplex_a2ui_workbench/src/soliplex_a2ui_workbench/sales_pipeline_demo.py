# Curated demo: a bounded monthly data generator with a durable CSV artifact.
import csv

import ui
import ui.workbench

months = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
]
DATA = {
    "rows": "3",
    "totals": [],
    "notice": "Choose 1–12 rows, then Generate to write sales.csv.",
}
saved = ui.workbench.read_file("sales.csv")
if saved:
    DATA["totals"] = [
        {"label": r["month"], "value": int(r["total"])}
        for r in csv.DictReader(saved.splitlines())
    ][:12]


def draw():
    DATA["total"] = sum(int(row["value"]) for row in DATA["totals"])
    rows = [
        ui.Text("Sales pipeline · from parameters to artifact"),
        ui.TextField("Rows", ui.bind("/rows"), variant="number"),
        ui.Button(ui.Text("Generate"), action=ui.Event("generate", {})),
        ui.Text(DATA["notice"]),
    ]
    if DATA["totals"]:
        rows.append(ui.BarChart(DATA["totals"], title="Monthly sales"))
    else:
        rows.append(ui.Text("Your generated monthly totals will appear here."))
    ui.show(ui.Column(rows), data=DATA)


def handle_event(name, context):
    if name == "generate":
        raw = str(DATA["rows"])
        if not raw.isdigit() or not 1 <= int(raw) <= 12:
            DATA["notice"] = "Rows must be a whole number from 1 to 12."
        else:
            count = int(raw)
            DATA["totals"] = [
                {"label": months[i], "value": (i + 1) * 10} for i in range(count)
            ]
            content = "month,total\n" + "".join(
                f"{r['label']},{r['value']}\n" for r in DATA["totals"]
            )
            ui.workbench.write_file("sales.csv", content)
            DATA["notice"] = (
                f"Saved {count} rows to sales.csv · total {sum(int(r['value']) for r in DATA['totals'])}"
            )
    draw()


draw()
