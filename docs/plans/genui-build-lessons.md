# GenUI build report — lessons from P0–P4

Companion to [`message-containers.md`](./message-containers.md). The
container/surface abstraction the earlier doc sketched landed in
five client-side phases on the `genui/framework-only` branch
(commits `b2083d0` → `beec5d5`). This report captures what worked,
what surprised us, and what the abstraction validated.

## What shipped

| Commit | Layer | Capability |
| --- | --- | --- |
| `b2083d0` | `soliplex_client` | `Surface<S>` / `StateProjection<S>` / `StateBus` (pure Dart) + `RagSnapshotProjection` fitness test. `signals_core` dep added. |
| `22911ca` | `soliplex_agent` | `AgentSession.agentState` reactive signal — first reactive exposure of `Conversation.aguiState`. |
| `9c4ffbe` | app | `StateBus` per-thread, owned by `ThreadViewState`. Auto-feeds from session attach. |
| `ea5d3ea` | app | `NarrationController implements Surface<List<Narration>>`; `narrate_say` keeps working; AID DISTRIBUTION replay button drives the panel via a projection. |
| `2af3e08` | app | Bug fix — single stable signal in NarrationController. |
| `beec5d5` | `soliplex_agent_maps` + app | `MapMarkersProjection` / `MapSpritesProjection` / `MapHudProjection` / `MapRouteProjection`; wire methods on `MapExtension`; replay refactored to emit-state-only. |

End state: clicking **AID DISTRIBUTION** in any room emits a
synthetic agent-state stream into a free-standing `StateBus`; four
projections (narration, markers, sprites, HUD) consume it; their
respective renderers paint the result. Camera flight + the live
clock stay imperative because they're viewer/host concerns, not
agent state.

## Lessons

### 1. Sealed types stay sealed; siblings are free

`Conversation.aguiState` was already a `Map<String, dynamic>`; we
exposed it via a `computed()` signal on `AgentSession`. That's it
— no new event variant, no sealed-switch sweeps. Cost: zero
exhaustive-switch breakage.

This validated the strategy doc's "prefer sibling types over
sealed branches" rule. We'd already followed it for `Narration`
(not a `ChatMessage` subtype). When this work needed an
agent-state surface, the same rule paid off again.

### 2. The single-watched-signal pattern is non-negotiable

First cut of `NarrationController.wireProjection(...)` swapped the
underlying signal field from `_imperative` to `_projected`. The
panel's `Watch` was bound to whichever signal it read first.
Result: replay ran, agent state emitted, projection produced
values, panel stayed empty. The Watch never saw the new emissions
because it was still subscribed to the dead `_imperative` signal.

Fix: keep one stable signal that the widget always watches.
Wiring a projection means *forwarding* into that signal, not
swapping references. Documented as the canonical pattern in
Appendix B's lifecycle doc.

This bug doesn't exist in the rag-style code that just calls
`.fromJson()` on a value; it only appears when you mix
"swap-the-source" with `signals_flutter`'s `Watch`.

### 3. Camera vs state — separate concerns

A subtle architectural choice paid off: the camera (where the
viewer is looking) is *not* in agent state. That's a human/UX
concern, not an agent concern. The agent says "the convoy is at
(lat, lng)"; the client decides whether to follow with the camera.
Keeping camera flight imperative meant the projection refactor
shrank rather than ballooned — `MapSpritesProjection` carries
positions; the room screen still calls `flyTo` between sites for
cinematic effect.

The same separation applies to:

- The **live-tick clock** — Dart-side `Timer.periodic` rendering
  elapsed time × `time_scale`. Not in agent state.
- **HUD anchor positions** — the agent emits banner/tonnage text;
  the projection chooses which corner.

Anti-rule: if you find yourself adding a "camera" or "clock" or
"reserved-pixel" key to `agentState`, that's the symptom of
crossing the seam wrong.

### 4. The contract fit four very different surfaces

The fitness test that mattered: `StateProjection<S>` had to fit
narration (separate package, separate widget, list of typed
records), map markers (collection of records), map sprites (similar
shape but renders as overlays not pins), and HUDs (corner-anchored
overlays in a Stack above the map). All four conformed without
contract changes. `StateProjection<S>.project(Map) -> S` was the
right shape.

If any one had needed a different signature, that would have
proven the contract too narrow. None did.

### 5. Imperative + projected coexist (last-writer-wins)

For v1 we chose: when a projection is wired, projected state wins
over the projection's signal. Imperative writes are *dropped* on
narration (clean policy) and *coexist* on the map (simpler). The
replay's leftover imperative HUD calls (live-tick clock) work
fine alongside projected HUDs because they target different ids.

If we'd insisted on "projection-only when wired" across all
surfaces, the Dart-side clock would have needed its own surface
type, or we'd have crossed the camera/state seam wrong (lesson
#3). Pragmatic choice; revisit when two surfaces need *both* paths
contending for the same id.

### 6. signals_core in pure-Dart packages — no purity break

`soliplex_client/CLAUDE.md` is strict: no Flutter imports.
`signals_core` (vs `signals_flutter`) is the pure-Dart sibling and
was already a `soliplex_agent` dep at the same version. Adding it
to `soliplex_client` cost one pubspec line and zero contract
changes. The Flutter widget layer keeps using `signals_flutter`
on top.

This was the question that scared me most going into P0 — that
"pure Dart" would force a hand-rolled mini-signals system. It
didn't.

### 7. The bridge is one signal, not a stream of events

The plumbing I expected: a `Stream<AgentStateEvent>` carrying
snapshots and deltas, with the bus reducing them. The plumbing
that worked: a `ReadonlySignal<Map<String, dynamic>>` that just
*holds* the current map. Each `RunState` emits a new
`Conversation.aguiState`; the signal re-fires; projections re-run.
No event reduction in the client — that already happened
upstream in `agui_event_processor.dart`.

This is a smaller mental model. Worth writing down so the next
person doesn't reach for a stream when a signal will do.

## What did NOT need to change

- `agui_event_processor.dart` — already mutates
  `Conversation.aguiState` correctly.
- `RunOrchestrator` — already emits `RunState` per change.
- `MapView` widget — already renders from
  `_markers` / `_images` / `_huds` signals; the wiring methods
  forward into those exact same signals, so no widget code moved.
- `NarrationPanel` — same. One stable signal, never replaced.

This was the strongest signal that the abstraction belonged where
we put it. New code is glue between existing reactive primitives;
no UI layer or domain layer was rewritten.

## What's next (post-v1)

- **P5 (this doc).** Done.
- **P6** — Two-way binding spike. `Surface.emit(SurfaceEvent)` is
  a no-op default today; first interactive surface (proposed
  CodeMirror or a dragable map marker) will exercise it.
- **OsCall surface integration** — file-backed surfaces. Out of
  scope for v1; surface contract has the slot.
- **Server-side AID DISTRIBUTION** — Appendix A of the plan.
  Backend room + scripted agent in `/Users/runyaga/dev/soliplex/`
  emitting the same state shape the client demo replay uses.
  When that lands, swap the local replay for a real session and
  verify the projections fire identically.
- **Schema validation in v2** — `agentState['ui']` is free-form
  today. `genai_primitives` (from flutter/genui) ships
  `json_schema_builder`; pure-Dart, plausible drop-in for
  per-surface schema validation.

## References

- Plan + appendices:
  `/Users/runyaga/.claude/plans/snuggly-floating-thompson.md`
- Original container sketch: `docs/plans/message-containers.md`
- Strategy / containers lessons (deleted in disentangle, captured
  in plan Appendix B's lifecycle docs).
