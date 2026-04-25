# Watching code execute as a first-class UX

Status: design — for next architecture sprint
Owner: alan@enfoldsystems.com
Date: 2026-04-25
Related:
- `docs/plans/message-containers.md` (the registry this depends on)
- `docs/plans/monty-debugger-stepper.md` (the v0 stepper plan;
  shares state with the surfaces below)
- `docs/lessons-learned-monty-maps.md` §6, §13 (singleton + factory
  lifecycle constraints this design must satisfy)

---

## Problem

The user pastes Python in the Monty terminal and runs it. The script
calls `map_fly_to`, `map_add_marker`, etc. — and the visible result
is camera motion, markers appearing, paths drawing. Two things go
wrong with the current implementation:

1. **The terminal modal blocks the map.** The dialog is centered on
   screen, opaque, and 720×640. The user can't see the camera fly
   while the dialog is open. They have to close it to watch — but:
2. **Closing the dialog disposes the runtime mid-run.** `TerminalPanel`
   constructs its own `MontyRuntime` in `initState` and disposes it
   in `dispose`. Closing the dialog tears down the runtime; any
   `map_fly_to` mid-animation freezes half-way; the rest of the
   script never executes.

Net effect: **the user can't both watch the map and run a script**.
This is the central use case of the maps room. The mismatch is
architectural, not a bug to patch.

The lesson from `lessons-learned-monty-maps.md` §13 (`MontyExtensionSet`
must be a factory) and §6 (`MapExtension` is a singleton) is the
same shape playing out one level up: **runtime lifetime needs to
match script lifetime, not UI lifetime.** A modal dialog's lifetime
is the wrong scope.

## Why this matters beyond the immediate bug

The whole appeal of the maps room (and the broader monty-on-device
story) is "the agent or user runs Python, you watch its effects."
That's also the heart of the
`docs/plans/monty-debugger-stepper.md` proposal — see code execute
line by line. And it's what the `docs/plans/message-containers.md`
registry is ultimately for: pluggable surfaces that *show* what the
runtime is doing.

Right now we have three surfaces with three different lifetime
shapes that don't compose:

| Surface           | Lifetime              | Runtime ownership            |
|-------------------|-----------------------|------------------------------|
| Map (`MapView`)   | App-singleton         | Reads `mapExtension` signals |
| Terminal panel    | Dialog (per-open)     | Owns its own `MontyRuntime`  |
| Debugger (planned)| Per-RoomScreen        | Owns its own `MontyRuntime`  |
| LLM `run_python`  | Per-AgentSession      | `MontyRuntimeExtension`'s    |

Four runtimes drifting through three lifetimes; the map is the only
shared point. **None of these surfaces can compose** — opening one
doesn't help you observe another.

## Goal — what "code execute as first-class" actually means

Three properties the UI should have:

1. **The map is always visible** when a script is running. Not partially
   covered by a modal. Not behind a draggable picture-in-picture. The
   map gets the full viewport; everything else is non-blocking
   ornament.
2. **The script (source + state + tool-call timeline) is visible at
   the same time as the map.** Not "open this dialog to see the
   code, close it to see the map" — both, simultaneously, in
   peripheral vision.
3. **Lifetime is the script's, not the dialog's.** Closing a panel
   should not abort the script. Opening a panel mid-run should attach
   to the existing execution and show what's already happened.

## Layout proposals

Three viable shapes, ranked from least invasive to most ambitious:

### A. Bottom-sheet panel (smallest delta from today)

Replace `showDialog` with a `Scaffold.bottomSheet` (non-modal) that
lives at the bottom 30–40% of the screen. Map gets the top 60–70%.
Pannable up/down to reclaim space. Dismissible to a small handle.

Pros:
- Smallest change — keeps the same widgets, just re-mounts them
- Already-familiar pattern (chat, document drawer)

Cons:
- Bottom-sheet is still a "panel" — feels less like a permanent
  workspace
- Vertical squeeze on the map may not be acceptable for cinematic flies

### B. Persistent side panel (the IDE pattern)

Right side of the room screen mounts a permanent panel: source on
top, state inspector middle, tool-call timeline bottom. Map fills
the left. A toggle button collapses the panel to a strip.

Pros:
- Mirrors how every IDE works — engineers will recognize the layout
- Source + map both have plenty of room
- Natural home for the debugger stepper's three panes

Cons:
- Needs responsive logic for narrow/mobile viewports
- More chrome on the screen at all times

### C. Inline-in-chat container blocks (the containers plan, fully realized)

Code lives in chat as a fenced block; the chat scrolls under the
camera. As the script executes, the block updates: line highlights,
state appears beside it, results stream in. Map is the canvas; chat
is the script log; the room is the entire page.

Pros:
- Most cohesive story — one timeline, one viewport, no panels
- Aligns directly with the message-containers plan
- Chat-first: conversational, with code as a normal message kind

Cons:
- Most ambitious refactor — every container kind needs to render
  inline in chat AND optionally as a full surface
- Hardest to retrofit; touches `code_block_builder.dart`, message
  rendering, scroll behavior, state bridging

## Proposal — staged path A → B → C

### Phase 1 (this sprint) — Bottom sheet + detached runtime lifecycle

Goal: stop losing scripts when the dialog closes. Make the map at
least partially visible during runs.

