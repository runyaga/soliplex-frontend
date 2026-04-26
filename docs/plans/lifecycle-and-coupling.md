# Lifecycle and coupling map — soliplex client stack

A reference for "who writes to what, at what lifecycle, through which
coordinator." Captured because every shipped bug in the GenUI work
was a lifecycle-scope mismatch, and we're about to add JS
bidirectional bindings (and eventually OsCall callbacks) — both of
which are *new writer sources*. Without an explicit coupling map
the dual-extension / scope-mismatch problems compound.

This sits alongside `genui-build-lessons.md` (the bug post-mortems)
and `message-containers.md` (the original sketch). It is reference,
not narrative.

## Seven lifecycle scopes

```text
process ── app ── server ── thread ── session ── run ── mount
   │       │        │         │          │        │       │
   │       │        │         │          │        │       └─ Flutter widget instance
   │       │        │         │          │        └─ One AG-UI run inside a session
   │       │        │         │          └─ One AgentSession (LLM exchange + tool yield/resume)
   │       │        │         └─ One ThreadViewState + StateBus + AgentRuntime._threadHistories[threadId]
   │       │        └─ One AgentRuntime + ServerConnection + AgentLlmProvider (one per backend)
   │       └─ Process-wide singletons (mapExtension, narrationController, …)
   └─ Dart isolate
```

Six distinct intermediate scopes between process and Flutter. State
written at one scope must be observed at another, every time. That
crossing is where bugs live.

The **server** scope is easy to miss because today most apps have one
backend, but `AgentRuntime` is constructed per `ServerConnection` —
the multi-server lobby has N runtimes. Anything cached on the
runtime (notably `_threadHistories`) is per-server, not per-app.

## Two coordinator hierarchies

We have **two** "extension" types managed by **two** different
coordinators in **two** different packages:

| Coordinator | Package | Manages | Lifecycle |
| --- | --- | --- | --- |
| `SessionCoordinator` | `soliplex_agent` | `SessionExtension`s (attach / dispose / namespace lookup) | per-session |
| `ExtensionCoordinator` | `dart_monty_bridge` (used in `dart_monty`) | `MontyExtension`s inside one `MontyRuntime` (host-function registration / collision check) | per-runtime |

The bridging type `MontyRuntimeExtension` is itself a
`SessionExtension` *and* it owns a `MontyRuntime` containing many
`MontyExtension`s. So the two coordinators nest:

```text
AgentRuntime  (per-server; owns ServerConnection + _threadHistories cache + SessionExtensionFactory)
  └── AgentSession  (spawned via runtime.spawn; receives cachedHistory from _threadHistories[threadId])
       └── SessionCoordinator
       ├── ExecutionTrackerExtension     (SessionExtension)
       ├── ToolCallsExtension            (SessionExtension)
       ├── HumanApprovalExtension        (SessionExtension)
       ├── MapExtension                  (SessionExtension)
       └── MontyRuntimeExtension         (SessionExtension)
            └── MontyRuntime
                 └── ExtensionCoordinator
                      ├── HttpMontyExtension      (MontyExtension)
                      ├── MapMontyExtension       (MontyExtension) ─┐
                      └── NarrationMontyExtension (MontyExtension) ─┤
                                                                    │
                                                                    │ writes through to
                                                                    ▼
            ┌──────────────────────────────────────────────────┐
            │ Surface singletons (app-scope)                   │
            │ mapExtension, narrationController                │
            └──────────────────────────────────────────────────┘
                                 ▲
                                 │ also written by:
                       ┌─────────┼─────────┐
                       │         │         │
              [LLM tool calls]   │   [Per-thread StateBus projections]
              (per-session)      │   (per-thread)
                                 │
                  [JS bidirectional bindings]   ← future
                  (per-mount, write-back to bus)
                                 │
                  [OsCall handlers]              ← future
                  (per-runtime, fs/shell callbacks)
```

Two seams on `AgentRuntime` are load-bearing for bugs we already
hit:

- `SessionExtensionFactory` (`agent_runtime.dart:344`) is the *only*
  per-server → per-session bridge. Item #6 (one model for
  `MapExtension`) is really a question about what this factory
  returns: a fresh per-session bridge to an app-singleton, or the
  controller itself as a `SessionExtension`.
