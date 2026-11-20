# Workbench walkthrough

Click **Start the walkthrough.**, the first room suggestion. The tour has
17 scripted steps. Stop is always available in its bottom tray; Pause/Resume
and Next let the viewer control the pace. Typing a chat message stops it too.
Reload restores the story and surfaces but never resumes, replays a gesture,
or runs Python. Start again explicitly to begin another tour.

## Mechanism

A client timer requests one step per action-only AG-UI turn. The narrow server
handler calls the existing workbench tools and emits the resulting validated
activities, followed by the same narration as an assistant chat message. The
exact Start suggestion also uses that handler, calling `start_walkthrough()`
without inference. The registered tool and its one-line teaching rule cover
model tool callers too.

A single tool call cannot pace its buffered ToolReturn activities. Separate
turns make each step visible before the next request. Reading time starts
after local effects complete: generally five or six seconds, eight seconds for
the introduction and ten for the AI Fix explanation. Each acknowledgement is
required before another step request; a 30-second acknowledgement timeout
stops the player. No timer, consent, or execution intent is persisted.

The bottom tray keeps the narration and controls separate from the right
sidebar's chart. On narrow screens the tour opens the Workspace tab, keeps the tray outside
workspace scrolling and pins playback controls above the tabs. Its
narration is a regular server-published text surface with stable identities;
the host adds local playback controls. Every layout mutation, including the
program's app and log windows, goes through the existing server validator.

The server checks the authenticated layout control, tour identity and exact
previous step. Stop tolerates an earlier acknowledged step so it can finish
cleanly when a Next request is already in flight. Closed tours reject Next.
The client ignores old acknowledgements and duplicate deliveries. A stopped
player never executes an arriving effect.

Start grants only local, in-memory consent. Before each automatic program
run or event, the client compares the current editor source's SHA-256 with the
curated `monty_gui_demo.py` digest. Changed, repaired or model-written source
fails closed. Publication and replay alone grant no permission. The ordinary
Run and AI Fix paths keep their existing behavior.

## What the viewer sees

| Steps | Visible result |
| --- | --- |
| 1 | Workbench regions and validated placement explained in the tray and chat |
| 2–3 | Real HHG Weekly visits line chart on the canvas; Regions bar chart on the right |
| 4–5 | Bar chart moves beside the line, then back, retaining its ids; user placement or size changes win |
| 6 | A custom Team survey on the left; field validation, credential guard and thread CSV explained |
| 7 | Sample visitor, Blue and Subscribe appear in the form, with a full reading interval before submission |
| 8 | Samples pass the regular form validator and CSV writer; chat and tray name the CSV and row's submission id |
| 9–10 | Unchanged curated Monty GUI source appears; Run opens its app beside the program |
| 11–13 | Three programmatic +1 presses visibly count to 3; narration explains `handle_event` and the round trip |
| 14 | Add point redraws the chart with the current count |
| 15 | Open log window publishes the event log through the server layout path |
| 16 | Honest AI Fix skip: explains the checkbox and deliberate NameError example, and says the repair/rerun chain is being fixed elsewhere |
| 17 | Only tour surfaces and its program-owned windows close; narration lists the other room suggestions |

AI Fix repair code in `lab_catalog.dart` was not edited. Its only changes
register live program controls in `build`, expose the current editor text and
existing Run/event callbacks, and unregister controls in `dispose`.

## Implementation files

| Area | Files |
| --- | --- |
| Script and server dispatch | `workbench_walkthrough.py`, `workbench_routes.py`, `workbench_tools.py` in the backend package |
| Registration and teaching | Backend `workbench_agent_tools.py`, `workbench_schemas.py`, `workbench_teaching.py` |
| Consent, pacing and source guard | Room `workbench/walkthrough_player.dart`, `workbench/walkthrough_programs.dart` |
| Host and composer integration | Room `workbench/workbench_host.dart`, `ui/room_screen.dart`, `a2ui/surface_scope.dart` |
| Live interpreter controls | Catalogs `program_app.dart`; Monty `lab_catalog.dart` |
| Digest dependency | Root `pubspec.yaml`, `pubspec.lock`: existing crypto dependency moves from dev to runtime |
| Backend tests | `test_walkthrough.py`, `test_workbench_tool_schemas.py`, `test_workbench_contract.py`, `test_stack_template.py` |
| Flutter tests | `walkthrough_player_test.dart`, `walkthrough_programs_test.dart`, `custom_form_test.dart`, `workbench_host_test.dart`; native example `walkthrough_programs_test.dart` |
| Harness | `lib/walkthrough.mjs`, model `walkthrough.json` and `prompts.yaml`, `model/run.mjs`, `lib/core.mjs`, `tests/core.test.mjs`, `tests/walkthrough.test.mjs`, `tests/index.js` |

## Verification and limits

Backend tests walk every step through the validator, check stable chart ids,
real CSV output, preservation of unrelated panels, placement priority,
unknown/out-of-order rejection, every Stop position, interruption races,
inert replay and a complete route stream with a model that raises if called.

Widget tests use the fake clock for pacing, Stop, typing, Pause/Resume, Next,
duplicate delivery and reload. A real mounted form test checks values appear
before any submission. A native Monty test runs the curated source and its
five scripted button events, then changes the editor and verifies refusal.

The `walkthrough` harness case clicks the actual room suggestion and observes
all 17 narrations and key surfaces in order, ending with the wrap-up and closed
tour surfaces. It keeps stream interception installed for the entire tour.
Offline JavaScript tests verify the watcher rejects skipped steps, unexpected
tool calls and failed checkpoints.

Host verification remains required: deployed Chrome semantics and pixels,
Glimmer room behavior, the real AG-UI persistence service, authenticated CSV
download, and the full app suite. No deployment or live browser run was
performed in the sandbox. The AI Fix demonstration is intentionally skipped.
