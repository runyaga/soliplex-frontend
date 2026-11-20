# Workbench scenario harness

| Suite | Coverage |
| --- | --- |
| Deterministic | Ten real threads seeded through public persistence APIs and actual workbench tool wrappers, with no inference |
| Models | Eighteen cases each for `workbench` (Glimmer) and `workbench-e4b` (Gemma 4 E4B), including the curated Monty GUI demo, form submissions, credential rejection and REPL result follow-up |
| Motivation | [Workbench lessons](../docs/LESSONS.md) |

| Run from the worktree root | Command |
| --- | --- |
| Deterministic | `bash workbench/scenarios/run.sh --deterministic` |
| Models | `bash workbench/scenarios/run.sh --models` |
| Everything | `bash workbench/scenarios/run.sh --all` |
| Offline JavaScript | `node --test workbench/scenarios/tests/` |
| Offline Python | `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s workbench/scenarios/tests -p 'test_*.py'` |
| Optional persistence check | Run the Python checks with installed Soliplex dependencies and `PYTHONPATH=workbench/backend/soliplex_a2ui_workbench/src`. The optional test uses in-memory SQLite and the real wrappers |
| Markdown | `markdownlint-cli2 'workbench/scenarios/**/*.md' 'workbench/docs/evidence/scenarios/**/*.md' '#**/node_modules/**'` |

| Host requirement | Value |
| --- | --- |
| Deployment | This preview's frontend and backend deployed together at `https://soliplex-a2ui-workbench.localhost:9743` |
| Stack | `~/dev/soliplex-a2ui-workbench`, compose project `soliplex-a2ui-workbench`, running `backend` |
| Credentials | Literal `WB_ADMIN_USER`, `WB_ADMIN_PASSWORD` and `WB_ADMIN_EMAIL` in untracked `workbench/stack/workbench.env`. The account needs both rooms |
| Playwright | Chrome installed. `run.sh` creates an ignored symlink to `~/dev/soliplex-embed-probe/node_modules` |
| Backend | `/app/.venv/bin/python`, Soliplex v0.93, deployed wrappers, both rooms allowed by `SOLIPLEX_WORKBENCH_ROOMS`. Installation defaults to `/environment` |
| Overrides | `WB_SERVER_ALIAS` defaults to `soliplex-a2ui-workbench-localhost-9743`, `WB_RUN_TIMEOUT_MS` to `240000`, `WB_BROWSER_CHANNEL` to `chrome` |

| Implementation | Contract |
| --- | --- |
| Persistence | `ThreadStorage.new_thread`, `add_run_input`, and `save_run_events` from `src/soliplex/agui/persistence.py@952e5ede` (v0.93). These methods match the local checkout. The caller owns transactions |
| Tool boundary | Real `RunContext[AgentDependencies]` with installation, authenticated identity and thread scope. Every `ToolReturn.metadata` activity is stored unchanged, between run lifecycle events. No `FunctionModel` is needed |
| Initial run | The seeder uses the initial run created by `new_thread`. Thread identity commits before wrappers read history in another session |
| Replacement | `repair_program` revises the existing program in place. Its window, source node, activity and surface identities remain stable. The user presses Run again |
| Container execution | The entry point pipes source and identity over stdin without copying files. For a separately mounted script, pipe a JSON object with `user`, `email`, and `room` into `docker compose exec -T backend /app/.venv/bin/python -B /path/seed.py` |
| Browser | Sign in through Authelia, click `flt-semantics-placeholder`, open thread routes and scope assertions to `Workbench region <role>` semantics containers. Windows expose `Workbench window <title>`. PNG pixel checks reject blank paint behind matched widgets |
| Model turns | New creates a real fresh thread per case. Setup, prompt, awaited actions and follow-ups share that thread. Chat and click turns use the same `page.route` capture of the actual Flutter request and require `RUN_FINISHED` |
| Prompts | `model/prompts.yaml` uses JSON syntax, a YAML 1.2 subset. Records have ids, prompts and assertions, with optional setup, setup assertions, actions, followup and expectFail |

