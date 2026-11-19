# Prompt: an agent-composed workbench layout for Soliplex, on its own install

You are designing, then prototyping, a different Soliplex user interface. In it the agent arranges the screen itself, not only answering in a chat column. Work in phases and stop for the owner at the end of phase 1.

## Goal

A "workbench" layout keeps a chat window, but the room's agent can also:

- open and close side bars and panels.
- bring widgets into view and arrange them.
- put up forms that capture structured input.
- place charts and tables.
- launch mini programs (Python run by Monty in the browser) in their own windows.

The layout persists across turns and reloads. The user can move, close or pin what the agent placed. Everything is built on A2UI surfaces and the existing Soliplex frontend architecture, not a fork that throws it away.

The prototype runs on a **separate Soliplex install**, not on the existing stacks.

## Constraints

- **Do not touch** these existing stacks: `~/dev/soliplex-dojo` (ports 9200 and 9543), `~/dev/soliplex-a2ui-lab` (9600 and 9643), or soliplex-afsoc (9443).
- **New stack:** `~/dev/soliplex-a2ui-workbench`, ports 9700 (HTTP) and 9743 (HTTPS), URL `https://soliplex-a2ui-workbench.localhost:9743`, with a distinct compose project name.
- **Target models.** Both are self-hosted. No frontier models, and every feature must work on both, or say which one it needs.
  - Muse Glimmer 30B: vLLM, OpenAI API, `http://MODEL_HOST:11450/v1`, model `Inferact/Muse-Glimmer-30B-NVFP4-W4A4`. Its reasoning cannot be switched off. Set `chat_template_kwargs.reasoning_strength` to `medium` for authoring and give it at least 4096 output tokens.
  - Gemma 4 E4B: Ollama, `http://OLLAMA_HOST:11434`, `gemma4:e4b`, thinking off.
- **Repository rule.** `soliplex_client`, `soliplex_agent` and the app never depend on `dart_monty`. The Monty bridge lives in a plugin package, `soliplex_monty`. dart_monty never depends on Soliplex.
- **Lints.** Use the soliplex/frontend package level: `very_good_analysis` plus `packages/soliplex_agent/dcm_options.yaml`. Run `flutter analyze`, `dcm analyze` and `dcm calculate-metrics` on everything you write.
- **Safety.**
  - An A2UI payload never executes Python by itself. Python runs on a user gesture.
  - Narrow exception, already approved: a bounded auto-retry chain after a user's Run.
  - Replay and reload never run code.
  - Forms and Monty output reach the model as untrusted data.
- **Prose rules** for documents: claim plus `path:line`, tables over paragraphs, no em dashes, no semicolons, and "I" not "we".
- **Git.** Do not commit or push anywhere unless the owner asks. Never add Claude attribution lines. Stage explicit paths, never `git add -A`.

## Read first: owner decisions already made

`~/dev/plans/soliplex-a2ui/` holds the plans. Read these first:

| File | Why |
| --- | --- |
| `track-a-action-contract.md`, `track-a-client-gaps.md` | how clicks and actions reach a room, surface state and replay, what the client does today |
| `track-b-binding-contract.md`, `widget-interaction-findings.md` | the Python `ui` binding for A2UI and 198 interaction tests' findings |
| `rooms/ROOMS-DESIGN.md` | seven room designs, build order, gaps |
| `hhg-a2ui-r2.md` (and `hhg-a2ui-r3.md` if present) | Map, Chart and Svg components and the `geo` catalog |
| `catalog-survey.md`, `inspiration-survey.md` | available A2UI catalogs, chart and map libraries, ideas from form and server-driven UI libraries |
| `monty-codegen-skill.md`, `monty-handoff.md` (if present) | what Monty supports, room skills, client and server handoff |
| `a2ui-lab-stack.md`, `dojo-integration-plan.md` | how the lab stack was cut and deployed |
| `monty-handoff.md` | Monty pause on one side and resume on the other: works with engine 1.3.0 on both sides. Soliplex pins pydantic-monty 1.4.0 (dump format 14), which the 1.3.0 client refuses. Prefer answer-only round trips (a host function calls a server endpoint). Treat any inbound dump as untrusted code. |

The decisions in force:

- **Server A2UI emitter and action reader:** `ggozad/soliplex-a2ui` (`56bf87c`).
- **A2UI version:** `a2ui_core` ^0.8.0, `a2ui_flutter` ^0.4.0, `a2ui_agent` ^0.4.0.
- **Python sessions:** one session per surface. Globals survive between events. A timeout or crash resets the session, and the user is told. Reactions are short `handle_event(name, context)` calls with no long-running loops.
- **Session call budget:** raise dart_monty's per-session suspension budget, which defaults to 1000, with `ResourceLimits(maxSuspensions:)`.
- **Model-written code is allowed:** the LLM writes the program and Monty runs it.
- **Maps:** GeoJSON `[lng, lat]`, a separate `urn:soliplex:catalog:geo:1` for maps, public tile servers allowed, no client API keys.
- **Failed runs:** retry automatically up to N times (default 2), then ask "Do you want to try again?".
- **First Run:** show "Loading Monty" while the runtime starts.

