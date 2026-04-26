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

---

# Addendum — lessons from end-to-end integration with the server

Captured after the P0–P5 framework hit a real backend (the AID
DISTRIBUTION room on `aid-distribution` branch in
`/Users/runyaga/dev/soliplex-aid/`). The handoff doc at
`/Users/runyaga/dev/plans/genui-frontend-handoff.md` carries the
running diagnosis log; this section distills what's worth
remembering after the bugs were fixed.

## 8. Surface singletons need auto-wire on session attach

The original P3 demo button explicitly wired the singletons
(`narrationController`, `mapExtension`) against a free-standing
bus. Real sessions never wired them — agent state events flowed
to `aguiState`, the per-thread bus updated, but no projection
was registered against the singletons. **The chat showed
delta JSON; the panels stayed blank.**

Fix: `ThreadViewState._wireSurfaceSingletons()` runs on every
session attach, projecting the bus into the four singletons and
unwiring on detach. The demo button still works because it
operates on its own bus and clears/wires before/after.

**Lesson for redesign:** singleton bridges from a session's
agent state to UI controllers must be the runtime's
responsibility, not the demo's. Discover-and-wire on attach
is the only correct default.

## 9. State must outlive sessions for reload to work

First version: bus was created on session attach, disposed on
detach. Browser reload meant: load thread history → no session
→ no bus → no panels rehydrate. Even though `ThreadHistory.
aguiState` arrived from the server, nothing was reading it.

Fix: bus is per-`ThreadViewState`, lives across attach/detach,
disposed only in `dispose()`. `_fetch().then()` seeds it from
`history.aguiState` directly. Subsequent session attaches
*feed* the existing bus instead of replacing it.

**Lesson for redesign:** the reactive substrate (bus +
projections) must follow the *thread's* lifecycle, not the
session's. Sessions come and go; the agent's state survives
both attach/detach and full reload. The bus shape must match
the state shape, not the session shape.

## 10. Camera and clock are viewer concerns, not agent state

When the convoy moved (state delta updated `ui.map.convoy.lat`),
the sprite was teleporting because the wire layer just replaced
the images list. Fixed by detecting per-id position changes and
routing through the existing `moveImage` tween (lessons 5b/5c
foreshadowed this).

Camera follow is a *separate* concern: the agent doesn't say
"the camera should fly here" — that's the *viewer* deciding what
to look at. We solved it in `ThreadViewState` by subscribing to
the convoy sprite's signal and calling `flyWithImage` on
position change. The agent state stays free of camera fields.

The same separation kept the live-tick clock simple: agent emits
`ui.hud.elapsed_minutes` (advisory); the actual on-screen clock
is a Dart-side Timer with `time_scale`.

**Lesson:** any UI element whose *update cadence* is decoupled
from agent emissions belongs on the viewer side. Camera
following, animation easing, tween durations, scroll position,
hover states — all viewer. Agent emits *what is*; viewer
interprets *how to show it*.

## 11. The Watch-bound-to-old-signal trap (revisited)

Already captured as P5 lesson #2 but it bit a SECOND time on
sprite-tween implementation. When `_diffApplyImages` calls
`moveImage` (which mutates the same `_images` signal), the
panel's Watch correctly observes the in-progress tween because
the signal *instance* is stable. Conversely, if we'd swapped
`_images` for a new signal during projection, every per-frame
tween update would have been invisible.

**Single stable signal that's forwarded to** is the canonical
shape for any reactive surface in this stack. `signals_flutter`'s
`Watch` doesn't follow signal-instance swaps; it tracks the
exact signal it observed at first read.

## 12. LLMs hallucinate from prompt examples, not state

The most surprising failure mode: even after the server emitted
the right snapshot, the LLM picked the *wrong coordinates* from
prompt examples baked into the system message ("memorise these:
hub at 12.0, 102.0"). When the seed coords moved, the prompt
became a lie the LLM still believed.

Two fixes layered together:
1. **Strip baked numbers from prompts.** Replace coord examples
   with id-based examples ("the hub's id is `hub`").
2. **Force tool calls for reads.** Add a parallel "you MUST call
   `agui_state` (or `where_is_convoy`) before answering any
   read-back question." Without this, the LLM answers from
   conversation memory.

**Lesson:** the *agent state* is the source of truth, not the
prompt. Prompts should describe *behaviour* and *vocabularies*
(tool names, id namespaces) but never carry *values* the agent
might emit later. Force the LLM through tools for both reads
and writes.

## 13. Tool design: prefer id-based over coord-based

`move_convoy(lat, lng, heading)` was the obvious shape but it
forced the LLM to pick lat/lng. The LLM picks from training data,
prompt examples, conversation memory — anything but live state.

Adding `move_convoy_to_site(site_id)` that looks up coords
from current state inverted the responsibility: the LLM
chooses the *intent* (`'camp-alpha'`); the tool reads state
to compute coords. The LLM never has to know lat/lng.

Same pattern for `serve_site(site_id, ...)` (wraps
`set_site_status` but spares the LLM from having to know
"served" is the magic string).

**Lesson:** every coordinate / numeric / enum-string value the
LLM has to pick is a hallucination opportunity. Wrap with
id-based or intent-based tools that the LLM can pick from a
small vocabulary, and have the tool look up the live values
itself.

## 14. Stack-of-commits-as-PRs really does scale

Fourteen commits on `genui/framework-only`, each one logically
a single PR. Reviewing each commit's diff in isolation is
straightforward; reviewing the cumulative state is too. The
trade-offs we hit:

- **Cleanup commits** (`dd2a0fa` format, `2af3e08` signal-
  stability fix) live alongside the features they touch.
  Worth squashing into the parent before the formal review,
  but useful while iterating.
- **Test fallbacks live alongside the feature they support.**
  E.g. the text-envelope detector and the ToolCall-args
  detector are both no-ops once the proper state path lands —
  they shipped together because the value of the demo working
  *now* outweighed the cleanup cost.
- **Backend coordination via shared doc.** The handoff doc at
  `~/dev/plans/genui-frontend-handoff.md` got *six* dated
  reply sections as the integration progressed. Each captured
  the live state of "what works, what's broken, what either
  side needs from the other." Future similar work should
  start with such a doc, not retrofit one.

## 15. Multi-agent coordination patterns that worked

Frontend + server developed in parallel via:

1. **Shared plan + handoff doc** — single source of truth for
   the contract (`agentState['ui']` shape, naming, behaviours).
2. **Backend agents spawned via `Agent` tool** — three rounds
   so far (initial implementation, coord fix, state-read
   mandate). Each completed in 3–8 minutes, returned a
   structured report with commit SHAs and curl evidence.
3. **Ping-pong via the handoff doc** — frontend appends a
   dated reply when it observes a backend gap; backend reads,
   fixes, reports back. Six rounds of this in this session;
   each round narrowed the gap.

**Lesson:** asynchronous parallel agents with a shared
narrative doc beats synchronous pair-programming for
client/server work where the contract is the bottleneck.
