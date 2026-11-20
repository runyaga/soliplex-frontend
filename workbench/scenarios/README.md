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
| Replacement | `repair_program` revises the existing program in place. Its window, source node, activity and surface identities remain stable. The user presses Run again |
| Container execution | The entry point pipes source and identity over stdin without copying files. For a separately mounted script, pipe a JSON object with `user`, `email`, and `room` into `docker compose exec -T backend /app/.venv/bin/python -B /path/seed.py` |
| Browser | Sign in through Authelia, click `flt-semantics-placeholder`, open thread routes and scope assertions to `Workbench region <role>` semantics containers. Windows expose `Workbench window <title>`. PNG pixel checks reject blank paint behind matched widgets |
| Model turns | New creates a real fresh thread per case. Follow-ups share only their prerequisite turns. The runner checks setup surfaces and waits for the actual Flutter AG-UI stream to finish |
| Prompts | `model/prompts.yaml` uses JSON syntax, a YAML 1.2 subset. Records have ids, prompts and assertions, with optional setup, setup assertions and actions |

| Evidence and limits | Detail |
| --- | --- |
| Output | UTC dated `workbench/docs/evidence/scenarios/<date>-<time>/` containing `report.md`, `results.json`, and screenshots. Reports include assertion outcomes, errors, assistant final messages and tool names from the stream and visible timeline |
| Failure | Reports update per case. Setup errors produce failed assertions. Any failed case or missing screenshot exits nonzero |
| Secrets | Credentials stay in memory and stdin. No shell sourcing, credential argv, traces, storage state or raw child logs. Evidence is redacted before serialization. Authentication screenshots are prohibited and account text is masked |
| Retention | The runner deletes its recorded deterministic and model thread ids in `finally`, through public `ThreadStorage.delete_thread`. Set `WB_KEEP_THREADS=1` to retain them for review. It never enumerates or deletes unrelated threads |
| Scope limits | Region semantics replace geometry classification. Current chart assertions check the placeholder's mounted data. Selectors require live verification |
| Execution | Deterministic programs and replay remain inert. Model counter cases deliberately press Run. The follow-up fix case checks replacement, not the host AI Fix repair chain |
| Offline tests | Twelve JavaScript tests cover corpus validation, evidence, semantic selectors and cleanup retention. Six Python tests cover recipes, public-storage cleanup and persistence, including all eight seeded recipes |
| Markdown | README and generated fixture reports pass markdownlint-cli2. Offline fixtures stay in ignored `tests/.output/` |
| Unverified | Claude must run the live suites. Docker, deployed PostgreSQL, browser semantics, screenshots and both models were unavailable here |
| Flutter checks | Host widget tests cover region and window semantics, Python source and Run mounting, and a hittable form Submit. The socket-restricted sandbox uses direct `flutter_tester` execution |