## Source to build on (local)

| Path | What |
| --- | --- |
| `~/dev/soliplex-frontend-wt/exp-dojo-a2ui` | soliplex/frontend `origin/main` `482879f8` plus the A2UI port. It has injected surface catalogs (`standardFlavor(surfaceCatalogs:)`), the `soliplex_monty` plugin (lab catalog, `PythonRepl`, Python `ui` bridge) and a type-to-focus fix in `room_screen.dart`. Branch `exp/dojo-a2ui`, uncommitted. Other agents may be editing it. **Copy it into your own worktree**, do not edit it. |
| `~/dev/soliplex-frontend-a2ui-embed` | earlier A2UI work: ADR-001 to ADR-008 in `docs/adr/`, action-only turns, the embedded conversation controller. Read-only. |
| `~/dev/soliplex-a2ui-monty` | the shared monorepo (local, not pushed). Packages `soliplex_monty`, `soliplex_monty_workspace`, `soliplex_catalogs`, the lab app, the benchmark, and `docs/A2UI-0.8-MIGRATION.md`. Read-only. |
| `~/dev/soliplex-embed-probe/lib/lab/` | the most up-to-date lab code: workspace mount, CSV graphing, lab `BarChart`, tests. Read-only. |
| `~/dev/soliplex-a2ui-lab/src/soliplex_a2ui_lab/` | a backend tool publishing A2UI surfaces as AG-UI `ACTIVITY_SNAPSHOT` (activity type `a2ui-surface`) from `ToolReturn.metadata`. `show_python_repl(source, title)` loads model-written code. Copy it, do not edit it. |
| `~/dev/soliplex` (`git show origin/main:<path>`) | backend docs: `docs/config/{rooms,agents,agui,skills}.md` |
| `~/dev/soliplex-template` | the stack generator. Read `skills/soliplex-template/SKILL.md`. |
| `~/.pub-cache/hosted/pub.dev/a2ui_*` | A2UI Dart sources. Python SDK and catalogs are at `a2ui-project/a2ui` on GitHub. |

## Gotchas already found (do not rediscover)