| Case field | Contract |
| --- | --- |
| `actions` | Ordered controls scoped by `region` (default workspace). An omitted `kind` clicks a named `button` or `tab` using `role` |
| `kind: fill` | `name` is the textbox label and `value` is its replacement text. Focus and key events update Flutter's editing state |
| `kind: choose` or `select` | `name` is the visible option label, such as North. Defaults to a chip button, with optional checkbox, radio or option role |
| `kind: check` | `name` is the checkbox label, such as Acknowledged. Sets it checked |
| `awaitTurn: true` | A click starts an action-only turn. Capture is installed before the click and awaited before subsequent actions or follow-ups |
| Action `assertions` | Canvas checks evaluated immediately after that action. Failures stop later clicks and are retained in evidence |
| `window` | Optional exact workbench window title for an action or canvas assertion, inside its selected region |
| `followup` | Nonempty list of prompts sent after all actions, in the same thread |
| Assertion `kind: reply` | `includes` is matched case-insensitively against the final assistant text of the most recent captured turn, which must finish successfully |
| Computed reply expectation | `includes: {"pow": [7, 12345, 1000003]}` computes the modular power with BigInt in the harness. The result is never supplied in the prompt |
| Assertion `kind: csv` | Public workdir listing must contain the receipt filename; an authenticated download must have a last row with the current submission ID and exact submitted values |
| Assertion `kind: submission` | `name: workbench_intake` or `workbench_form` and exact `context` values must match a synthetic tool call/result pair in the action run's persisted input, read through its authenticated public GET endpoint |
| `expectFail` | Optional nonempty reason recorded in evidence. Assertions still run and failures still exit nonzero. A passing case is marked `unexpectedPass` |

| Added model case | Sequence |
| --- | --- |
| `walkthrough` | Click the first room suggestion and observe all 17 scripted narrations and key surfaces in order within a generous timeout, ending with the wrap-up. Start grants consent only to the curated GUI source; AI Fix is honestly skipped. See [walkthrough mechanism and checks](../docs/WALKTHROUGH.md) |
| `monty_demo` | Send Open the Monty GUI demo. Press Run and require its heading, zero counter, chart, six buttons and initial log window. Close the initial log, click +1 twice and check each counter and last-event line. Open the log, require it, close it and require its absence. Layout gestures must finish their captured streams. The deterministic seeder publishes the same demo with open_demo and verifies inert reload before the same clicks |
| `submit_form` | Setup places the built-in intake in the left sidebar. Fill Question with Scenario zebra question, check North and Acknowledged, then Submit and await its turn. Require the stored workbench_intake pair, RUN_FINISHED and zebra in that turn's reply |
| `custom_form` | Publish Scenario survey in the left sidebar, fill Name, choose Blue from its radio list, check Subscribe and Submit. Require provenance, stored workbench_form values, walrus and scenario-survey.csv in the reply, and matching values in the downloaded CSV |
| `credential_form` | Request a login form with a password field. Require the companion text panel and no password-like canvas field |
| `ai_fix_off` | Run a deliberately failing program with AI Fix unchecked. Observe 20 seconds, require zero action turns and the visible error |
| `ai_fix_on` | Check AI Fix and Run the failing program. Require one repair publication, its automatic successful run-result action, and computed print output with `ok` in the window |
| `repl_result` | Publish Scenario compute with `print(pow(7, 12345, 1000003))`, press Run and await its action turn, then ask what it printed. Require the computed value in the follow-up reply |

| Existing REPL result path | Code trace |
| --- | --- |
| Output capture | `packages/soliplex_monty/lib/src/lab_catalog.dart:544` writes bounded print output into the surface model and calls onRun at line 565 when no successful ui.workbench layout actions are staged. Those actions use the separate layout transaction at line 563. The ui tree itself stays local |
| Bound action | `workbench/backend/soliplex_a2ui_workbench/src/soliplex_a2ui_workbench/workbench_publication.py:299` binds workbench.program.run_result to output and provenance |
| Action turn | `lib/src/modules/room/ui/room_screen.dart:277` forwards surface actions to `thread_view_state.dart:459`, which spawns an empty-prompt turn with a2uiAction. `packages/soliplex_agent/lib/src/orchestration/run_orchestrator.dart:249` places it in forwardedProps |
| Model input | `workbench/backend/soliplex_a2ui_workbench/src/soliplex_a2ui_workbench/workbench_actions.py:75` converts a run result into an untrusted user message. `workbench_routes.py:336` appends it to the adapter's run input |
| Next turn | `workbench_projection.py:147` restores accepted submissions from persisted run inputs. `workbench_routes.py:285` reinserts those messages on continuation. This is a user-message history path, with a synthetic tool pair used for intake and custom forms |
| Decision | The print-output path exists. repl_result is an expected-pass case. No product path was added |

