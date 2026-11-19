# Phase 2 host installation handoff

| Item | Value |
| --- | --- |
| Status | Prepared only. I did not run generation, Docker, model probes, Flutter, or git writes |
| Script | `./setup-stack.sh`, executable, `set -euo pipefail` |
| Target | `~/dev/soliplex-a2ui-workbench` |
| Scratch | `~/dev/soliplex-a2ui-workbench-build` |
| Compose project | `soliplex-a2ui-workbench` |
| URL | `https://soliplex-a2ui-workbench.localhost:9743` |
| HTTP | `http://soliplex-a2ui-workbench.localhost:9700` |
| Sign-in | Authelia, username `$WB_ADMIN_USER`, a password the operator chooses, Soliplex admin |
| Prior decisions search | Two factory-knowledge queries, `soliplex a2ui lab stack template Authelia` and `workbench Glimmer Gemma second install`, both failed with `Too many open files`. Prior decisions are UNVERIFIED. I cannot claim no prior decision found |
| Source authority | I used the local files below. Template snapshot is `soliplex-template@4d9b4b8e639b38289d2893187343baa8df65bfa3`. The lab report is dated 2026-11-19 at `plans/soliplex-a2ui/a2ui-lab-stack.md:3`. No indexed `path@commit` was available |

| Citation convention | Root |
| --- | --- |
| `T/` | `~/dev/soliplex-template/` |
| `L:` | `~/dev/plans/soliplex-a2ui/a2ui-lab-stack.md:` |
| `D:` | `~/dev/plans/soliplex-a2ui/dojo-integration-plan.md:` |
| `F/` | `~/dev/soliplex-frontend-wt/exp-dojo-a2ui/` |
| `B/` | `~/dev/soliplex-a2ui-lab/` |

| BLOCKER | Evidence | Resolution needed |
| --- | --- | --- |
| Requested Ollama hostname conflicts with template guidance | `T/skills/soliplex-template/references/GENERATION.md:134` requires a bare IP and predicts HTTP 403 for a hostname. The brief explicitly requests `http://OLLAMA_HOST:11434` | The script preserves the requested endpoint. Step7 must pass using that hostname, followed by the E4B room check from the container. If it fails, stop and resolve server hostname allowance with the owner. I have not substituted an IP or changed Ollama |
| Exact thinking-off behavior is not established | The template agent examples omit model settings at `T/skills/soliplex-template/assets/template/backend/environment/installation.yaml.mako:272`. Current backend uses an OpenAI chat transport for Ollama at `~/dev/soliplex/src/soliplex/config/agents.py:580` | The candidate option sends `extra_body.think: false` through `/v1/chat/completions`. Step7 requires an answer with no returned reasoning fields. This alone cannot prove the server honored the option. Claude must verify the installed Ollama version's behavior before declaring thinking off satisfied |
| Requested A2UI versions conflict with the supplied Phase 2 frontend | Brief requires core 0.8 and Flutter 0.4. The supplied plugin pins core 0.7.0 and Flutter 0.3.0 at `F/packages/soliplex_monty/pubspec.yaml:17`. The historical integration plan reports the same versions at `D:41` | I preserve the explicitly requested current plugin example baseline. Claude must resolve whether Phase 2 can use this baseline or needs a separately authorized migration. This handoff does not claim 0.8 compliance |
| Upstream drift, conditional host stop | Reviewed generator snapshot is `4d9b4b8`. Step1 fetches and fast-forwards clean main, or clones main if the original is on another branch | If HEAD differs from the reviewed snapshot, step1 aborts before generation. Review the new template before changing the pin |

