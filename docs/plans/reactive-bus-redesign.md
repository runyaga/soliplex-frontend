# Reactive bus-centric redesign — soliplex client stack

Goal: collapse the four parallel writer paths, four registries, and two
extension hierarchies into one reactive model where state flows through
one bus per scope. Imperative paths remain only where the foreign
runtime's contract requires them (LLM tool calls, Python host functions,
JS bindings, OS callbacks).

This plan is **soliplex-side only.** `dart_monty` is frozen at its
upcoming public release; nothing in this redesign requires a
`dart_monty` change. The seam is `soliplex_agent_monty`, which becomes a
translation layer between soliplex's `SessionExtension` model and
dart_monty's `MontyExtension` API.

## Core principle

> **State is reactive. Action is imperative.**

- Every state mutation flows through one `StateBus` (per scope). The bus
  is the only writer of state; render targets are read-only public.
- Every action with a required reply (LLM tool call, Python host function,
  JS binding, OS callback) is a function call through a unified
  `SessionExtension` registry. The same handler shape covers all four
  foreign runtimes.

## Hard architectural boundaries

| Boundary | Rule |
| --- | --- |
| `dart_monty` ↔ soliplex | dart_monty's public API is frozen by its release. soliplex_agent_monty translates; soliplex never reaches into dart_monty internals. |
| soliplex bus ↔ dart_monty signals | Two state systems. dart_monty's progressive signals describe Python execution. soliplex's bus describes the user-facing world. They cohabit at the bridge; they do not merge. |
| Render targets ↔ writers | `mapExtension`, `narrationController`, future surfaces expose only read APIs publicly. All writes are bus deltas. |
| `SessionExtension` ↔ `MontyExtension` | `SessionExtension` is soliplex's authoring model. `MontyExtension` is dart_monty's wire format. Bridge layer translates one to the other. Plugin authors never see `MontyExtension`. |
| App shell ↔ plugins | `lib/` is the app shell — routes, modules, flavor composition, room-screen layout. Every domain-specific render target / session reactor / plugin lives in its own `packages/soliplex_*/`. Core packages (`soliplex_agent`, `soliplex_client`) **cannot** depend on plugin packages; the dependency direction is one-way and enforced via pubspec. |

## Implementation detail: JSON internals

The v1 bus stores `Map<String, dynamic>` internally and accepts deltas
as RFC 6902 JSON Patch operations. **This is an implementation
choice, not an architectural commitment.** The architecture commits
to:

1. One canonical document per scope.
2. All writes through one delta operation.
3. All reads through projections with subscriptions.
4. No render-target mutation outside the bus → projection path.

The internal representation could equally be a typed record tree, an
immutable persistent data structure, or anything else without touching
the architecture. JSON wins in v1 because:

- AG-UI's wire format is JSON; `StateSnapshotEvent` / `StateDeltaEvent`
  apply directly with no translation.
- Free serialization for any future cross-reload persistence.
- Agent and client can evolve the schema without lock-step type updates.
- The projection layer recovers type safety at the read boundary —
  a `MarkersProjection` returns `List<MarkerData>`, not `dynamic`.

The cost is path strings (`/ui/map/markers/-`) where typos fail at
runtime instead of compile time. The "Bus schema validation at
applyDelta boundary" follow-on (in Open follow-ons) is the mitigation
when concrete need surfaces.

## Bus scopes

`StateBus` is **scope-agnostic.** It doesn't know about LLMs, sessions,
or AG-UI events; it's a reactive document that anything can write deltas
to and anything can subscribe to via projections. The thread bus
happens to be where AG-UI events land in v1, but the same mechanics
apply to non-LLM state at any scope:

- **App-level events** (window resize, tab focus/blur, navigation, toast
  notifications, connectivity changes, error banners) — frontend state
  with no relation to any agent. App-bus.
- **Server-level events** (room list updates, auth refresh, server
  health, SSE connection status) — server-bus.
- **Room-level events** (room config changes, cross-thread room
  announcements) — room-bus.
- **Thread-level events** (current map, narration, widgets, convoy
  position) — thread-bus. **Built in v1.**

v1 implements per-thread only; the architecture supports adding others
without redesign because the bus type is the same at every scope.

| Scope | Bus | Owner | v1 |
| --- | --- | --- | --- |
| App | `appBus` | shell | not built |
| Server | `serverBus[ServerId]` | `AgentRuntime` (per-server) | not built |
| Room | `roomBus[(ServerId, RoomId)]` | per-room view state | not built |
| **Thread** | `threadBuses[ThreadKey]` | `AgentRuntime._threadStates` | **built** |

A projection declares which bus it consumes. Cross-scope projections are
opt-in (a projection can take multiple buses).

### Per-thread keying

Per-thread state is keyed by the full `ThreadKey` triple
`(serverId, roomId, threadId)` — the typedef record at
`packages/soliplex_agent/lib/src/models/thread_key.dart:9` — not by
bare `threadId: String`.

Today `AgentRuntime._threadHistories: Map<String, ThreadHistory>` keys
by bare `threadId` (`agent_runtime.dart:92`). This works in practice
because each runtime is per-server, but it's a latent bug: two rooms
could in principle share a `threadId`, and the cache wouldn't catch
the collision. The redesign fixes this:

```dart
// Before
final Map<String, ThreadHistory> _threadHistories = {};

// After
final Map<ThreadKey, ThreadState> _threadStates = {};

class ThreadState {
  final StateBus bus;
  final Conversation conversation;
}
```

`ThreadKey` is a Dart record with value equality, so it works as a
`Map` key directly. ~6 call sites change to pass `key: ThreadKey`
instead of `threadId: String`. ~10 LOC delta. Eliminates a latent bug
class.

## Render-target scope

Render targets (`mapExtension`, `narrationController`, …) stay
**app-singleton with read-only public API** for v1. The library-private
`_forwardFromProjection` pattern is the only write path; the active
thread's projection is the only caller.

This minimizes churn (existing widgets keep their imports) while
enforcing single-writer discipline. A future PR can promote render
targets to per-thread instances if multi-thread-visible UX is ever
needed; the migration is mechanical and isolated.