| Evidence and limits | Detail |
| --- | --- |
| Output | UTC dated `workbench/docs/evidence/scenarios/<date>-<time>/` containing `report.md`, `results.json`, and screenshots. Reports include assertion outcomes, errors, assistant final messages and tool names from the stream and visible timeline |
| Failure | Reports update per case. Setup errors produce failed assertions. Any failed case or missing screenshot exits nonzero |
| Secrets | Credentials stay in memory and stdin. No shell sourcing, credential argv, traces, storage state or raw child logs. Evidence is redacted before serialization. Authentication screenshots are prohibited and account text is masked |
| Retention | The runner deletes its recorded deterministic and model thread ids in `finally`, through public `ThreadStorage.delete_thread`. Set `WB_KEEP_THREADS=1` to retain them for review. It never enumerates or deletes unrelated threads |
| Scope limits | Region and window semantics replace geometry classification. Graphics charts require image semantics with title and series; the embedded lab chart exposes named bar buttons. Every visible assertion also checks PNG ink. Selectors require live verification |
| Execution | Replay remains inert. The Monty demo and model counter cases deliberately press Run. Other deterministic programs remain inert. The follow-up fix case checks replacement. The AI Fix cases check the host repair chain and its off switch |
| Offline tests | JavaScript tests cover corpus validation, action checkpoints, window scopes, turn capture, stored form pairs, reply assertions, computed expectations, evidence, semantic selectors and cleanup retention. Eight Python tests cover recipes, public-storage cleanup and persistence, including all ten seeded recipes |
| Markdown | README and generated fixture reports pass markdownlint-cli2. Offline fixtures stay in ignored `tests/.output/` |
| Unverified | Claude must run the live suites. Docker, deployed PostgreSQL, browser semantics, screenshots and both models were unavailable here |
| Flutter checks | Host widget tests cover region and window semantics, Python source and Run mounting, and a hittable form Submit. The socket-restricted sandbox uses direct `flutter_tester` execution |

## Curated Monty GUI demo

`open_demo(name="monty_gui")` publishes the backend package's
`monty_gui_demo.py` unchanged in a new **Monty GUI demo** canvas window. The
suggestion **Open the Monty GUI demo.** teaches the model to call that tool and
tell the user to press Run and click the buttons. Publication never executes
Python. Run builds the controls in **Monty GUI demo app** beside the source
window and opens a separate **Monty event log** result window. The app controls
and counter assertions use `initialViewport: true`: no scrolling is allowed,
and both viewport and ancestor clipping bounds must contain each target.
Each button calls the real `handle_event(name, context)` in the same session.

A second Run closes the prior log before replacing it in the retained session.
The counter stays at or above zero. Add point appends a counter sample;
`chart.bar` builds the spec and the existing embeddable `ui.BarChart` displays
the latest 32 samples beside the controls. `ui.graphics.Chart` requires a
standalone surface, so the demo uses the existing lab chart for this composition.
Opening the log replaces its previous window, then moves the replacement to
canvas position 1. Each gesture stages at most three layout actions, below the
eight-action limit (including the automatic app opening), and leaves at most
three windows open: program, app and log. Ordinary windows retain their limit
of two; the app counts toward the new total limit of three.

Backend tests check publication, corrective unknown-name errors, the frozen
publication operations and log layout transactions. The fixture stores a source
placeholder; the Flutter test reads the canonical backend source directly.
The app uses a server-authored `shared.programApps` binding from its stable
window ID to the registered program surface. Its live surface stays in memory
in the program's session. Reload renders a press-Run placeholder because the
interpreter globals do not survive reload. A new Run reuses or reopens that
window; closing the program cascades to its app. The program transcript shows
only its latest entry by default, with a control above it to expand history.
Canvas widths below the tablet breakpoint stack the app before its program;
wider canvases put them beside each other.

Native Monty widget tests execute that source and every handler, including
chart redraws, log replacement, repeated close and reopen, and more than eight
cumulative actions across separate gestures. Live Chrome and Glimmer checks
still require the host deployment.

## Custom form contract

