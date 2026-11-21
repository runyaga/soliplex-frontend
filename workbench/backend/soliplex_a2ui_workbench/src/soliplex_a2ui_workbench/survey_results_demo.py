# Curated demo: submit Team survey, press Run, then Refresh and click a colour.
import csv

import ui
import ui.workbench

DATA = {"counts": {}, "respondents": [], "selected": "", "rows": 0}
people = []


def refresh():
    global people
    people = list(
        csv.DictReader(ui.workbench.read_file("team-survey.csv").splitlines())
    )
    DATA["counts"] = {
        color: len([r for r in people if r.get("color") == color])
        for color in ["Red", "Green", "Blue"]
    }
    DATA["rows"] = len(people)
    select(DATA["selected"])


def select(color):
    DATA["selected"] = color
    DATA["respondents"] = [
        r.get("name", "Anonymous") for r in people if r.get("color") == color
    ]


def draw():
    ui.show(
        ui.Column(
            [
                ui.Text("Team survey · live results"),
                ui.Text(f"{DATA['rows']} responses · team-survey.csv"),
                ui.Text(
                    "Submit on the left, then Refresh. Click a bar to see its respondents."
                ),
                ui.Button(ui.Text("Refresh"), action=ui.Event("refresh", {})),
                ui.BarChart(
                    [
                        {"label": c, "value": DATA["counts"][c]}
                        for c in ["Red", "Green", "Blue"]
                    ],
                    title="Color counts",
                    action=ui.Event("select", {}),
                ),
                ui.Text(
                    (
                        DATA["selected"]
                        + " respondents: "
                        + (", ".join(DATA["respondents"]) or "None")
                    )
                    if DATA["selected"]
                    else "Choose a colour bar to inspect responses."
                ),
            ]
        ),
        data=DATA,
    )


def handle_event(name, context):
    if name == "refresh":
        refresh()
    elif name == "select":
        select(context.get("label", ""))
    draw()


refresh()
draw()
