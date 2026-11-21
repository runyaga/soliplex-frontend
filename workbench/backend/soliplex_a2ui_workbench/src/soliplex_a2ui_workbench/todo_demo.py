# Curated demo: durable tasks; the model sees items, including done flags.
import json

import ui
import ui.workbench

saved = ui.workbench.read_file("todo.json")
DATA = {
    "items": json.loads(saved) if saved else [],
    "new": "",
    "notice": "Saved to todo.json on each change.",
}


def draw():
    items = DATA["items"]
    remaining = len([item for item in items if not item["done"]])
    rows = [
        ui.Text("To-do · make room for what matters"),
        ui.Text(f"{remaining} left · {len(items)} total"),
        ui.TextField("New task", ui.bind("/new")),
        ui.Button(ui.Text("Add"), action=ui.Event("add", {})),
        ui.Text(DATA["notice"]),
    ]
    for i, item in enumerate(items):
        text = item["text"]
        rows.append(
            ui.Card(
                ui.Column(
                    [
                        ui.Text(("Done: " if item["done"] else "To do: ") + text),
                        ui.Row(
                            [
                                ui.Button(
                                    ui.Text(
                                        ("Undo " if item["done"] else "Done ") + text
                                    ),
                                    action=ui.Event("done", {"index": i}),
                                ),
                                ui.Button(
                                    ui.Text("Remove " + text),
                                    action=ui.Event("remove", {"index": i}),
                                ),
                            ]
                        ),
                    ]
                )
            )
        )
    if not items:
        rows.append(
            ui.Text("No tasks yet. Add one above, then ask the assistant what's left.")
        )
    ui.show(ui.Column(rows), data=DATA)


def handle_event(name, context):
    items = DATA["items"]
    if name == "add":
        text = DATA["new"].strip()[:60]
        if text and len(items) < 12:
            items.append({"text": text, "done": False})
            DATA["new"] = ""
        else:
            DATA["notice"] = "Enter a task; this demo holds up to 12 tasks."
            draw()
            return
    elif name in ["done", "remove"]:
        i = int(context.get("index", -1))
        if 0 <= i < len(items):
            if name == "done":
                items[i]["done"] = not items[i]["done"]
            else:
                items.pop(i)
    ui.workbench.write_file("todo.json", json.dumps(items))
    DATA["notice"] = "Saved to todo.json. Ask the assistant what's left."
    draw()


draw()
