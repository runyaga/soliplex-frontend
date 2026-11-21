# Soliplex Workbench: feature set for review

You are reviewing the "workbench", an experimental frontend for Soliplex. Your job is to judge what it can do, find the gaps, and propose demos that are truly interesting to a technical audience. The current demos lack polish and do not push the envelope. Be candid. Filler demos are worse than none.

## Stack

- Soliplex backend (FastAPI, pydantic-ai agents, AG-UI streaming protocol, OIDC login). Each room has an agent, tools, a system prompt and clickable suggestions.
- Flutter web frontend. Chat on the left, a workspace on the right: a canvas, left and right sidebars and a bottom tray.
- A2UI: the agent publishes declarative UI surfaces (component trees with data bindings) as AG-UI activity events. The client renders them from registered component catalogs.
- Monty: a sandboxed Python interpreter that runs in the browser (WASM worker), with resource limits. Python programs run on the client, never on the server.
- Models: "Glimmer" (a local model, the main target) and Gemma 4 E4B (a small local model). Both are weaker than frontier models, so every demo must work on them.

## Where the code is

Repository: this repository (a public fork of soliplex-frontend), branch `exp/workbench-preview`. Each change is built on its own `exp/workbench-*` branch and merged into the preview branch. The preview branch is deployed to a local stack.

| Path | What it does |
| --- | --- |
| `lib/src/modules/room/workbench/` | The Flutter workbench: host and canvas layout, regions, windows, program app windows, walkthrough player |
| `packages/soliplex_monty/` | The Monty Python integration: the program editor and run log (`lib/src/lab_catalog.dart`), the `ui` module for program GUIs, events, type check, AI Fix repair chain, resource limits |
| `packages/soliplex_monty/example/` | A standalone app and tests for the Monty widgets |
| `packages/soliplex_catalogs/` and chart code | A2UI component catalogs, charts included |
| `workbench/backend/soliplex_a2ui_workbench/` | The server side: agent tools (`workbench_tools.py`, `workbench_agent_tools.py`), layout store and projection, route guards and action handling (`workbench_routes.py`, `workbench_actions.py`), forms and CSV results, chart validation, curated demo programs, the walkthrough, and model teaching with room suggestions (`workbench_teaching.py`) |
| `workbench/stack/` | Scripts that configure rooms and build and deploy the stack (`setup-stack.sh`, `compose_config.py`) |
| `workbench/scenarios/` | The Playwright harness: deterministic checks, model cases (`model/prompts.yaml`), walkthrough checkpoints and unit tests |
| `workbench/docs/` | Lessons learned (`LESSONS.md`), work orders and test evidence |

## What works today

Layout and surfaces

- The agent places surfaces through server-validated tools: forms, charts, text panels, tabs, split containers, windows, Python programs. The server holds the layout tree with stable ids and limits (64 nodes).
- The agent can move, close and reopen surfaces, and read the current layout with `get_workbench`.
- The layout and content persist with the thread and survive reload.

Forms

- Built-in intake template, or custom forms with field kinds text, textarea, number, choice, checkbox and date. Limits are 12 fields and 12 options.
- The server rejects credential fields (password, token, PIN and similar) with a corrective error.
- Submit is validated server side and appended to `<form-slug>.csv` in the thread's workdir. Submissions are deduplicated, and cells are escaped against formula injection.
- The submission reaches the model as untrusted data. The model can read results with `read_form_results`.

Charts

- Line, bar and pie charts work live, with accessible labels. Scatter, radar, candlestick and gauge exist but are untested live.
- Known bugs: a pie chart clips in the sidebar, the dark-mode pie hides one slice and its legend, and the line chart's x-axis drops its last label.

Python programs (Monty)

- The agent writes a program into a window with an editor, Run, a run log and "Show code". Programs run only when the user presses Run. Model-written code never runs by itself.
- A program can build a GUI through a `ui` module (labels, buttons, inputs, charts). The GUI appears in a separate app window. Button clicks call `handle_event` in the retained Python session, so state persists between events.
- A program can open, move and close workbench windows through the same server-validated layout path the agent uses.
- After a Run, the output goes to the model, which can answer questions about it (for example, "sum of primes below 50000").
- AI Fix (a checkbox, off by default): when a run fails, the model repairs the program in place and the fix runs once by itself. Verified live: NameError, SyntaxError and type errors.
- Type check (a checkbox, off by default): a type checker runs before execution and blocks type errors, even in code that never runs.