- **Template generator:**
  - It prints DB passwords and the ingester token to stdout. Rotate them before the first start, and never echo secrets.
  - It has known bugs on `main` `4d9b4b8`: Docker 29 `/tmp` permissions (#345), nginx and Authelia port mismatches after a port remap, and `add` failing on a new Authelia store. `a2ui-lab-stack.md` lists the fixes.
- **Authelia users:**
  - The password reset script looks users up by full email, but the `$WB_ADMIN_USER` user is keyed `$WB_ADMIN_USER`.
  - To set `$WB_ADMIN_USER` with a password the operator chooses, use the script's `_generate_hash` and write `users.yml` in place.
- **macOS single-file bind mounts** break when a file is replaced, as `sed -i` does. Write files in place, or use `docker compose up -d --force-recreate <service>`. Authelia's file watcher can lag a few seconds behind the change.
- **nginx:**
  - The template sets `limit_rate 1024k` per server. Add a static-asset location with `limit_rate 0` to **both** server blocks (the HTTP one and the TLS one on 9443).
  - Add `application/wasm` to `gzip_types`. The Monty worker wasm then goes from 17.7 MB to 7 MB, and from 17 s to 0.2 s.
  - Restart nginx after replacing the web build.
- **Browser builds:**
  - Under dart2js, `1 << 32` is 0, so `Random.secure().nextInt(1 << 32)` throws. Use `0x7fffffff`, and run pure-Dart tests on Chrome too.
  - Flutter's service worker caches old builds, so hard reload after a deploy.
- **Type-to-focus:** the room screen's handler moves focus to the composer on any keystroke. It needs a guard for other focused text fields. That guard is in `exp-dojo-a2ui` `room_screen.dart`, as `_anotherTextFieldHasFocus`.
- **Models and Monty:**
  - Without being told, models write `tkinter`. Give them the `ui` API in a room skill (preferred) or the prompt.
  - Monty has no `io` and no third-party packages, and `from x import *` is not supported.
  - Names starting with `_` cannot be imported from host modules.
  - E4B tends to mutate built widgets (`root.children.append`), and widget handles are opaque.
- **Browser driving:** a lightweight headless browser driver is available (`server.mjs`, `lib.mjs`, `e.sh`). Copy it for your stack rather than using screenshots through MCP for everything.

## Phase 1: design (stop for the owner at the end)

Write `~/dev/plans/soliplex-a2ui/workbench/WORKBENCH-DESIGN.md` covering:

1. **Layout model.**
   - Regions: chat, left and right side bars, a main canvas or grid, floating windows, and a bottom tray.
   - How a surface is placed, moved, resized, minimised or closed.
   - What the user can do versus what the agent can do.
   - How the layout survives reload and replay.
2. **The protocol.** How the agent addresses layout. Compare at least:
   - (a) a Soliplex `layout` catalog (components such as `Panel`, `Sidebar`, `Window`, `Grid` that hold surfaces).
   - (b) a placement field on the AG-UI activity, next to `a2ui_operations`.
   - (c) a separate layout surface whose data model the agent updates.

   Pick one with reasons, citing ADR-004 and ADR-005 (module composition and layering) and how `RoomScreen` is built today.
3. **Agent tools.** The server tools the room's model gets: open a panel, place a form, show a chart, launch a mini program, close or rearrange. Give each a typed schema, for E4B reliability. Say how they use `soliplex-a2ui`, and how the model learns the available catalogs and layout (a room skill).
4. **Forms and capture.** A form surface submits a typed action: Track A contract, action-only turn, validation before the model.
5. **Mini programs.**
   - A `PythonRepl` or Python-built surface in its own window, with the Monty session per surface.
   - Can mini programs talk to each other or to the layout (for example a program that opens a chart)?
   - Where the safety boundary sits.
6. **Charts and tables.** Use `fl_chart`, and a table from the basic catalog or a new component. Selection is linked across panels with shared bound paths.
7. **Persistence and replay.** Which state is server-owned (layout, accepted surfaces) and which is client-local (window positions, drafts), and what replay restores without running code.
8. **Fit with the existing frontend.** What changes in `soliplex/frontend` (a new flavor or a workbench module) versus the plugin, and how the standard chat keeps working unchanged.
9. **A phased build plan**, with sizes and model-free acceptance tests, plus a live demo script for both models.
10. **`DECISION:` items** for the owner.

Make 2 or 3 layout mockups as simple ASCII or SVG. Then stop and summarise for the owner.

## Phase 2: second install (in parallel with phase 1)

1. Fast-forward `~/dev/soliplex-template` to `origin/main` if it is clean. If it is on another branch, do not switch it: clone a copy instead. Generate `~/dev/soliplex-a2ui-workbench` with ports 9700 and 9743, Authelia, and Glimmer for chat.
2. Embeddings: `http://MODEL_HOST:11438/v1`, dimension 2048, nemotron. Rerank on `:11434`.
3. Set up Authelia with user `$WB_ADMIN_USER`, a password the operator chooses, and admin rights. Rotate the generated secrets.
4. Apply the nginx gzip and rate-limit fixes.
5. Deploy the current `exp-dojo-a2ui` plugin example build, a copy, so the stack starts with the A2UI lab capability. Verify sign-in, a room, and Python running in the browser, with screenshots.
6. Write `~/dev/plans/soliplex-a2ui/workbench/STACK.md` with the steps, the adaptations, and the verification.

## Phase 3: prototype (only after the owner approves the design)

Build in a new frontend worktree, `git -C ~/dev/soliplex-frontend-a2ui-embed worktree add -b exp/workbench ~/dev/soliplex-frontend-wt/exp-workbench origin/main`, then port what you need. Build the agent tools in the workbench stack's own tool package. Deliver:

- a working layout with chat, a side bar, a canvas and a window.
- agent tools to place a form, a chart and a mini program.
- tests and gates.
- a live demo on both models, with screenshots.

## Report

At the end of each phase give a short summary:

- the files written.
- decisions needed.
- the stack URL and sign-in.
- what works and what does not, with evidence.

## Owner direction: which side Python runs on (added 2026-11-19)

Make the side explicit everywhere:

- **Tools.** Expose `run_python_client` (browser Monty, `ui`, mounted workspace files, runs on a user gesture) and `run_python_server` (server sandbox or server Monty, server data, unattended within limits) as distinct tools.
- **Traces.** Tag every run `python.side=client|server` with engine version, room, thread, surface and chain id. Client runs reach Logfire through the run-result actions the server records. No Logfire token goes in the browser.
- **Handoffs.** Interpreter state goes in a thread workspace file. The AG-UI state carries only a pointer, `{side, engine, dump: <file id>, sha256, owner, hop}`, never the dump bytes, which can be 3.5 KB to 4 MB and would be re-sent and re-stored every turn.

The lab stack sends traces to Logfire project `default`, service `soliplex-a2ui-lab`. The new stack should use its own service name. The token is in `~/dev/.env` as `LOGFIRE_TOKEN`. Wire it as a secret file plus `logfire_config` with `token: "secret:LOGFIRE_TOKEN"` and `send_to_logfire: true`.

## Owner direction: nested layouts (added 2026-11-19)

The workbench layout must nest:

- panels inside side bars.
- split panes inside the canvas.
- tabs inside panels.
- windows that hold their own layouts.
- a mini program's surface inside a window inside a region.

Design the layout model as a tree, not a fixed set of slots. For the tree, state:

- which nodes the agent may create or move.
- the maximum depth.
- how a node is addressed: a stable id, not a path that breaks when a parent moves.
- what happens to children when a parent closes.
- how the tree persists and replays.

Component-level nesting (Rows, Columns, Cards, Tabs and Lists inside each other) is being measured separately in `~/dev/plans/soliplex-a2ui/nested-layouts.md`. Read it when it exists, including its findings on overflow, responsive width and model authoring.