- `_threadHistories` (`:92`, `:426–451`) is per-server, per-thread,
  and survives session boundaries. The reload-persistence fix
  (Lesson #9) works because the bus is reseeded from
  `cachedHistory.aguiState` on every spawn — the cache lives on the
  runtime, not the bus and not the session.

The naming collision (`SessionExtension` vs `MontyExtension`) is the
single biggest cognitive-cost item in the stack — same word, different
base class, different lifecycle, different coordinator. The
architecture review's item #1 (rename `SessionExtension` →
`SessionPlugin` or `SessionCapability`) targets this.

## Writer sources today (three) and tomorrow (five)

Every reactive piece of state on the client is written by at least
one of these sources. Surface singletons (`mapExtension`,
`narrationController`) are written by *all three* today.

| # | Writer | Scope | Path |
| --- | --- | --- | --- |
| 1 | **AG-UI state events** (`StateSnapshotEvent` / `StateDeltaEvent`) | per-event → per-run → per-thread | `processEvent` → `Conversation.aguiState` → `AgentSession.agentState` signal → `StateBus.setAgentState` → projections → singletons |
| 2 | **LLM `ClientTool` calls** | per-session | `RunOrchestrator` yields → `ToolRegistry.execute` → `ClientTool.executor` → singleton imperative method |
| 3 | **Monty Python externals** | per-runtime (per-session) | `runtime.execute(code)` → Python calls `monty.map_*` → `HostFunction` handler → singleton imperative method |
| 4 | **JS bidirectional bindings** *(future)* | per-mount → per-thread | JS event → `@JSExport` callback → `Surface.emit(SurfaceEvent)` → `StateBus.events` → forwarded to agent (next agent run reads it back as state) |
| 5 | **OsCall handlers** *(future)* | per-runtime → per-thread | filesystem watcher / shell callback → `Surface.emit(SurfaceEvent)` → same path as #4 |

Reads happen at:

- **Mount** (`MapView`, `NarrationPanel`, `WidgetTreePanel`,
  `_HudChild`, future JS-rendered surfaces) — Flutter widgets
  watching surface signals or projection signals.
- **Run** — `RunOrchestrator` reads `Conversation` for
  resumption / tool yield decisions.
- **Session** — `AgentSession` reads `RunState` for lifecycle.

## The intersection: surface singletons

All three current writers and both future writers converge on the
same handful of objects:

- `mapExtension` (markers / sprites / polylines / polygons / huds /
  viewport) — a single `Signal` per data type, mutable from at
  least four directions.
- `narrationController` (entries) — singleton with a single stable
  signal.
- `WidgetCatalog`-rendered widgets via `WidgetTreeProjection` —
  read-only from agent state today.

The "last writer wins" rule is implicit. Today it's mostly
non-conflicting (LLM tool calls happen serially with state events
because the LLM emits both before the run completes; Monty externals
fire only when a `run_python_on_device` tool is in flight). When JS
bindings land, conflict windows widen — a user dragging a marker
while the agent is also moving it via a state delta will race.

## Lifecycle mismatches we hit (and named)

Each shipped bug was a scope mismatch:

| Bug | Mismatch | Fix | Lesson |
| --- | --- | --- | --- |
| Initial snapshot rendered, but moves didn't propagate to panels | per-thread bus was reconstructed on every session attach; surface singletons stayed wired to the old projection | `_wireSurfaceSingletons` runs on attach (couples per-session to per-thread) | #8 |
| Browser reload wiped the map | Bus was per-session; reload has no session | Bus promoted to per-thread, seeded from `history.aguiState` | #9 |
| Replay ran but narration panel stayed blank | `wireProjection` swapped the underlying signal; `Watch` stayed bound to the old one | One stable signal forwarded into | #11 |
| Convoy sprite jittered, camera arc broken | Two writers (diff-apply tween + camera-follow) on one per-mount tween primitive | `registerExternalSpriteFollower` / suppress diff-apply tween for followed ids | (this PR) |
| MapExtension's double registration | Same controller registered as per-session `SessionExtension` AND as app-singleton (`maps_singleton.dart`) — `wire*Projection` exists *because* of this duplication | Pick one model (review item #6) | (open) |

## The consolidation items, mapped to this picture

Architecture review's items 1–3 + 6 each attack a specific scope
mismatch:

- **#1 Rename `SessionExtension`** → makes the two coordinator
  hierarchies explicit by name. Newcomer instantly sees "this is the
  per-session plugin coordinator" vs "this is the per-runtime
  external coordinator."
- **#2 Delete `StateUpdated` ExecutionEvent** → removes a sealed
  variant nothing writes; consolidates state-change semantics on the
  signal (`agentState`) instead of the stream (`stateChanges`).
- **#3 Collapse three lifecycle types** (`ConversationStatus`,
  `RunState`, `AgentSessionState`) → makes the lifecycle hierarchy
  one named thing.
- **#6 Pick one model for `MapExtension`** (singleton OR
  session-extension, not both) → eliminates `wire*Projection` as
  glue between two scopes for the same controller.

Items 4, 5, 7, 8 don't change scopes; they're cohesion fixes
(documentation, single-sourcing).

## What changes when JS bindings land

A JS-bridged surface (e.g. CodeMirror) introduces a fourth writer
*and* a new coordinator-style problem:

1. **The JS instance is per-mount** but it can outlive a Flutter
   widget rebuild if the host page survives. So its lifecycle is
   actually closer to "per-thread" if backed by `HtmlElementView`
   reuse. Need to be explicit about that.

2. **Bidirectional means two-way coupling.** The agent emits state →
   JS renders. The user types in JS → `Surface.emit` →
   `StateBus.events` → forwarded to agent → agent emits state →
   JS re-renders. Loop closed. Without explicit lifecycle ownership
   of the JS instance vs the bus subscription, the loop can fire
   before the agent has acknowledged, causing flicker / fighting
   updates.

3. **A JS-bridged surface will want both an LLM-tool surface AND a
   script-callable surface** (so the agent can also drive it via
   tools, and Python scripts can drive it via externals). That
   means a `CodeMirrorExtension` (`SessionExtension`) PAIRED with a
   `CodeMirrorMontyExtension` (`MontyExtension`) — repeating the
   `MapExtension` / `MapMontyExtension` pattern. Item #6 (pick one
   model) becomes more pressing because every new surface
   compounds the duplication.

4. **JS↔Dart communication itself has lifecycle gotchas.** The JS
   instance must be cleanly disposable when the Flutter element
   unmounts, must reattach when re-mounted (or the host has to keep
   it alive), and must coordinate with the per-thread `StateBus`
   without leaking subscriptions. Documenting the JS-instance
   lifecycle as a separate scope ("per-mount-but-cached"?) is its
   own one-paragraph-doc work.

## Recommendation for sequencing JS work

Do the consolidation (items 1–3 + 6) first. Then JS-bridged
surfaces become a clean **fifth writer source** with one
coordinator type and one extension hierarchy, instead of compounding
the dual-extension problem:

```text
Today (3 writers, 2 coordinator hierarchies):
  AG-UI events / ClientTool / MontyExtension
       │
   [SessionCoordinator + ExtensionCoordinator]
       │
       ▼
   surface singletons

After consolidation (3 writers, 1 plugin model):
  AG-UI events / SessionPlugin / SessionPlugin
                  └─ tool functions  └─ runtime externals
       │
   [one SessionPlugin coordinator]
       │
       ▼
   surface singletons (single home, single registration)

Then JS extension (4 writers, same 1 plugin model):
  AG-UI events / SessionPlugin / SessionPlugin / SessionPlugin
                  └─ LLM tools     └─ Monty       └─ JS bridge
                                                     ↕ Surface.emit
       │
   [one SessionPlugin coordinator]
       │
       ▼
   surface singletons
```

The consolidation is roughly a half-week of mechanical work. JS
bidirectional surfaces are a clean demo (CodeMirror first, ~2 days)
once the lifecycle map has one coordinator type instead of two.

## When in doubt, ask: "what scope?"

Three questions to ask any time a new piece of state is added:

1. **Where does the value originate?** Per-event, per-run,
   per-session, per-thread, app, or per-mount?
2. **Who reads it?** A widget (per-mount), a projection
   (per-bus-subscription), an orchestrator (per-run), …
3. **What happens at every lifecycle boundary it crosses?** Detach,
   attach, reload, re-mount. If the answer is "implicit" or
   "depends on attach order", it's a future bug.

Every shipped bug in this branch was a "what scope?" question that
hadn't been asked.
