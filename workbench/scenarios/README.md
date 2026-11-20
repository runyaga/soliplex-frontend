# Workbench scenario harness

| Suite | Coverage |
| --- | --- |
| Deterministic | Eight real threads seeded through public persistence APIs and actual workbench tool wrappers, with no inference |
| Models | Ten prompts each for `workbench` (Glimmer) and `workbench-e4b` (Gemma 4 E4B) |
| Motivation | [Workbench lessons](../docs/LESSONS.md) |

| Run from the worktree root | Command |
| --- | --- |
| Deterministic | `bash workbench/scenarios/run.sh --deterministic` |
| Models | `bash workbench/scenarios/run.sh --models` |
| Everything | `bash workbench/scenarios/run.sh --all` |
| Offline JavaScript | `node --test workbench/scenarios/tests/core.test.mjs` |
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
| Replacement | Move the old program into a temporary canvas window, close it, then publish fixed source in the original window. Closing retains child edges. Host repair authorization is never fabricated |
| Container execution | The entry point pipes source and identity over stdin without copying files. For a separately mounted script, pipe a JSON object with `user`, `email`, and `room` into `docker compose exec -T backend /app/.venv/bin/python -B /path/seed.py` |
| Browser | Sign in through Authelia, click `flt-semantics-placeholder`, open thread routes and assert names and roles outside the chat lane. Bounds check placement. PNG pixel checks reject blank paint behind matched widgets |
| Model turns | New creates a real fresh thread per case. Follow-ups share only their prerequisite turns. The runner checks setup surfaces and waits for the actual Flutter AG-UI stream to finish |
| Prompts | `model/prompts.yaml` uses JSON syntax, a YAML 1.2 subset. Records have ids, prompts and assertions, with optional setup, setup assertions and actions |

| Evidence and limits | Detail |
| --- | --- |
| Output | UTC dated `workbench/docs/evidence/scenarios/<date>-<time>/` containing `report.md`, `results.json`, and screenshots. Reports include assertion outcomes, errors, assistant final messages and tool names from the stream and visible timeline |
| Failure | Reports update per case. Setup errors produce failed assertions. Any failed case or missing screenshot exits nonzero |
| Secrets | Credentials stay in memory and stdin. No shell sourcing, credential argv, traces, storage state or raw child logs. Evidence is redacted before serialization. Authentication screenshots are prohibited and account text is masked |
| Retention | Threads remain for review. Delete them through the app when finished. The harness never deletes unrelated threads or volumes |
| Scope limits | Bounds substitute for missing accessible workspace and window roles. Current chart assertions check the placeholder's mounted data, not a graphical renderer. Selectors require live verification |
| Execution | Deterministic programs and replay remain inert. Model counter cases deliberately press Run. The follow-up fix case checks replacement, not the host AI Fix repair chain |
| Offline results | I ran ten JavaScript tests, three recipe tests and one persistence test covering all eight recipes. The installed Soliplex package is `0.94.dev0`, with the public methods above verified identical to v0.93 |
| Markdown | README and generated fixture reports pass markdownlint-cli2. Offline fixtures stay in ignored `tests/.output/` |
| Unverified | Claude must run the live suites. Docker, deployed PostgreSQL, browser semantics, screenshots and both models were unavailable here |
| Flutter checks | Format and analyze cannot start because the SDK writes to `/opt/homebrew/share/flutter/bin/cache`, outside the writable sandbox. No Dart source changed |