| Step | Exact host command from this directory | Behavior and retry rule | Result |
| --- | --- | --- | --- |
| Review | `less setup-stack.sh` | Review the script and BLOCKER rows before installation | TODO (host) |
| 1 | `./setup-stack.sh step1` | Check tools, update clean main or clone another branch into scratch, require reviewed pin, generate once with `--no-git`. Refuse a nonempty unmanaged target | TODO (host) |
| 2 | `./setup-stack.sh step2` | Rotate six initial secrets once. Print only count and lengths. Refuse existing containers or the target Postgres volume before rotation | TODO (host) |
| 3 | `./setup-stack.sh step3` | Write models, two room variants, tools and skills. Install Authelia with `--no-up`. Apply all compatibility and nginx patches. Repeating refreshes managed configuration | TODO (host) |
| 4 | `./setup-stack.sh step4` | Build images, run stack-init, create Authelia database, bootstrap file backend if empty, start Authelia | TODO (host) |
| 5 | `./setup-stack.sh step5` | Add identifier before exporting. Preserve UUID across retries, verify exported identity, reset password using `_generate_hash`, write users in place, add admin by sub, restart Authelia | TODO (host) |
| 6 | `./setup-stack.sh step6` | Copy frontend and local Monty checkout, analyze, run plugin VM and Chrome tests, build example, install web files, start stack, apply both room ACLs, restart backend and nginx | TODO (host) |
| 7 | `./setup-stack.sh step7` | Host model probes, embedding dimension assertion, HTTP checks, gzip headers. Browser checks below remain required | TODO (host) |
| Sequential alternative | `./setup-stack.sh all` | Same sequence. It does not bypass any BLOCKER or host acceptance requirement | TODO (host) |

