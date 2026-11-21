# Curated two-stage repair. Keep both stages: fix only the reported line.
# First repair: return value + 0. Second repair: handle nonnumeric total as 0;
# the existing positive-value filter skips and counts that malformed row.
import csv

import ui
import ui.workbench


def checked_total(value: int) -> int:
    return value + "0"  # Deliberate type error (attempt 1).


raw = "month,total\nJan,10\nFeb,BROKEN\nMar,30\n"
clean = []
dropped = 0
for row in csv.DictReader(raw.splitlines()):
    amount = int(row["total"])  # Deliberate runtime error (attempt 2).
    if amount > 0:
        clean.append({"label": row["month"], "value": checked_total(amount)})
    else:
        dropped += 1
assert len(clean) == 2 and dropped == 1, (
    "Keep Jan 10 and Mar 30; count one rejected row"
)
content = "month,total\n" + "".join(f"{r['label']},{r['value']}\n" for r in clean)
ui.workbench.write_file("clean.csv", content)
DATA = {
    "clean": clean,
    "dropped": dropped,
    "total": sum(int(r["value"]) for r in clean),
}
ui.show(
    ui.Column(
        [
            ui.Text("Self-healing pipeline · two repairs, one Run"),
            ui.Text(
                f"Saved clean.csv · {len(clean)} clean rows · dropped {dropped} · total {DATA['total']}"
            ),
            ui.BarChart(clean, title="Clean monthly sales"),
            ui.Text(
                "Type check caught stage 1; runtime exposed stage 2. Ask how many rows were dropped."
            ),
        ]
    ),
    data=DATA,
)
print(
    f"Pipeline complete: {len(clean)} clean rows, dropped {dropped}, total {DATA['total']}; saved clean.csv"
)
