# Workbench scenario harness

| Suite | Coverage |
| --- | --- |
| Deterministic | Eight real threads seeded through public persistence APIs and actual workbench tool wrappers, with no inference |
| Models | Twelve cases each for `workbench` (Glimmer) and `workbench-e4b` (Gemma 4 E4B), including intake submission and REPL result follow-up |
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
| `followup` | Nonempty list of prompts sent after all actions, in the same thread |
| Assertion `kind: reply` | `includes` is matched case-insensitively against the final assistant text of the most recent captured turn, which must finish successfully |
| Computed reply expectation | `includes: {"pow": [7, 12345, 1000003]}` computes the modular power with BigInt in the harness. The result is never supplied in the prompt |
| Assertion `kind: submission` | `name: workbench_intake` and exact `context` values must match a synthetic tool call/result pair in the action run's persisted input, read through its authenticated public GET endpoint |
| `expectFail` | Optional nonempty reason recorded in evidence. Assertions still run and failures still exit nonzero. A passing case is marked `unexpectedPass` |

| Added model case | Sequence |
| --- | --- |
| `submit_form` | Setup places the built-in intake in the left sidebar. Fill Question with Scenario zebra question, choose North, check Acknowledged, then Submit and await its turn. Require the stored workbench_intake pair, RUN_FINISHED and zebra in that turn's reply |
| `repl_result` | Publish Scenario compute with `print(pow(7, 12345, 1000003))`, press Run and await its action turn, then ask what it printed. Require the computed value in the follow-up reply |

| Existing REPL result path | Code trace |
| --- | --- |
| Output capture | `packages/soliplex_monty/lib/src/lab_catalog.dart:544` writes bounded print output into the surface model and calls onRun at line 565 when no successful ui.workbench layout actions are staged. Those actions use the separate layout transaction at line 563. The ui tree itself stays local |
| Bound action | `workbench/backend/soliplex_a2ui_workbench/src/soliplex_a2ui_workbench/workbench_publication.py:299` binds workbench.program.run_result to output and provenance |
| Action turn | `lib/src/modules/room/ui/room_screen.dart:277` forwards surface actions to `thread_view_state.dart:459`, which spawns an empty-prompt turn with a2uiAction. `packages/soliplex_agent/lib/src/orchestration/run_orchestrator.dart:249` places it in forwardedProps |
| Model input | `workbench/backend/soliplex_a2ui_workbench/src/soliplex_a2ui_workbench/workbench_actions.py:75` converts a run result into an untrusted user message. `workbench_routes.py:336` appends it to the adapter's run input |
| Next turn | `workbench_projection.py:147` restores accepted submissions from persisted run inputs. `workbench_routes.py:285` reinserts those messages on continuation. This is a user-message history path, with a synthetic tool pair used only for intake |
| Decision | The print-output path exists. repl_result is an expected-pass case. No product path was added |

| Evidence and limits | Detail |
| --- | --- |
| Output | UTC dated `workbench/docs/evidence/scenarios/<date>-<time>/` containing `report.md`, `results.json`, and screenshots. Reports include assertion outcomes, errors, assistant final messages and tool names from the stream and visible timeline |
| Failure | Reports update per case. Setup errors produce failed assertions. Any failed case or missing screenshot exits nonzero |
| Secrets | Credentials stay in memory and stdin. No shell sourcing, credential argv, traces, storage state or raw child logs. Evidence is redacted before serialization. Authentication screenshots are prohibited and account text is masked |
| Retention | The runner deletes its recorded deterministic and model thread ids in `finally`, through public `ThreadStorage.delete_thread`. Set `WB_KEEP_THREADS=1` to retain them for review. It never enumerates or deletes unrelated threads |
| Scope limits | Region semantics replace geometry classification. Current chart assertions check the placeholder's mounted data. Selectors require live verification |
| Execution | Deterministic programs and replay remain inert. Model counter cases deliberately press Run. The follow-up fix case checks replacement, not the host AI Fix repair chain |
| Offline tests | Twenty JavaScript tests cover corpus validation, actions, turn capture, stored intake pairs, reply assertions, computed expectations, evidence, semantic selectors and cleanup retention. Six Python tests cover recipes, public-storage cleanup and persistence, including all eight seeded recipes |
| Markdown | README and generated fixture reports pass markdownlint-cli2. Offline fixtures stay in ignored `tests/.output/` |
| Unverified | Claude must run the live suites. Docker, deployed PostgreSQL, browser semantics, screenshots and both models were unavailable here |
| Flutter checks | Host widget tests cover region and window semantics, Python source and Run mounting, and a hittable form Submit. The socket-restricted sandbox uses direct `flutter_tester` execution |