| Thing | Scope |
| --- | --- |
| Bus | per-`ThreadKey` |
| Projection instances | per-`ThreadKey` (bound to one bus) |
| Render targets (singletons) | app-singleton, read-only public, swap-source on thread change |

## Two kinds of state

Not every reactive thing in the codebase is a target for the bus. The
deciding question:

> **Does this state need to survive across session boundaries within a
> thread (in the same browser session)?**

If yes → bus (per-thread `StateBus` is the persistence layer).
If no → extension-owned signal (transient, per-session).

| Kind | Example | Owner |
| --- | --- | --- |
| **Per-thread persistent** — survives session-end / thread-switch | markers, narration, widgets, convoy position, **execution step log** (thinking + tool-call steps with timing) | per-thread `StateBus` (canonical) |
| **Per-session transient** — dies with the session | streaming-state machine per message, pending approvals, executing-status flags | `SessionExtension`-owned signals (single-writer, UI reads) |

The bus *is* the per-thread persistence layer (after step 3, owned by
`AgentRuntime` as `ThreadState(bus, conversation)`). Anything that
should survive a session-to-session transition within a thread belongs
on the bus. Anything that's truly per-session-transient stays on
extensions.

(Cross-browser-reload persistence is a separate concern; it's solved
today by re-fetching from the server, which gives back `aguiState` and
messages but not local-only state. Bus state survives within a
browser session; cross-reload survival depends on whether the server
emits/persists those paths.)

### Extensions that stay as-is (per-session transient)

These SessionExtensions are correctly per-session-transient. They
don't need to survive thread reopens because their state is
intrinsically about the *current* moment, not historical.

- `HumanApprovalExtension` — single writer (approval-request handler),
  exposes pending-approval signal. Pending approvals don't replay;
  they were either resolved or stale.
- `ToolCallsExtension` — local-status reducer (executing → completed
  / failed). Borderline: `Conversation.toolCalls` already preserves
  the canonical persistent record from the server. The extension's
  local-status transitions are useful during execution but redundant
  for replay. Stays as-is; redundancy with `Conversation.toolCalls`
  is the persistent view consumers should use for "what tools ran."

After Phase 2 step 7, each gains `hostFunctions: const []` (~3 LOC
each). No other refactoring.

### Extensions that move to the bus (per-thread persistent)

`ExecutionTracker` / `ExecutionStep` (thinking + tool-call steps
with timing) belongs on the bus. Today it's a per-session extension
that resets to empty when you switch threads and come back — that's
a UX bug, not by design. Moving it to the bus fixes the bug naturally
(the bus is per-thread; switching away and back finds the same state).

Conversion (Phase 1 step 5b, new):

- The execution-event reducer becomes a function that emits
  `bus.applyDelta(...)` to `agentState['/_meta/steps']` instead of
  writing to a private signal.
- A `StepsProjection extends StateProjection<List<ExecutionStep>>`
  reads `agentState['/_meta/steps']` and deserializes back to typed
  `ExecutionStep` with `StepType`/`StepStatus` enums. Type safety
  preserved via the projection layer (same trick as `MarkerData`,
  `Narration`, etc.).
- `ExecutionThinkingBlock` widget binds to the projection signal
  instead of the extension signal. One line change at the binding
  site; rendering logic unchanged.
- `ExecutionTracker` extension class either retires (if the reducer
  is enough) or shrinks to a pure event-to-delta translator.

This is **Phase 1 step 6** — small (~half-day), mechanical, no risk
to the rest of the redesign. Placed after the `MapPlugin` conversion
since the pattern is proven by then.

### UI components that stay as-is

| Component | Category | Why it stays |
| --- | --- | --- |
| `ExecutionThinkingBlock` widget | UI watcher of a signal | Source signal changes (extension → projection) but the widget itself is unchanged |
| `code_block_builder.dart` (figlet / container / svg / highlighted code dispatch) | Stateless renderer | Pure function from markdown language tag to widget; no state |
| `streaming_state.dart` (in `soliplex_client`) | Per-message streaming state machine | Per-message transient; PR #62 is improving its internal guard helper, orthogonal to redesign |

## Guards: which go away, which stay

Two categories of guard exist in the codebase. The redesign retires
one and not the other.

| Category | Cause | Survives redesign? |
| --- | --- | --- |
| **Self-inflicted** | Multiple owners of one resource, caches outliving their source, signals being swapped, deferred callbacks racing synchronous disposal | **Goes away** — architectural fix removes the situation |
| **External asynchrony** | Network latency, out-of-order events, user-input timing, cancellation, mount/unmount in Flutter | **Stays** — no architecture eliminates physical reality |

### Category A guards retired by v1