| Adaptation | Reason | Precedent or template source |
| --- | --- | --- |
| Separate project, paths, 9700:9000 and 9743:9443 | Protect other installs. Script rejects protected names and canonical path aliases. Every Docker invocation is scoped to the target, including helper subprocesses through `COMPOSE_PROJECT_NAME`. Resolved compose checks reject other published ports, external volumes, external networks and outside bind sources | Compose project name is parameterized at `T/skills/soliplex-template/assets/template/docker-compose.yml.mako:3`. Host ports are parameters at `T/skills/soliplex-template/scripts/generate_soliplex_project.py:69`. Lab isolation at `L:3` |
| Read-only reference stacks | Only the new target and scratch are runtime write destinations. No stop, prune, down or volume deletion command is present. Protected published ports are 9200, 9543, 9600, 9643 and 9443. Internal nginx 9443 remains valid | Lab kept dojo untouched at `L:3`. Internal port guidance at `T/skills/soliplex-template/references/PARAMETERS.md:187` |
| No automatic initial commit | Generator defaults to git initialization and `git add -A`. Explicit `--no-git` avoids both | `T/skills/soliplex-template/scripts/generate_soliplex_project.py:954`, `:1019` |
| Discard generator stdout and stderr | Generated DB passwords and bearer must never reach the terminal, including failure output. No secret-bearing log is created | `L:130`, `T/src/soliplex_template/secrets.py:373` |
| Random initial rotation with in-place file writes | Six values become fresh 64-character hex strings before database initialization. A marker prevents repeat rotation against initialized PostgreSQL. Partial initial rotation can be retried before start | `L:51`, `T/src/soliplex_template/secrets.py:17`, `:338` |
| Glimmer default, title and provisioned RAG agents | Use vLLM endpoint `http://MODEL_HOST:11450/v1`, exact Muse model, context 131072, 32768 output tokens. Change lab reasoning low to requested medium | `L:34`, `L:40`. Generated agent IDs at `T/skills/soliplex-template/assets/template/backend/environment/installation.yaml.mako:272` |
| Gemma alternate agent and separate A2UI Lab E4B room | Make the option directly selectable through a room. Use Ollama endpoint root `http://OLLAMA_HOST:11434`, OpenAI transport base `/v1`, model `gemma4:e4b`, 4096 output tokens, candidate `think: false`. Thinking-off remains a BLOCKER | Agent fields are post-generation edits per `T/skills/soliplex-template/references/INFERENCE_PROVIDERS.md:113`. Backend transport at `~/dev/soliplex/src/soliplex/config/agents.py:580` |
| Required placeholder `ollama_base_url` | Generate with `http://127.0.0.1:11434` and wire every actual model explicitly afterwards. No model is intended to use the placeholder | `T/skills/soliplex-template/references/INFERENCE_PROVIDERS.md:62`, generator requirement at `T/skills/soliplex-template/scripts/generate_soliplex_project.py:708`, `L:28` |
| Nemotron embeddings in backend and ingester | Same vLLM endpoint `http://MODEL_HOST:11438/v1`, exact model `nvidia/llama-nemotron-embed-vl-1b-v2`, vector dimension 2048. Step7 asserts probe dimension | `L:35`, `L:49`. Both configs must match per `T/skills/soliplex-template/references/INFERENCE_PROVIDERS.md:126` |
| Nemotron reranker and Glimmer RAG QA | Backend reranker uses `http://MODEL_HOST:11434`, model `nvidia/llama-nemotron-rerank-vl-1b-v2`. Keep generated in-stack docling wiring | `L:36`, `L:37`, `L:38` |
| Docker 29 chmod | Insert `RUN chmod 1777 /tmp` after both backend `/tmp` COPY instructions and the dev image COPY. These images also serve provisioner and initialization roles | `L:131`, `T/skills/soliplex-template/assets/template/backend/Dockerfile.mako:41`, `:57`, `T/skills/soliplex-template/assets/template/soliplex-dev/Dockerfile:44` |
| Remove unsupported fork-only fields when present | Stock backend rejects `usage_limits` and `run_timeout_seconds`. Do not copy fork-only limits from the dojo | `L:132` |
| nginx Host port map | Use `$http_host` to recover the externally published port when X-Forwarded-Port is absent | `L:133`, `T/skills/soliplex-template/assets/template/nginx/nginx.conf.mako:60` |
| Authelia configuration before first up | `--no-up` writes configuration and secrets, avoiding installer add on an empty identifier store | `T/skills/soliplex-template/scripts/install_authelia.py:826`, `L:55` |
| Authelia listener, proxy and healthcheck use 9743 | Backend issuer resolves directly to Authelia on the compose network. All three ports must agree with issuer URL. nginx itself still listens internally on 9443 | `L:57`, `L:135`, `T/skills/soliplex-template/scripts/install_authelia.py:415`, `:468`, `:579` |
| Bootstrap file backend | Create an empty users file during configuration and replace it with a captured bootstrap hash before Authelia starts. No digest is printed. Step5 performs the final reset using the requested helper | File backend path at `T/skills/soliplex-template/scripts/install_authelia.py:487`. Hash capture behavior at `T/skills/soliplex-template/scripts/authelia_users.py:114` |
| Identifier add before export | Persist a new UUID on the host, add first, export to a unique filename, then verify the exported username and UUID. This handles retries without hiding an identity mismatch | `L:56`, `L:134`, buggy export-first order at `T/skills/soliplex-template/scripts/authelia_users.py:196` |
| `$WB_ADMIN_USER` key and in-place password reset | Full email lookup would miss this username. Use `_generate_hash` directly, write users.yml through an open file, add admin with matching opaque sub. Restart clears watcher lag | `T/skills/soliplex-template/scripts/authelia_users.py:114`, `:156`, `:263`, `L:59`, `L:60`. Bind-mount constraint is in `workbench/PROMPT.md` |
| Unique export filename and in-place identifiers.yml update | Avoid stale macOS view after unlinking a mounted file | `L:134`, unlink behavior at `T/skills/soliplex-template/scripts/authelia_users.py:170` |
| Static asset exemption in both server blocks | Add `limit_rate 0` for JS, wasm, CSS, JSON, fonts and images. Exclude API, MCP, Authelia, ingester and error routes from suffix matching. Add `application/wasm` to gzip_types | Server rate limits at `T/skills/soliplex-template/assets/template/nginx/nginx.conf.mako:113`, `:370`, gzip list at `:47`. Owner's additional fixes at `workbench/PROMPT.md` |
| Copy plugin example and dependency | rsync excludes `.git`, `build` and `.dart_tool`. Rewrite only copied plugin's local Monty path to the scratch copy. Shared frontend and dart_monty2 remain untouched | Deployable entry is `packages/soliplex_monty/example/lib/main.dart` at `D:55`, deployed version `soliplex_monty_app` at `L:97`. Path dependency at `F/packages/soliplex_monty/pubspec.yaml:20` |
| Build target | In copied `packages/soliplex_monty/example`, run `flutter build web --target lib/main.dart --release --no-tree-shake-icons --no-web-resources-cdn` | `D:136`, `L:62`. The root app does not register the lab plugin |
| Web nonce and text-field focus checks | Retain safe `nextInt(0x7fffffff)`, patch copied old expression only if needed. Require existing focus guard | Lab failure at `L:136`. Current safe expression at `F/packages/soliplex_monty/lib/src/python_ui.dart:87`. Focus guard at `F/lib/src/modules/room/ui/room_screen.dart:1392`. Lab note claiming the current worktree still has the nonce bug is stale |
| Local frontend mount and restart | Install under target `frontend-web/`, mount read-only at `/app/build/web`, restart nginx after replacing the files. Refuse an unrelated override | `L:63`, `L:81`, `L:137`, image frontend origin at `T/skills/soliplex-template/scripts/generate_soliplex_project.py:1099` |
| Copy backend tool, room and authoring skills | Rewrite tool package to `soliplex_a2ui_workbench`. Copy working Monty and A2UI skills. Keep authenticated READ and WRITE, DENY default, apply ACLs for both variants | `L:64`, `L:65`, `L:79`, `L:80`, working room at `B/backend/environment/rooms/a2ui-lab/room_config.yaml:1` |
| Gates on copied code | Run Flutter analysis, plugin VM and Chrome tests, DCM analysis and metrics with agent package options copied into scratch package config files. Existing DCM exceedances may stop deployment and need review | `D:83`, `D:87`, `D:89`, `D:94`. No gates were run in this preparation sandbox |