Walkthrough

- "Start the walkthrough." plays 17 narrated, paced steps without the model: charts, moving a chart, a custom form filled and submitted to CSV, the Monty GUI demo driven by clicks, a log window, and cleanup. It has Stop, Pause and Next. Clicking Start permits only the curated programs to run.

Suggestions in the room today

- Start the walkthrough.
- Open the Monty GUI demo.
- Team survey form saving to CSV.
- A dashboard with a line chart and a bar chart.
- A primes program the model reports on after Run.
- Syntax error, NameError and type check examples for AI Fix.

Testing

- A Playwright harness drives the deployed app headless. It has a deterministic suite and a model suite of 22 cases, which pass 21 of 22 on Glimmer.

In progress, not merged

- Programs read and write thread files (.csv, .md, .txt, .json) through the server, scoped to the thread.
- The model reads a running program's app state as untrusted data. Example: a to-do app, then "what's left?".

Known gaps and rough edges

- Room info does not list client-side tools, and the chat timeline does not distinguish client tool calls from server tool calls.
- The composer sometimes drops the first character after a click.
- A form's title shows twice.
- A stray "Run finished without a response" bubble appears after layout actions.
- Walkthrough step 16 skips AI Fix instead of showing it.
- A small model in a thread that already holds a bad answer tends to repeat it.

## Three complex demos to start from

These are starting points to critique, not a spec. Each one combines several features. Each also needs the in-progress file and app-state work.

### 1. From survey to decision (hands-on)

1. The user asks for a field survey. The model places a custom form in the left sidebar: site, region (choice), satisfaction 1 to 5, issue (textarea).
2. The user submits four or five entries. Each one is validated and appended to `field-survey.csv`.
3. The user asks for an analysis app. The model writes a Python program. On Run, it reads the CSV and opens an app window with a bar chart by region, a pie chart of issues, and filter buttons. A click on a region redraws the charts through `handle_event`.
4. The user asks "which region needs attention and why?". The model answers from the app's state and the CSV, both treated as untrusted data. It then saves `summary.md` to the thread.

It shows the path from form to file to program to chart to model reasoning, with every step validated and kept with the thread.

### 2. A data pipeline that fixes itself (sit back and watch, or hands-on)

1. The model writes a pipeline that parses `sales.csv`, totals by month and charts the result.
2. Type check is on and blocks a type bug before anything runs.
3. With Type check passing, the first Run fails on a malformed row (`ValueError`).
4. AI Fix repairs the program to skip and count bad rows. The fix runs by itself, the chart appears in its own window, and the program writes `clean.csv`.
5. The user asks "how many rows were dropped?" and the model answers from the run output.

It shows type checking, automatic repair and rerun, file output and charts, all in the browser sandbox.

### 3. Incident console (hands-on)

1. A curated Python program simulates a service. It opens a console window with Start, Tick and Inject fault buttons and a live latency line chart.
2. When latency crosses a threshold, the program opens a log window and moves the chart beside it, through the validated layout path.
3. The user asks "what happened at tick 12?". The model reads the app state and explains.
4. The model places a prefilled incident report form. The user edits and submits it to `incidents.csv`.

It shows a Python program driving the workspace layout, the model reasoning over live app state, and a closed loop back into a validated form.

## Constraints a demo must respect

- Untrusted data (form input, file contents, program output, app state) never acts as instructions to the model.
- Model-written code runs only on a user click. Only curated programs may auto-run, inside the walkthrough.
- Every layout change goes through server validation.
- Demos must work on a small local model, so prefer flows where the model makes few, simple tool calls.

## What I want from you

1. Your read of what is unusual here compared with a plain chat UI, in a few lines.
2. Gaps that block impressive demos, ranked by impact. Separate missing capability from polish.
3. Eight to twelve demo proposals. For each:
   - the pitch;
   - the user's actions and the model's moves, step by step;
   - which capabilities it uses;
   - what must be built first, sized S, M or L;
   - why a technical audience would care;
   - the risk on a small model.

   Mark each one as sit-back-and-watch or hands-on, and rank them by interest per unit of work.
4. A polish list for the existing demos.