- Replace `showDialog` mounting of `TerminalPanel` with a
  `PersistentBottomSheetController` mounted on the room's
  `Scaffold`. The sheet is non-modal; the map underneath is
  interactive.
- Detach the `MontyRuntime` from the panel's `dispose()`. When the
  sheet closes with a run in flight, schedule disposal via
  `inflight.whenComplete(runtime.dispose)`. The script keeps running;
  any `map_*` calls keep firing against the singleton `mapExtension`.
- Add a "minimize" affordance: collapse the sheet to a 36px-tall
  status pill while a run is active. The pill shows "running:
  &lt;function name&gt;" with a stop button. Tap to expand.

Files touched:
- `lib/src/modules/room/ui/room_screen.dart` (mount the sheet)
- `lib/src/modules/room/ui/terminal_panel.dart` (lifecycle detach)

This is ~150 LOC total. Ships the immediate UX win.

### Phase 2 (next sprint) — Side panel + debugger stepper

Goal: source/state/timeline visible alongside the map. Debugger
controls (step, pause, reset) become a normal part of the workspace.

- Land `MontyDebuggerExtension` per `docs/plans/monty-debugger-stepper.md`.
- Reorganise the room screen so the debugger panel mounts on the
  RIGHT side as a collapsible IDE-style pane. Map fills the LEFT.
- Phase 1's bottom sheet either folds into the debugger panel
  (terminal becomes the input pane of the debugger) or stays as a
  separate "scratch" overlay. Probably folds in — one place to type,
  one place to inspect.
- Lifetime is per-room (not per-script) — open the panel, inspect
  the latest run, close it; reopen later, see history.

Files touched:
- `lib/src/modules/room/monty_debugger_extension.dart` (new)
- `lib/src/modules/room/ui/debugger_panel.dart` (new)
- `lib/src/modules/room/ui/source_view.dart` (new)
- `lib/src/modules/room/ui/room_screen.dart` (split horizontally)
- `lib/src/modules/room/ui/terminal_panel.dart` (delete or fold in)

### Phase 3 (later) — Containers in chat

Goal: code blocks in chat become live containers (map, debugger,
terminal) when the LLM emits the right fence syntax. Closes the loop
on `docs/plans/message-containers.md`.

- Implement `ContainerRegistry` per the message-containers plan.
- Migrate `MapView`, `TerminalPanel`/debugger inputs, and
  `DebuggerPanel` to be alternative renderers for `(id, kind)`.
- `code_block_builder.dart` recognises ` ```container {...} ` blocks
  and resolves them through the registry.
- Runtime lifetime becomes container-scoped: the LLM (or the user)
  spawns a container with a stable id; both the chat block and any
  full-screen surface attach to the same container; closing one view
  does nothing to the runtime.

This is the message-containers plan in concrete form, validated by
having three real container kinds (map, terminal, debugger) plus
a real demand pattern (the user pasting a script and watching it).

## Acceptance criteria

For phase 1 (the sprint deliverable):

- [ ] Pasting a script and clicking Run shows the map throughout the run.
- [ ] Closing the terminal sheet during a run does NOT stop the
      script. `map_fly_to`, `map_add_marker`, `map_move_marker` all
      complete to their `duration_ms`.
- [ ] When a run completes after the sheet has closed, a snackbar or
      toast surfaces "Script done" with a "View output" action that
      re-opens the sheet to show the result block in history.
- [ ] No regression in the LLM `run_python_on_device` path (which
      uses a different runtime).

For phase 2:

- [ ] Source / state / timeline visible alongside the map without
      pop-up modals.
- [ ] Pause / step / continue / reset all functional per the
      debugger plan.
- [ ] Lifetime per room: navigate away and back, panel state restored.

For phase 3:

- [ ] LLM can emit a `container` fence and the chat renders it as
      the right kind.
- [ ] Container survives chat scroll, agent turn boundaries, and
      session re-attaches.

## Risks

- **Bottom-sheet on web Chrome can be wonky.** Flutter's
  `showBottomSheet` doesn't handle keyboard avoidance the same way
  on web as on mobile. Test carefully; might need `BackdropFilter`
  workarounds.
- **Detached runtime leaks if `whenComplete` doesn't fire.** A
  runtime that's awaiting an external event (HTTP, debugger pause)
  could outlive the panel indefinitely. Add a hard-deadline disposer
  (15s? 60s?) as a backstop.
- **Phase 2 layout breaks at narrow widths.** Need responsive
  collapse-to-pill behaviour like the debug console pattern in the
  earlier `feat/m4-python-ui-basics` branch.
- **Phase 3 is a large refactor.** Don't start until phase 2 has
  shipped and the `Container` abstraction has been used in anger.

## Non-goals

- No multi-pane drag-resize for phase 1 — fixed proportions.
- No cross-script state sharing in phase 1 — each run is its own
  runtime as today.
- No "rerun" or "edit and re-run" affordance until phase 2.

## Done when

Phase 1 ships and a user can:
1. Paste `docs/installation/rooms/maps/showcase_tour.py`.
2. Click Run and immediately see the map fly across continents.
3. The bottom sheet stays out of the cinematic part of the viewport.
4. Closing the sheet doesn't abort the helicopter mid-flight.
5. Reopening the sheet after the run shows the completed history
   block.