| Verification | Exact command or browser action | Expected evidence | Result |
| --- | --- | --- | --- |
| Embedded Python | Parsed all 10 Python heredocs with `ast.parse` without executing them | Syntax valid | PASS (preparation) |
| Patch assertions | Applied nginx and Dockerfile patches to in-memory source text only | Two static asset locations, wasm gzip type, port map and three chmod insertions | PASS (preparation) |
| Script syntax | `bash -n ./setup-stack.sh` | Exit 0 | PASS (preparation) |
| Compose isolation | `./setup-stack.sh step7` | Project name, only published 9700 and 9743, no outside bind mounts or external resources | TODO (host) |
| Containers | `cd ~/dev/soliplex-a2ui-workbench && docker compose -p soliplex-a2ui-workbench ps` | All long-running services healthy | TODO (host) |
| Model endpoints | `./setup-stack.sh step7` | Glimmer medium probe, embedding length 2048, rerank response, E4B content without returned reasoning. Does not settle thinking-off BLOCKER alone | TODO (host) |
| Listener and static config | `cd ~/dev/soliplex-a2ui-workbench && docker compose -p soliplex-a2ui-workbench exec -T nginx nginx -t` | Configuration valid | TODO (host) |
| Resolved models | `cd ~/dev/soliplex-a2ui-workbench && docker compose -p soliplex-a2ui-workbench run --rm -T soliplex-dev /app/.venv/bin/soliplex-cli config /environment` | Correct endpoints, reasoning medium, max_tokens 32768, E4B option 4096. Inspect locally, do not paste configuration containing secrets into reports | TODO (host) |
| Issuer URL | `curl -fkSs https://soliplex-a2ui-workbench.localhost:9743/api/login` | Authelia server URL contains hostname, 9743 and `/authelia` | TODO (host) |
| Discovery | `curl -fkSs https://soliplex-a2ui-workbench.localhost:9743/authelia/.well-known/openid-configuration` | Matching issuer and reachable endpoints | TODO (host) |
| Worker gzip | `curl -fkSs -H 'Accept-Encoding: gzip' -D - -o /dev/null https://soliplex-a2ui-workbench.localhost:9743/assets/packages/dart_monty/lib/assets/dart_monty_worker.wasm` | 200, application/wasm, Content-Encoding gzip | TODO (host) |
| HTTP static block | `curl -fSs -o /dev/null -w '%{http_code} %{speed_download}\n' http://soliplex-a2ui-workbench.localhost:9700/assets/packages/dart_monty/lib/assets/dart_monty_worker.wasm` | 200. Transfer not capped at 1024k per second | TODO (host) |
| TLS static block | `curl -fkSs -o /dev/null -w '%{http_code} %{speed_download}\n' https://soliplex-a2ui-workbench.localhost:9743/assets/packages/dart_monty/lib/assets/dart_monty_worker.wasm` | 200. Transfer not capped at 1024k per second | TODO (host) |
| Unauthenticated protection | `curl -kSs -o /dev/null -w '%{http_code}\n' https://soliplex-a2ui-workbench.localhost:9743/api/v1/rooms` | 401 | TODO (host) |
| Open app | `open -a 'Google Chrome' https://soliplex-a2ui-workbench.localhost:9743` | Accept local certificate if needed, hard reload to clear prior service-worker content | TODO (host) |
| Sign-in | Click Connect, choose Authelia, sign in as `$WB_ADMIN_USER` with a password the operator chooses | DevTools Network shows firstfactor 200, OIDC callback, rooms 200. Lobby shows both A2UI rooms | TODO (host) |
| Admin | `cd ~/dev/soliplex-a2ui-workbench && docker compose -p soliplex-a2ui-workbench run --rm -T soliplex-dev /app/.venv/bin/soliplex-cli admin-users list /environment` | $WB_ADMIN_USER's persisted UUID matches an admin sub rule | TODO (host) |
| Glimmer room | Open A2UI Lab. Send `Show me the mission checklist.` | Room answers and checklist appears | TODO (host) |
| Python editor | Send `Open the Python editor.` | PythonRepl renders, no execution until Run | TODO (host) |
| Browser Python | Replace editor source with `x = sum(range(10))` then `print(x)` then `x * 2`, each on its own line. Press Run | First-run loading state, worker JS and wasm 200, output 45 and 90 | TODO (host) |
| Widget interaction | Choose Widgets from Python, press Run, then Send to Python | Counter advances from 0 to 1, no console errors | TODO (host) |
| Focus | Click the Python-built Name field and type `workbench` | Text stays in that field | TODO (host) |
| Reload safety | Hard reload the thread before pressing any Run button | Surfaces restore, Python does not automatically execute | TODO (host) |
| E4B room | Repeat checklist, editor, Python, widget and reload checks in A2UI Lab E4B | Same capability, endpoint reachable from backend, thinking-off BLOCKER resolved separately | TODO (host) |