`place_form` accepts either `template="intake"` or a nonempty `fields` list.
Combining them is rejected. The intake fields and `workbench_intake` submission
shape are unchanged. Both forms display "Form created by the assistant" below
the title. Custom fields support text, textarea, number, choice, checkbox and
date. Each has a unique identifier name, label, kind and optional required flag.
Choices accept string options or objects with value and label, and `multiple`.
Number bounds are `min`/`max`; text bounds are `max_length` (default 4000).
Required checkboxes must be checked. Dates use valid `YYYY-MM-DD` values.

Bare labels become text fields with lowercase underscore names. select,
dropdown and radio become choice; multiselect becomes choice with multiple.
The server rejects credential requests in field names, labels, option labels
and titles, unsupported kinds, misplaced bounds and oversized definitions.
Limits are 12 fields, 12 options, 80 characters per title/label, 60 per option
label/value, 64 per identifier, and 4000 per text value.

Custom Submit emits `submit_form` with a `values` object. Server validation
binds it to the stored activity and surface, rejects extra fields and checks
required values, types, options and bounds before inference. Basic numeric
controls write strings; accepted finite numbers become numbers. Choices write
lists; a single choice becomes one string. Empty optional fields are omitted.
The server adds the authoritative surfaceId and title and stores the canonical
envelope with its untrusted synthetic `workbench_form` pair (`form.submit@1`).
History restores that exact pair and deduplication identity. Reload and replay
never submit or start inference. The tool is reserved and cannot be registered
by the client; forged synthetic history is rejected.

The deterministic custom form case checks an inert reload. Its byte-identical
backend publication fixture also drives Flutter tests for all field kinds,
semantics, current-value submission and finite region/window/split/tab bounds.
The harness uses a radio action for Color because the basic catalog renders
single choices without chips as radio lists. Widget semantics check that role.
Live Chrome semantics and model runs still require the host suites.

## Saved form results

Each validated Submit appends one row to the thread workspace CSV before
inference. Custom titles become lowercase ASCII slugs of at most 48 characters;
empty slugs use `form`. Ordered field names determine file compatibility. A
conflicting schema gets `-2`, `-3`, etc. The built-in template reserves
`intake.csv`; a custom form titled Intake starts at `intake-2.csv`.

Columns are `submitted_at` (server UTC), `submission_id`, then fields in
definition order. Missing optional values are empty cells; booleans and lists
use JSON. Cells beginning with `=`, `+`, `-`, `@`, tab or carriage return receive
an apostrophe. The Python CSV writer handles quoting and newlines. A directory
lock serializes writes across threads and backend processes; disk rows provide
submission-ID deduplication across worker restarts. Writes are flushed and
synced before the server reports the saved filename. CSV saving and run-history
persistence are separate operations: a retry after a saved row reuses its receipt.

`read_form_results(title)` is scoped to the authenticated thread and returns
untrusted data, total row counts, columns, and recent rows. Output is limited to
20 rows per file, 1000 characters per cell and 16 KiB overall, with `truncated`
set when limits discard content. It never creates files. Room teaching explains
that a synthetic form result is a just-completed user submission, and replies
should briefly acknowledge values and the authoritative `savedFile` filename.

Step3 sets `sandbox_config.workdirs_path` to `/data/workbench/workdirs` on the
existing named Compose volume. Step6 creates that directory and assigns it to
the backend user. Existing Compose isolation and deployment guards remain.
The app already refreshes workdirs on thread open and run completion, shows CSV
files in its Files panel, and offers the existing download action. No app
feature flag or production Dart change is needed.

Offline backend tests exercise actual public listing/download handlers with
identity dependencies stubbed. A widget test verifies a saved survey CSV is
visible and its download action selects it. Live authentication, deployed volume
ownership, Chrome rendering, Glimmer wording and browser downloads remain host
verification steps after deployment.

## Program repair preference

Each program has an AI Fix checkbox, unchecked by default. The preference is
stored on this device by stable surface ID, so repair replacement and reload
retain it. It is separate from server-authored code: publishing or replaying a
surface cannot opt the user in. Repair chains and pending arrival permissions
stay in memory; reload and history never resume them. Unchecking ends a pending
chain. The manual AI Fix button requests one repair; with the checkbox off the
replacement waits for Run. The former Yes/No retry prompt is removed; after the
retry budget is spent, the manual button remains available.