- `_captureThreadHistory` disposed-session check (PR #61) — eliminated by per-thread `Conversation` in step 3. `_threadHistories` cache is gone; nothing to capture; no `.then` callback chasing disposed signals.
- `wireProjection` swap-source guards (Lesson #11) — already partially eliminated; fully gone after step 7.
- `registerExternalSpriteFollower` set + skip-followed-ids in `_diffApplyImages` (camera-arc race fix) — eliminated by single-writer-per-tween in step 6.
- `_wireSurfaceSingletons` re-wire on session attach — eliminated when bus persists across sessions.

### Category B guards that stay (correctly)

- `_onActiveTextStream` (PR #62) — streaming event ordering. Network-asynchrony, intrinsic.
- `if (mounted)` / `if (context.mounted)` checks — Flutter widget lifecycle, intrinsic.
- Cancellation-token race checks in tool execution — async cancellation, intrinsic.
- Future race/timeout guards in `monty_wait_for` — intrinsic to async waits.

### Concurrent PRs

Tactical fixes can land alongside or before the v1 stack:

- **PR #61** (`fix/capture-thread-history-disposed`) — land now. After step 3 ships, the guard becomes dead code and gets deleted.
- **PR #62** (`refactor/streaming-guard-extraction`) — land now. The deduplicated helper is welcome regardless; the guard stays.

## Patterns this collapses

Four patterns recur across the codebase. The redesign collapses each.

| # | Pattern | Width today | After |
| --- | --- | --- | --- |
| 1 | Foreign-runtime call shape | 4 type hierarchies (`ClientTool` / `MontyExtension` / future JS / future OsCall), 4 registries, 4 dispatchers | One `SessionExtension` declaring `tools` and `hostFunctions`; the bridge layer adapts to whichever foreign runtime invokes. |
| 2 | Writer paths to render-target singletons | 3 paths (AG-UI events through state document, ClientTool imperatively, Monty externals imperatively) | One path: `bus.applyDelta(...)`. Singletons read-only. |
| 3 | Outer-scope-caches-inner-scope state | 3 encodings (`Conversation` per-session, `_threadHistories` Map, `StateBus` per-thread) | One: per-thread `ThreadState(bus, conversation)` on the runtime. |
| 4 | Registry shapes | 5 (`ToolRegistry`, `ExtensionCoordinator`, `WidgetCatalog`, `SessionExtensionFactory`, `registerExternalSpriteFollower`) | Unified registration via `SessionExtension` declarations; render-target-side registers retire. |

## Where to start — PRs #54–63 are the foundation

The session-extension architecture this redesign builds on is being
established by an in-flight 10-PR stack on `runyaga/soliplex-frontend`:

| PR | Title | Stack base | Role for redesign |
| --- | --- | --- | --- |
| **#54** | `feat(core): AppModule lifecycle replaces ModuleContribution` | `main` | Foundation — module contract |
| **#55** | `feat(soliplex_agent): SessionCoordinator and StatefulSessionExtension` | #54 | **Primary base type** the redesign extends |
| **#56** | `feat(room): ExecutionTrackerExtension — first session reactor` | #55 | Phase 1 step 6 refactors this extension's storage from a private signal to bus writes |
| **#57** | `feat(room): show spinner on thread tile when agent run is active` | `feat/session-spawner` | Independent UX |
| **#58** | `feat(room): ToolCallsExtension — status-only tool call tracking` | #57 | Stays as-is in redesign (per-session transient) |
| **#59** | `feat(room): HumanApprovalExtension + ToolApprovalExtension reactor` | #58 | Stays as-is in redesign (per-session transient) |
| **#60** | `feat(room): ExtensionStatePanel debug view over StatefulSessionExtensions` | #59 | Debug tooling; survives redesign unchanged |
| **#61** | `fix(soliplex_agent): guard _captureThreadHistory against disposed session` | `main` | Tactical fix; guard becomes dead code after Phase 1 step 3 |
| **#62** | `refactor(soliplex_client): extract _onActiveTextStream guard helper` | #61 | Pure refactor; orthogonal |
| **#63** | `feat(room): gate ExtensionStatePanel behind kDebugMode` | #60 | UX hygiene |

These are reviewed and cherry-picked with the new design in mind — i.e.
PRs going through review may be tweaked to align with the redesign
patterns documented here, but the *substance* of each PR (the new
extension/reactor) lands as the foundation Phase 1 extends.

**Phase 1 cannot start until the relevant subset of #54–63 is in
main.** Specifically Phase 1 needs at minimum:

- **#54** (AppModule lifecycle)
- **#55** (SessionCoordinator + StatefulSessionExtension)
- **#56** (ExecutionTrackerExtension) — step 6 modifies its internal storage

PRs #57–60 and #63 add value but don't block. #61, #62 are independent fixes.

After the foundation stack is merged, consider tagging
`foundation/v0` on main as the reference point Phase 1 branches from.

## Phasing — Phase 1 (no dart_monty) → Phase 2 (dart_monty integration)

The work splits into two cleanly separated phases. **Phase 1 ships and
stabilizes before Phase 2 starts.** This is non-negotiable — combining
them concentrates risk and review burden in one stack and forces
reviewers to hold both "reactive bus inversion" and "foreign-runtime
bridge" in their heads simultaneously.

| Phase | What | dart_monty | FFI/WASM divergence concerns |
| --- | --- | --- | --- |
| **Phase 1** | Reactive bus inversion in soliplex. Bus becomes canonical for UI state. Render targets read-only public. ClientTool executors write the bus. Lifecycle types collapse. | **Untouched.** `MapMontyExtension`/`NarrationMontyExtension` keep operating exactly as today (carried forward unchanged). | **None.** Pure Dart soliplex-only changes. |
| **Phase 2** | Add dart_monty as a foreign-runtime adapter on the established Phase 1 foundation. `hostFunctions` field added to `SessionExtension`. Bridge layer (`MontyHostPlugin`) synthesizes `MontyExtension`s from declarations. `monty_get` / `monty_wait_for` / `monty_subscribe` implemented. `MapMontyExtension`/`NarrationMontyExtension` retire (their host functions move to `MapPlugin`/`NarrationPlugin`). | Integrated. soliplex_agent_monty becomes the translation layer. | Concentrated here. WASM/OsCall throttle, dual-backend integration tests. |

Phase 1 PRs land into main on their own merits. Phase 2 PRs open
**after** Phase 1 has merged and burned in.

### Phase 1 — 7 stacked PRs

Each PR is independently reviewable and revertable. Total ballpark:
~1.5–2 weeks of focused work.

| # | PR | What it does | Risk | Scope |
| --- | --- | --- | --- | --- |
| 1 | **Package restructure — extract plugins out of `lib/`** | Domain-specific render targets and plugins move out of the app shell into sibling packages of `soliplex_agent_maps`. Specifically: extract `lib/src/narration/` → `packages/soliplex_agent_narration/`; extract `lib/src/widget_tree/` → `packages/soliplex_agent_widgets/`. Establish dependency direction in pubspecs: `lib/` (app shell) depends on every plugin package; plugin packages depend only on `soliplex_client` and `soliplex_agent`; **`soliplex_client` and `soliplex_agent` cannot depend on any plugin package.** Layer-2 enforcement live. | Low (no behavior change; pure code-moves and pubspec edits) | 1–2 days |
| 2 | **`SessionContext`** | Introduce `SessionContext` carrying `bus`, `session`, `runtime` to handlers. Plumb through `onAttach`. **No `hostFunctions` field yet** — that's Phase 2. | Low (mechanical, additive) | 1 day |
| 3 | **Bus canonical for state, Conversation per-thread, lifecycle types collapse** ⚠️ | `StateBus` becomes source of truth for UI state. `Conversation.aguiState` field deleted. `Conversation` moves to per-thread scope (alongside bus). `_threadHistories` cache deleted (replaced by per-`ThreadKey` `ThreadState` map). Three lifecycle types (`ConversationStatus` + `RunState` + `AgentSessionState`) collapse into one. Per-thread keying migrates from bare `threadId` to `ThreadKey`. | **High** — only step where regression is subtle. Heavy integration test coverage required. | 2–3 days |
| 4 | **`NarrationPlugin` end-to-end** | Smallest plugin. Convert: `NarrationController` becomes read-only public, `_forwardFromProjection` library-private, all `ClientTool` executors write the bus. Proves the pattern in isolation. **`NarrationMontyExtension` carried forward unchanged** — Phase 2 retires it. | Low | 0.5 day |
| 5 | **`MapPlugin`** | Largest plugin. Convert `MapExtension` to read-only public API. Move all map operations to `MapPlugin` declaring tools (no `hostFunctions` yet — Phase 2). Bus is single writer for map state. The camera-arc race fix (`registerExternalSpriteFollower`) deletes itself. **`MapMontyExtension` carried forward unchanged** — Phase 2 retires it. | Medium | 1 day |
| 6 | **Execution steps → bus** | `ExecutionTracker` reducer writes to `agentState['/_meta/steps']` via `bus.applyDelta(...)` instead of its own signal. New `StepsProjection` deserializes back to typed `List<ExecutionStep>`. `ExecutionThinkingBlock` rebinds to the projection signal — widget rendering unchanged. **Fixes today's UX bug**: switching away from a thread and coming back now shows prior step history (per-thread persistence via the bus). | Low | 0.5 day |
| 7 | **Remove public mutators** | Mechanical sweep — delete `mapExtension.addMarker`, `narrationController.append`, etc. Anything that doesn't compile migrates to bus writes or a `SurfaceEvent`. The architectural invariants are enforced by Layers 1+2 (visibility + package boundaries); lints are a follow-on. | Low | 0.5 day |

After Phase 1 merges, the soliplex side is fully reactive for UI
state. The Monty side still mutates singletons through its existing
extension classes — that *works* (the singletons are still publicly
mutable to MontyExtensions during Phase 1; the lint and visibility
restrictions only apply to soliplex code). Phase 2 closes that gap.

### Phase 2 — 4 stacked PRs

Opens after Phase 1 is merged and stable. Total ballpark: ~3–4 days
focused work.

| # | PR | What it does | Risk | Scope |
| --- | --- | --- | --- | --- |
| 8 | **`hostFunctions` field on `SessionExtension`** | Add `List<HostFunction> get hostFunctions => const []` to `SessionExtension`. Existing extensions get the default; nothing else changes yet. | Low | 0.5 day |
| 9 | **`MontyHostPlugin` bridge** | Translation layer in `soliplex_agent_monty`. Walks `SessionExtension.hostFunctions`, synthesizes `MontyExtension`s from declarations, registers with a per-session `MontyRuntime`. Implements built-in bridge host functions: `monty_get`, `monty_wait_for`, `monty_subscribe` (all three using OsCall, day one). Throttle defaults to ≥50ms on `monty_subscribe`. **Mandatory dual-backend integration tests (`-p vm` AND `-p chrome`).** | Low–medium | 1–1.5 days |
| 10 | **Convert `NarrationPlugin` + `MapPlugin` to declare `hostFunctions`** | Move host-function logic from `NarrationMontyExtension` / `MapMontyExtension` into `hostFunctions` declarations on `NarrationPlugin` / `MapPlugin`. Bridge picks them up automatically. Delete `NarrationMontyExtension` and `MapMontyExtension`. | Medium (the actual Monty cutover) | 1 day |
| 11 | **`MontyRuntimeExtension` cleanup** | `MontyRuntimeExtension` retires as a stand-alone SessionExtension; its `MontyRuntime` ownership moves into `MontyHostPlugin`. The soliplex-side wrapper around dart_monty's `ExtensionCoordinator` collapses. (dart_monty's *internal* `ExtensionCoordinator` stays exactly as-is — only the soliplex-side wrapper changes.) | Low–medium | 0.5 day |

## What changes in `soliplex_agent`

`packages/soliplex_agent/lib/` is ~4,714 LOC across 38 files. Roughly
**12% touched, 72% untouched.**

### Heavy edit — 3 files, ~200–280 LOC actually changed

| File | LOC | Edited | What changes |
| --- | --- | --- | --- |
| `agent_session.dart` | 568 | ~100–150 | `agentState` becomes a *view* of the bus; bus reference threaded into session; `_aguiStateOf` switch simplifies once lifecycle types collapse. |
| `agent_runtime.dart` | 480 | ~50–80 | `_threadHistories: Map<String, ThreadHistory>` migrates to `_threadStates: Map<ThreadKey, ThreadState>`; `seedThreadState` / `seedThreadHistory` write to a per-thread bus; `_extensionFactory` plumbing unchanged. |
| `run_orchestrator.dart` | 813 | ~30–50 | Biggest file, smallest edit. `StateSnapshotEvent` / `StateDeltaEvent` write the bus directly. Run lifecycle, tool yielding, error classification untouched. |

### Mechanical additions

**Phase 1** — 1 file, ~10 LOC touched

| File | Change |
| --- | --- |
| `session_coordinator.dart` | +~10 LOC: pass `SessionContext` to extensions on attach |

**Phase 2** — 4 files, ~100 LOC touched

| File | Change |
| --- | --- |
| `session_extension.dart` | +~30 LOC: `List<HostFunction> get hostFunctions => const []` |
| `stateful_session_extension.dart` | +~10 LOC: pass `hostFunctions` through |
| `tool_approval_extension.dart` | unchanged (no host functions) |
| `session_coordinator.dart` | +~30 LOC: walks extensions, gathers `hostFunctions` for the bridge to pick up |

### Type collapse — 2 files, net ~80 LOC removed

| File | Change |
| --- | --- |
| `agent_session_state.dart` (19) | Deleted; absorbed into unified lifecycle type. |
| `run_state.dart` (263) | Absorbs `AgentSessionState`; ~30 LOC removed. |

### New files — ~120 LOC added

| File | LOC | Purpose |
| --- | --- | --- |
| `session_context.dart` | ~50 | Object passed to handlers. Exposes `bus`, `session`, `runtime`. |
| `thread_state.dart` | ~50 | Per-thread bundle: `(StateBus, Conversation)`. Owned by AgentRuntime. |
| Plumbing | ~20 | Bus reference threading. |

### Untouched — ~3,400 LOC, ~22 files

- `host/` — all 12 files (~1,200 LOC)
- `http/` — 2 files (~400 LOC)
- `models/` — 3 files (~150 LOC)
- `orchestration/` non-redesign files — 7 files (~880 LOC)
- `runtime/` non-redesign files — 3 files (~270 LOC)
- `tools/` — 3 files
- `scripting/script_environment.dart`
- `testing.dart` (light touch — fakes update for new shapes)

## What changes in `Conversation`

`packages/soliplex_client/lib/src/domain/conversation.dart` is 258 LOC.
Net: shrinks to ~150 LOC.

| Field | After |
| --- | --- |
| `threadId` | unchanged |
| `messages: List<ChatMessage>` | unchanged |
| `toolCalls: List<ToolCallInfo>` | unchanged |
| `status: ConversationStatus` | **collapses** with `RunState` + `AgentSessionState` into one lifecycle type |
| `aguiState: Map<String, dynamic>` | **deleted** — bus is canonical for UI state |
| `messageStates: Map<String, MessageState>` | unchanged |
| `activities: List<ActivityRecord>` | unchanged |

`Conversation` moves from per-session to per-thread scope (lives in
`ThreadState` alongside the bus). Messages, tool calls, activities flow
across sessions on the same thread automatically.

## FFI / WASM backend analysis

**Phase 1 introduces zero new FFI/WASM divergence.** Everything in
Phase 1 is pure-Dart soliplex-only changes that work identically on
both backends. The dual-backend test matrix for Phase 1 is just
"existing tests pass on both `-p vm` and `-p chrome`."

**Phase 2's risk is concentrated in `monty_subscribe`** (step 9)
exercising dart_monty's OsCall channel under bus-driven event volume.
Mitigations:

1. **Throttle by default.** `monty.subscribe(path, callback, throttle_ms=50)` — bridge buffers updates, fires at most once per window.
2. **Mandatory dual-backend integration tests in step 9's PR.** `-p vm` AND `-p chrome` for all three host functions, including subscription cleanup on session dispose, and a WASM event-loop stress test under 1000-delta volume.

| New primitive | FFI | WASM | Notes |
| --- | --- | --- | --- |
| `StateBus.applyDelta` | ✓ | ✓ | pure Dart |
| `StateBus.agentState` (signal) | ✓ | ✓ | signals_core |
| `StateBus.events` (Stream) | ✓ | ✓ | dart Stream |
| `SessionContext` | ✓ | ✓ | pure Dart |
| `MontyHostPlugin` (the bridge) | ✓ | ✓ | uses dart_monty public API only |
| `monty_get` host function | ✓ | ✓ | snapshot read |
| `monty_wait_for` host function | ✓ | ✓ | Future returned by handler |
| `monty_subscribe` host function | ✓ | ✓ ⚠️ | OsCall-driven; throttle defaults to ≥50ms |
| `_forwardFromProjection` | ✓ | ✓ | pure Dart |

## Enforcement layers

v1 relies on the two compile-time layers. Lint and architecture-test
layers are deferred follow-ons (see Open follow-ons).

| Layer | Mechanism | What it catches | In v1? |
| --- | --- | --- | --- |
| 1. Visibility | Dart library privacy (`_method`, `@internal`) | External callers can't reach mutating APIs on render targets. | ✓ |
| 2. Package boundaries | Dependency direction in `pubspec.yaml` | Plugin packages can't import render-target packages. The biggest win. | ✓ |
| 3. Custom lints | `custom_lint` or DCM | Residual cases inside one package; forbid `bus.agentState.value =` style writes; flag forbidden imports. | follow-on |
| 4. Architecture tests | AST-walking tests | Cross-cutting invariants. | follow-on |

The honest read: **Layers 1+2 do the architectural work.** Once the
package restructure is in place and render-target singletons have only
read APIs publicly, wrong code mostly doesn't compile. Lints would
catch the residual gap, but the gap is small enough that code review
covers it adequately for v1. Add lints later if specific violations
recur in practice.

## Risk concentration

**Phase 1**: step 3 is the single high-risk PR. Failure mode is
"subtle wrongness at runtime" because data flow changes without
changing types. Mandatory test coverage:

- Replay-after-reload (browser refresh mid-session reseeds bus from `history.aguiState`).
- Multi-session-on-one-thread (bus survives session attach/detach).
- Mid-run cancel/resume.
- Tool yield/resume preserves bus state.
- The camera-arc race scenario passes *without* `registerExternalSpriteFollower` (it gets deleted in step 5, but the rule that prevents the race holds from step 3 forward).

Every other Phase 1 step either fails to compile or fails a lint when
wrong.

**Phase 2**: step 9 (`MontyHostPlugin` bridge) is the WASM/OsCall
risk concentration — see FFI/WASM analysis above.

## Success criteria

### Phase 1 — done when

1. Every soliplex-side state mutation for UI surfaces goes through `bus.applyDelta(...)`. `grep` returns zero direct `_entries.value =` style writes outside `_forwardFromProjection` methods *in soliplex code*.
2. `wire*Projection` glue methods are deleted; nothing to wire because nothing else (in soliplex) writes.
3. `registerExternalSpriteFollower` and friends are deleted; the architecture forbids the bug they were patching.
4. `_threadHistories` is gone; per-thread state is keyed by `ThreadKey`, not bare `threadId`.
5. Three lifecycle types collapsed to one.
6. `Conversation.aguiState` field deleted.
7. `MapMontyExtension` / `NarrationMontyExtension` continue to function unchanged. dart_monty integration is **not** broken; it's just not yet ideal.
8. App shell (`lib/`) imports plugin packages; plugin packages import only `soliplex_client` and `soliplex_agent`. `flutter pub deps` confirms the one-way dependency direction.

### Phase 2 — done when

1. Every plugin author writes one `SessionExtension` declaring both `tools` and `hostFunctions` over the same handlers. No plugin authors see `MontyExtension`.
2. `MapMontyExtension` and `NarrationMontyExtension` are deleted.
3. `MontyHostPlugin` is the only soliplex-side bridge to dart_monty.
4. `monty_get` / `monty_wait_for` / `monty_subscribe` ship and pass dual-backend integration tests.
5. `dart_monty`'s public API hasn't changed.
6. `lifecycle-and-coupling.md` updates to the new diagram: 7 lifecycle scopes, one writer source (bus), one reader pattern (projection), one bridge between soliplex and dart_monty.
7. The single soliplex-side bridge to dart_monty is `MontyHostPlugin`; no other code path reaches `MontyExtension`.

## Demoable behavior per step

Every PR ships with a concrete user-visible or architecturally-visible
demo. If a step has no demo, it shouldn't be a separate PR.

### Foundation (PRs #54–63, in flight)

| PR | Demoable behavior |
| --- | --- |
| #54 | App starts/stops with module lifecycle hooks firing; routes resolve from registered modules. |
| #55 | A test session attaches an extension; namespace lookup returns it; detach disposes cleanly. |
| #56 | Run an agent thread → execution panel shows live thinking-step + tool-call entries with status transitions. |
| #57 | Start a thread → its tile in the sidebar shows a spinner; spinner stops on completion. |
| #58 | Tool-call panel populates per tool with executing → completed/failed status transitions. |
| #59 | Agent calls a tool requiring consent → approval prompt appears; outcome reflects in tool-call status. |
| #60 | Open ExtensionStatePanel → live JSON view of every attached `StatefulSessionExtension`'s state. |
| #61 | "Signal read after disposed" warnings drop from 1 to 0 in test runs. |
| #62 | Refactor only — no behavior change; existing tests pass. |
| #63 | ExtensionStatePanel only appears in debug builds. |

### Phase 1

| Step | Demoable behavior |
| --- | --- |
| 1 | Architecturally visible: `flutter pub deps` shows `lib/` depending on plugin packages; plugin packages depending on core; no reverse imports. Try `import 'package:lib/...'` from a plugin — compile error. No user-facing change. |
| 2 | A handler receives `SessionContext` and reads `ctx.bus.agentState.value`. Plumbing only. |
| 3 ⚠️ | **Persistence promise lands.** Browser refresh mid-mission preserves map / narration state. Switching threads and switching back preserves state with no flicker. Mid-run cancel/resume preserves state. The `_threadHistories` dance is gone. |
| 4 | Narration entries from a `ClientTool` end up on the bus → reflected in the panel. Narration persists across session boundaries within a thread. Try to call `narrationController.append(...)` from outside the plugin — compile error. |
| 5 | All map demos work in main (markers, smooth sprite tweens, fly-with-image arc, auto-fit-bounds). **Headline demo:** the camera-arc scenario works *without* `registerExternalSpriteFollower` — architecture forbids the bug. Map state persists across reload/thread-switch/session boundaries. |
| 6 | **Fixes today's UX bug:** switching to another thread mid-run and switching back shows the prior step log. Today the log resets to empty. |
| 7 | Try to call `mapExtension.addMarker(...)` from app code — **compile error** (the public mutating API no longer exists). Try to import a render-target package from a plugin package — **compile error** (Layer 2 dependency direction). Architectural invariants enforced at the language level. |

### Phase 2

| Step | Demoable behavior |
| --- | --- |
| 8 | A `SessionExtension` declares `hostFunctions: const [...]`; runtime accepts it; existing extensions still attach. Plumbing only. |
| 9 | **Python becomes a reactive bus participant.** Three demos: (a) `pos = monty.get('/ui/map/convoy')` — snapshot read; (b) `monty.wait_for('/ui/map/convoy/site_id', equals='camp-alpha')` — Python suspends until match; (c) `monty.subscribe('/ui/map/convoy', on_move)` — callback fires on each change. Works on both `-p vm` and `-p chrome`. |
| 10 | **Python drives map and narration directly:** `for site in sites: monty.move_convoy_to_site(site)` — full tour from one Python script. `monty.append_narration('Coordinator', 'Beginning mission')`. `MapMontyExtension` and `NarrationMontyExtension` files deleted. |
| 11 | A session with `MontyHostPlugin` registered behaves identically to one with the old `MontyRuntimeExtension`. The soliplex-side wrapper around dart_monty's coordinator is gone. |

### Headline demos by phase

- **End of foundation (PRs #54–63):** *"You can see what the agent is doing in real time"* — reactor panels, tool-call panel, thread spinners, approval prompts.
- **End of Phase 1 step 3:** *"State survives reloads and thread-switches"* — the persistence promise.
- **End of Phase 1 step 6:** *"Step history persists across thread reopens"* — the UX bug fixed.
- **End of Phase 1:** *"Plugins are isolated and architecturally enforced at the language level"* — try to write the wrong way, the compiler stops you.
- **End of Phase 2 step 9:** *"Python is a first-class reactive participant"* — read/wait/subscribe over the bus.
- **End of Phase 2 step 10:** *"Python drives the UI through the same plugins as the LLM"* — one plugin, both foreign runtimes.

## Tests and documentation per PR

Every PR in the stack carries its own tests and doc updates — neither
is deferred to a "test pass" or "docs pass" PR. Repo conventions per
`/Users/runyaga/dev/soliplex-frontend-merged/CLAUDE.md`:

### Tests

| Type | When required | Tooling |
| --- | --- | --- |
| **Unit tests** for new types | Every PR introducing a new class, signal, projection, host function | `mcp__dart-mcp__run_tests` (preferred); `flutter test` fallback |
| **Integration tests** for behavioral changes | Phase 1 step 3 (mandatory: replay-after-reload, multi-session-on-thread, mid-run cancel/resume, tool yield/resume), Phase 2 step 9 (mandatory: dual-backend `monty_get` / `monty_wait_for` / `monty_subscribe` cycle, subscription cleanup, WASM event-loop stress under 1000 deltas) | Same |
| **Dual-backend** (`-p vm` AND `-p chrome`) | Required for any code that interacts with dart_monty (Phase 2). Mandatory for `monty_subscribe`. | `flutter test -p vm` and `flutter test -p chrome` |
| **Coverage** | Existing CI gate: 80% line coverage in soliplex_agent and soliplex_client. New code must keep coverage at-or-above current. | CI pipeline |
| **Lint zero-warnings** | Every PR | `mcp__dart-mcp__analyze_files` (must pass with zero issues); `dcm` per memory (`feedback_run_dcm_with_analyzer`) |
| **Format** | Every PR | `mcp__dart-mcp__dart_format` |

### Documentation

| Type | Where | When |
| --- | --- | --- |
| **PR description** | GitHub PR body | Every PR. Links to this plan doc and the specific step number it implements. |
| **Inline code docs** | Dartdoc on new public types and methods | Every PR introducing public surface. |
| **CLAUDE.md updates** | `/CLAUDE.md` and per-package `CLAUDE.md` files | When introducing or changing a primitive that future contributors will read about (e.g. when `SessionExtension` gains `hostFunctions`, the per-package `CLAUDE.md` adds an example). |
| **Plan-doc updates** | This document | Whenever a step's scope or risk changes during implementation; write a one-liner saying what shifted. |
| **Lessons addendum** | `docs/plans/genui-build-lessons.md` | Whenever a step surfaces a non-obvious lesson worth carrying forward. |
| **`lifecycle-and-coupling.md` update** | `docs/plans/lifecycle-and-coupling.md` | Phase 1 step 7 (when the architecture stabilizes) and Phase 2 step 11 (when dart_monty integration is final). The doc reflects the new architecture, not the old. |
| **Markdown lint zero-issues** | Every `.md` file touched | Mandatory per CLAUDE.md. `markdownlint-cli2 "**/*.md" "#node_modules"` must pass. |

### Specific test requirements per Phase 1 step

- **Step 1** (Package restructure): existing tests pass on both backends. No new tests required (no new behavior).
- **Step 2** (`SessionContext`): unit test that the context exposes `bus`, `session`, `runtime`; that handlers receive it on attach.
- **Step 3** (Bus canonical): the integration test list in "Risk concentration" — *all of them*. Plus regression tests for the patterns that were Self-Inflicted-Guard motivators (PR #61's disposed-session race scenario should pass without the guard).
- **Step 4** (`NarrationPlugin`): unit test that ClientTool executors write the bus and that the `NarrationProjection` deserializes correctly. Conformance test that the public API of `NarrationController` is read-only.
- **Step 5** (`MapPlugin`): same as step 4, plus a regression test for the camera-arc scenario the deleted `registerExternalSpriteFollower` was patching — must pass without the workaround.
- **Step 6** (Execution steps → bus): unit tests for the steps reducer (event → JsonPatchOp); `StepsProjection` deserialization; **and** a UX integration test that switching away from a thread mid-run and returning shows the prior step history (the bug this step fixes).
- **Step 7** (Mutators removed): the architectural invariants are enforced at compile time by Layers 1+2 (visibility + package boundaries). Verification is mechanical: if the codebase compiles after the public mutators are deleted, the invariants hold. Optional: a one-off `dart analyze` pass with a deliberate violation locally to confirm the compiler catches it.

### Specific test requirements per Phase 2 step

- **Step 8** (`hostFunctions` field): unit test that `SessionExtension.hostFunctions` defaults to `const []`; existing extensions still attach correctly.
- **Step 9** (`MontyHostPlugin` bridge): full dual-backend matrix (see FFI/WASM analysis section).
- **Step 10** (Plugin host-function migration): regression tests that `MapMontyExtension` / `NarrationMontyExtension` deletions don't break Python-side scripts that called the old paths.
- **Step 11** (`MontyRuntimeExtension` cleanup): integration test that a session with `MontyHostPlugin` registered behaves identically to one with the old `MontyRuntimeExtension` registered.

## Review aids for upstream

The demoable-behavior tables above plus the test/doc requirements are
the source for two things every PR ships with: a structured PR
description and a review checklist. Both reduce the cognitive load on
reviewers and make "is this PR done?" mechanical.

### PR description template

Every step's PR opens with this body (Markdown, paste verbatim and
fill blanks):

```markdown
## What this PR does

(One paragraph — paraphrase the step's "What it does" cell from the
phase table in `docs/plans/reactive-bus-redesign.md`.)

Implements **Phase {N} step {M}** of the reactive-bus redesign.
Plan: `docs/plans/reactive-bus-redesign.md`.

## Demoable behavior after this lands

(Verbatim from the step's row in "Demoable behavior per step".)

## Stack position

Base: `{base-branch}`
Depends on: PRs #{...}
Blocks: PRs #{...} (if any)

## Test plan

- [ ] `mcp__dart-mcp__analyze_files` — 0 issues
- [ ] `mcp__dart-mcp__run_tests` — all pass
- [ ] (Phase 2 / OsCall steps only) `flutter test -p chrome` — all pass
- [ ] (Step 3 / Step 9 only) Integration test list from "Risk concentration":
  - [ ] {specific test 1}
  - [ ] {specific test 2}
  - …
- [ ] Manual demo per "Demoable behavior" section above
- [ ] Markdown lint — 0 issues (if any `.md` touched)

## Documentation updated

- [ ] PR description (this) references plan doc
- [ ] Inline dartdoc on new public surface
- [ ] (Phase 1 step 7 / Phase 2 step 11 only) `docs/plans/lifecycle-and-coupling.md` reflects new architecture
- [ ] (Lessons-worthy only) `docs/plans/genui-build-lessons.md` addendum

## Risk

(Copy from the step's "Risk" cell.)

## Reviewer checklist

(Copy from "Review checklist per step" section.)
```

### Review checklist per step

What a reviewer should verify in addition to the standard "code looks
good." Tied to the architectural invariants this redesign establishes.

**Universal (every PR):**

- [ ] Touches only files in scope per the plan; no unrelated drive-by edits.
- [ ] Tests cover the new behavior; existing tests still pass.
- [ ] No new `// ignore:` directives.
- [ ] No new `dart:io` or `dart:ffi` imports in code that targets WASM.

**Phase 1 step 1 (Package restructure):**

- [ ] `lib/src/narration/` and `lib/src/widget_tree/` are gone; corresponding `packages/soliplex_agent_*/` exist.
- [ ] `flutter pub deps -s compact | grep soliplex_client` shows `soliplex_client` does NOT depend on any plugin package.
- [ ] Same check for `soliplex_agent`.
- [ ] `lib/` (app shell) depends on each plugin package via path.
- [ ] No code outside `lib/` imports anything from `lib/src/`.

**Phase 1 step 3 (Bus canonical) ⚠️:**

- [ ] All integration tests in "Risk concentration" pass.
- [ ] `_threadHistories: Map<String, ThreadHistory>` is gone; replaced by `_threadStates: Map<ThreadKey, ThreadState>`.
- [ ] `Conversation.aguiState` field is deleted; `agentState` reads come from the bus.
- [ ] Three lifecycle types (`ConversationStatus`, `RunState`, `AgentSessionState`) collapsed to one.
- [ ] PR #61's `_captureThreadHistory` guard is dead code (or deleted in a follow-up note).
- [ ] Manual demo: browser refresh mid-mission preserves map state.
- [ ] Manual demo: thread-switch and back preserves state with no flicker.

**Phase 1 step 4 (NarrationPlugin):**

- [ ] `NarrationController.append` and any other public mutator is gone (or library-private).
- [ ] All ClientTool executors that mutate narration use `bus.applyDelta(...)`.
- [ ] `NarrationProjection` round-trips: narration entry → bus → projection → typed `Narration` list.
- [ ] Narration survives session-end / new-session-on-same-thread cycle (manual or test).
- [ ] `NarrationMontyExtension` is unchanged and still functional (Phase 2 retires it).

**Phase 1 step 5 (MapPlugin):**

- [ ] All `mapExtension.addMarker` / `addImage` / `setHud` etc. mutators are library-private.
- [ ] `registerExternalSpriteFollower` is deleted; the camera-arc test passes without it.
- [ ] Map state survives session-end / reload / thread-switch.
- [ ] `MapMontyExtension` unchanged and still functional.

**Phase 1 step 6 (Steps → bus):**

- [ ] `ExecutionTracker` either retired or shrunk to a pure event-to-delta translator.
- [ ] `agentState['/_meta/steps']` populates as the agent runs.
- [ ] `StepsProjection` deserializes back to typed `List<ExecutionStep>` with `StepType`/`StepStatus` enums.
- [ ] Manual demo: switch threads mid-run and back; step log persists.

**Phase 1 step 7 (Public mutators removed):**

- [ ] All public mutating methods on render-target singletons (`mapExtension.addMarker`, `narrationController.append`, etc.) are deleted or library-private.
- [ ] Codebase compiles cleanly with the deletions.
- [ ] Try locally: replace one `bus.applyDelta(...)` site with the old imperative call → it fails to compile.
- [ ] No new behavior; integration tests from prior steps still pass.

**Phase 2 step 9 (`MontyHostPlugin` bridge) ⚠️:**

- [ ] `monty_get`, `monty_wait_for`, `monty_subscribe` all implemented.
- [ ] `flutter test -p chrome` passes for all three.
- [ ] `monty_subscribe` throttle defaults to ≥50 ms.
- [ ] Subscription cleanup verified on session dispose (no leaks under repeated session attach/detach).
- [ ] WASM event-loop stress test passes under 1000-delta volume.
- [ ] No imports of `dart_monty` private members; only public API.

**Phase 2 step 10 (Plugin migration):**

- [ ] `MapMontyExtension` and `NarrationMontyExtension` files are deleted.
- [ ] `MapPlugin.hostFunctions` and `NarrationPlugin.hostFunctions` declare the equivalent operations.
- [ ] Existing Python scripts that called the old paths still work (regression test).

### Suggested PR labels (for upstream sorting)

- `redesign-phase-1` / `redesign-phase-2` — phase tag.
- `architecture` — non-trivial architectural change.
- `risk-high` — apply only to Phase 1 step 3 and Phase 2 step 9.
- `architecture-test-required` — apply where new architecture tests must accompany code.
- `dual-backend-required` — apply where `-p chrome` must pass.

These let upstream filter the queue and prioritize review attention
where the risk is highest.

## Companion docs

- **`docs/plans/example-plugin-todos.md`** — complete worked example of a plugin built on the new architecture. Demonstrates every architectural pattern in one ~300-LOC plugin: package isolation, `SessionExtension` with tools (and Phase 2 host functions), bus-write path, read-only render target, multi-projection, `SurfaceEvent` write-back, persistence, and the Python integration story. Use as the spec for what `MapPlugin` and `NarrationPlugin` should look like after conversion.
- **`docs/plans/bus-path-safety.md`** — design-space exploration of compile-time-safe approaches to bus paths. Recommendation: plugin-owned typed write methods (the architectural shape this plan already produces) plus phantom-typed `JsonPath<T>` constants. Skip codegen/schema for v1. ~200 LOC across already-planned PRs; no scope or risk change to this plan.
- **`docs/plans/lifecycle-and-coupling.md`** — reference doc covering current lifecycle scopes and coordinator hierarchies. Updates after Phase 1 step 7 and Phase 2 step 11.
- **`docs/plans/genui-build-lessons.md`** — running log of lessons learned during the GenUI work that informed this redesign.
- **`docs/plans/message-containers.md`** — historical / superseded; kept for context.

## Open follow-ons (not in v1)

- **Lint suite for architectural invariants.** ~2–4 rules covering: direct `bus.agentState.value =` assignment, `bus.applyDelta` calls outside plugin files, imports of dart_monty internal libraries from soliplex code. Tool TBD (`custom_lint` vs DCM — DCM already in CI per `feedback_run_dcm_with_analyzer`). Architecture tests as a backstop. Defer until concrete violations are seen post-v1; the gap Layers 1+2 don't cover is small and code review handles it.
- **Render targets per-thread** (vs app-singleton). Mechanical migration once v1 ships; widgets resolve controllers via Provider scoped to `ThreadState`.
- **Server-wide bus** for room list / auth / cross-thread state. Currently in Riverpod; promote when concrete need arises.
- **Bus schema validation** at `applyDelta` boundary. Catches `/ui/map/markrs/-` typos at write time. Pairs naturally with the lint suite if/when it lands.
- **Optional**: fold `serverId` into a dedicated Server scope owning the bus map. Keeps multi-server behavior unambiguous if Server scope ever expands.
- **JS bidirectional bindings** (CodeMirror first). Slots in as a fourth foreign-runtime adapter on the unified bridge.