| Screenshot capture | Exact host command after the matching browser check | Result |
| --- | --- | --- |
| Create evidence directory | `mkdir -p ~/dev/soliplex-a2ui-workbench/evidence` | TODO (host) |
| Lobby after sign-in | `screencapture -i ~/dev/soliplex-a2ui-workbench/evidence/01-signin.png` | TODO (host) |
| Glimmer checklist | `screencapture -i ~/dev/soliplex-a2ui-workbench/evidence/02-glimmer-room.png` | TODO (host) |
| Python output | `screencapture -i ~/dev/soliplex-a2ui-workbench/evidence/03-glimmer-python.png` | TODO (host) |
| Widget counter | `screencapture -i ~/dev/soliplex-a2ui-workbench/evidence/04-glimmer-widgets.png` | TODO (host) |
| E4B room and Python output | `screencapture -i ~/dev/soliplex-a2ui-workbench/evidence/05-e4b-python.png` | TODO (host) |

| Operational limit | Handling |
| --- | --- |
| Partial generator failure | Do not use `--force`. Inspect the new target on the host. No secret-bearing output is retained |
| Rotation after initialization | Refused. This script performs initial rotation only, with no volume deletion or automatic SQL password repair |
| Repeating step3 | Restores managed config, including auth listener fixes, and preserves users and secrets. Then repeat steps4 through6 to apply changes |
| Repeating step5 | Reuses persisted UUID. Mismatched existing identity stops the step. Password and admin rule converge on the requested values |
| Concurrent frontend edits | rsync is a copy, not an atomic source snapshot. Quiesce source editors for step6 if a consistent revision is required |
| Symlinks | Output trees containing symlinks are refused before mutation. Inspect unexpected copied or generated symlinks locally instead of bypassing path guards |
| Flutter and DCM versions | DCM analyze help was inspected and unsupported `--options` was avoided. Actual gates remain UNVERIFIED. A gate failure stops deployment. Do not skip a failed gate without reviewing its cause |
| Host connectivity | Network access, image availability, TLS behavior, Docker version, model compatibility and browser behavior remain UNVERIFIED |
| Protected installs | No commands target soliplex-dojo, soliplex-a2ui-lab or soliplex-afsoc. The lab is read only. Do not use unscoped cleanup commands during recovery |

## Host run results (2026-11-19)

