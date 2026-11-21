# Curated demo: edits stay local until Save; Run reloads notes.md.
import ui
import ui.workbench

DATA = {"text": ui.workbench.read_file("notes.md"), "saved_pattern": ""}


def remember_saved():
    pattern = ""
    for char in DATA["text"]:
        pattern += ("\\" if char in "\\.^$*+?{}[]|()" else "") + char
    DATA["saved_pattern"] = "^" + pattern + "$(?![\\s\\S])"


def draw():
    ui.show(
        ui.Column(
            [
                ui.Text("Notes · your thread notebook"),
                ui.Text(
                    "Run loads notes.md. Save keeps the current text with this thread."
                ),
                ui.TextField("Notes", ui.bind("/text"), variant="longText"),
                ui.Text(
                    {
                        "@call": "formatString",
                        "args": {
                            "value": "Unsaved changes: ${not(value:${regex(value:${/text}, pattern:${/saved_pattern})})}"
                        },
                    }
                ),
                ui.Button(ui.Text("Save"), action=ui.Event("save", {})),
                ui.Text("Saved snapshot: notes.md"),
            ]
        ),
        data=DATA,
    )


def handle_event(name, context):
    if name == "save":
        ui.workbench.write_file("notes.md", DATA["text"])
        remember_saved()
    draw()


remember_saved()
draw()