| Item | Result | Evidence |
| --- | --- | --- |
| Steps 1 to 7 | All exit 0 after the fixes below | `./setup-stack.sh stepN` |
| Secret rotation | 6 secrets rotated, length 64, values never printed | step2 output |
| Isolation | Only nginx publishes ports, 9700 and 9743. Project `soliplex-a2ui-workbench`. Dojo, lab and afsoc untouched | `check_compose` |
| Model probes | Glimmer medium answers, embeddings dim 2048, rerank 200, E4B streamed with 0 reasoning chars | step7 |
| nginx | `application/wasm` served with `Content-Encoding: gzip` | step7 |
| Sign-in | `$WB_ADMIN_USER` with a password the operator chooses through Authelia lands on `#/lobby` | `evidence/01-signed-in.png` |
| Rooms | A2UI Lab (Glimmer), A2UI Lab E4B, Custom Tool Demo | `evidence/02-lobby.png` |
| Glimmer, Python in browser | Tip calculator: source shown inert until Run, then Monty builds the surface | `evidence/03-glimmer-tip.png`, `evidence/05-ran.png` |
| E4B, Python in browser | Run executes in Monty. E4B's program raised `TypeError: Text() got an unexpected keyword argument 'value'`, a model API error, and AI Fix is offered | `evidence/10-e4b-ran.png` |
| Copied frontend gates (not code I wrote) | `flutter analyze` 1 issue, `dcm analyze` 0, `calculate-metrics` 0, `flutter test` 42 pass, chrome tests fail to load `workspace_files_test.dart` | `../../../soliplex-a2ui-workbench-build/gates.txt` |

| Fix applied during the run | Cause |
| --- | --- |
| `uv run --no-project` in `py()` | uv picked up the generated project's `requires-python >=3.13` |
| Copy `python-retry` skill | The lab room lists it, so `admin-users list` failed in stack-init |
| Exclude `ephemeral`, `.symlinks`, `Pods` from the frontend rsync, and limit the symlink guard to the stack dir | Flutter creates symlinks in the scratch build tree |
| Run every `pub get` before the gates, and report gates without blocking | Root `flutter analyze` ran before `soliplex_monty` resolved |
| Copy `a2ui_action.py` beside `a2ui_lab.py`, rename the import | `ModuleNotFoundError: soliplex_a2ui_lab` gave HTTP 500 on `/api/v1/rooms` |
| E4B `extra_body.reasoning_effort: none`, probe streamed | Ollama ignores `think: false` on streamed `/v1` calls (220 reasoning chars streamed vs 0). Before the fix the room showed a Thinking block, `evidence/07-e4b-thinking.png` |
| Rebuild frontend from the current `exp-dojo-a2ui` | Another agent added PythonRepl `mode` to the lab server (02:38) and client (02:46). The older client rejected it with `VALIDATION_FAILED` |

| Open | Note |
| --- | --- |
| Source drift | `exp-dojo-a2ui` and `soliplex-a2ui-lab` are being edited by another agent. Re-run step3 and step6 together to keep server and client in step |
| Chrome test load failure | `workspace_files_test.dart` fails to load under `--platform chrome`. Cause not investigated |

## Later changes (2026-11-19)

| Change | Result |
| --- | --- |
| Sources frozen | Frontend builds from `exp-workbench` (`exp/workbench` at 41e43107). Lab inputs come from `soliplex-a2ui-workbench-build/lab-snapshot` (lab HEAD fdd6437 plus `uncommitted.diff`) |
| Logfire | step3 writes `.secrets/logfire_token.gen` from `~/dev/.env`, mounts it in the backend only, sets `logfire_config` service `soliplex-a2ui-workbench`, environment `workbench`. A Glimmer chat produced `invoke_agent` and `chat` spans under that service |
| B07, gates | step6 stops on any failed gate. `WORKBENCH_ALLOW_GATE_FAILURES=1` deploys anyway |
| B07, overwrites | step3 seeds `a2ui_lab.py` and `a2ui_action.py` once and never overwrites them |
| Stack stopped | All services except postgres exited at the same time about 7 hours earlier (exit 0 and 137). `docker compose up -d --wait` restored them. Cause not investigated |
| Delegate allowlist | `agent-allow.txt` adds `MODEL_HOST` for Codex and agy sends on this project only |
