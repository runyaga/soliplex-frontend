# Message containers — rich widgets inline in chat messages

## Problem

We have two kinds of LLM-driven UI living in the room today:

1. **Stateless rendered output** — figlet ASCII art. The tool returns a
   string, the LLM wraps it in the figlet fence, the markdown layer
   dispatches to `_FigletBlock`, which renders monospace text. Every
   message gets a fresh, independent widget. State is just the string.
2. **Stateful, externally-driven UI** — flutter_map. `MapExtension` owns
   a long-lived `MapController`. The LLM calls tools (`set_map_view`,
   `add_marker`, …) that drive the controller imperatively. The `MapView`
   widget binds *one* `FlutterMap` to that controller. Without a mounted
   `MapView`, controller calls throw `MapController used before
   FlutterMap rendered`.

The figlet pattern doesn't generalize to maps because:

- `MapController` is single-binding. Two `MapView`s contesting the same
  controller behave badly.
- Map state spans many turns. Scrolling a `MapView` widget out of the
  message list and back must not reset the camera.
- Python scripts (via monty) must drive the same controller.

We need an abstraction that supports **inline-on-message** rendering
*and* a **persistent backing instance**. Call this a **message
container**.

## Design

### Concept

A *message container* is a typed, host-side instance that:

- has a stable identity (an `id`),
- owns its mutable state and any imperative controller,
- exposes a tool-callable surface (used by `ClientTool`s and Monty
  externals — same instance, both layers),
- renders a Flutter widget when requested by a chat message.

Rendering is decoupled from ownership. A container exists whether or
not any message is currently mounting its widget.

### Lifecycle

```text
LLM tool call           Container created (or looked up by id)
  ↓
Container state mutates (camera moves, marker added)
  ↓
Render request (markdown ```container language tag, or sidebar)
  ↓
Widget mounts, attaches to container, paints current state
  ↓
Widget unmounts (scroll-out / message replaced)
  ↓
Container persists; next mount picks up where the last left off
```

The container survives mount/unmount. The widget does not — it is just
a view onto the container.

### Three pieces

```text
ContainerRegistry        ← session-scoped, holds all live containers
  ├── MapContainer       ← extends Container, owns MapController
  ├── (future) SqlContainer, ChartContainer, EditorContainer, ...
  │
  ↓ exposes ClientTool surface
SessionExtension wrappers (MapExtension already exists for this layer)
  │
  ↓ exposes Python externals
MontyExtension wrappers (MapMontyExtension — TBD)
  │
  ↓ exposes Flutter widget
ContainerView({required String id, required Container kind})
  └── delegates to kind-specific widget (MapView, EditorView, …)
```

### Render dispatch — fence registry pattern, generalised

The figlet/svg case in `code_block_builder.dart` already dispatches by
language tag. Extend it:

```dart
if (language == 'container') {
  final spec = jsonDecode(code) as Map<String, Object?>;
  final containerId = spec['id'] as String;
  final kind = spec['kind'] as String;
  return ContainerView(id: containerId, kind: kind);
}
```

The LLM emits:

````markdown
```container
{"id": "main-map", "kind": "map"}
```
````

When the markdown renderer hits that fence, it builds a
`ContainerView`, which looks up `main-map` in the registry, finds a
`MapContainer`, and instantiates `MapView` bound to it.

`set_map_view` and friends already operate on the `MapContainer`'s
controller. The widget paints the current state. Tool calls in
*subsequent* turns mutate the container; if the user scrolls back to
the message, the widget reattaches and paints whatever's current — no
state loss.

### Single instance per id, not per message

If the LLM emits the same `{"id": "main-map", "kind": "map"}` block in
five separate messages, all five widgets attach to the *same*
container. Only one paints at a time (whichever is in the visible
viewport). The fence is a *handle*, not a constructor.

### Why not "give every message its own map"?

You can — by passing a different `id` per message. But the default
should be **one container per kind per session**, with the LLM (or
Monty) choosing to spawn a second only when it actually means a second
map (e.g. an A/B view comparison).

Discovery: a `list_containers` tool returns
`[{id, kind, summary}, ...]` so the LLM knows what already exists
before creating another.

## What this means for the maps work

### Now (unblock the demo)

1. Mount **one** `MapView` somewhere visible in the room screen (e.g. a
   collapsible side panel or above the chat thread). Skip the
   inline-on-message work for now — it's the bigger refactor.
2. Wire `MapView` to the existing `MapExtension` instance reachable
   through the session. This gets the demo working today.
3. Caveat in the doc: this is the v0 mount; v1 is the message-container
   refactor below.

### Next (the proper refactor)

1. Introduce `Container` interface, `ContainerRegistry`, and
   `ContainerView` widget in a new package (probably
   `packages/soliplex_frontend_containers`, or sibling to
   `soliplex_agent`).
2. Refactor `MapExtension` to delegate to a `MapContainer`.
3. Refactor `_FigletBlock` to be a stateless `ContainerView` for kind
   `figlet` (a *trivial* container — its state is just the rendered
   string). This validates that the abstraction handles both stateful
   and stateless cases.
4. Add the ` ```container ` fence dispatch in `code_block_builder.dart`.
5. Provide a `list_containers` tool, plus a `discard_container(id)`
   tool for cleanup.
6. Update `docs/integrating-flutter-packages.md` (and the figlet doc)
   to describe the container pattern as the new way to add rich UI.

### Cross-cutting with Monty

Externals exposed to Monty mirror the container's tool surface. The
`MapMontyExtension` operates on the same `MapContainer` instance the
LLM tools see. A Python script that loops through cities and calls
`monty.map.fly_to(...)` drives the same widget that's painted in the
chat. Same controller, two callers.

## Three input pathways converge on a container

The container is **driven by multiple sources**, all writing into the
same reactive state. The widget observes that state and re-paints. The
sources are:

```text
                  ┌──────────────────────────┐
   LLM tool call ─┤                          │
                  │     ContainerState       │
   Monty Python ──┤   (signal-backed,        │── observed by Widget
   (call + signal)│    multi-writer)         │
                  │                          │
   AG-UI state ───┤                          │
   /activity      │                          │
   snapshots      └──────────────────────────┘
```

### 1. LLM tool calls

`set_map_view`, `add_marker`, … as designed. Synchronous mutations to
container state.

### 2. Monty Python — calls and signals

- **Calls**: `monty.map.fly_to(lat, lng)` — same operation the LLM
  tool does, just from a Python script. Implementation: a
  `MapMontyExtension` registers Python externals that drive the same
  `MapContainer`.
- **Signals**: Python can both *emit* signals into a container's state
  and *subscribe* to changes coming from other sources. Use case: a
  background Python loop that polls a dataset and pushes updates into
  the map (live tracker dots), or that watches `monty.map.viewport`
  and reacts when the user pans. dart_monty's signal substrate is the
  same `signals_core` library the rest of the app uses, so the bridge
  is one-shape: a `Signal<T>` on the Dart side mirrored to a Python
  reactive primitive.

This makes Python the natural place for **scripted, interruptible,
multi-step orchestration** — the LLM writes a small Python program
once, the user (or a background tick) runs it, the container updates
reactively. The LLM doesn't need to emit one tool call per camera
move.

### 3. AG-UI state and activity snapshots

AG-UI streams two structured channels alongside the message stream:

- **State events** — declarative snapshots of agent-side state
  (`StateSnapshot`, `StateDelta`).
- **Activity events** — tool calls, tool results, custom events.

Both can drive containers:

- A `state.map.viewport` field in an AG-UI `StateSnapshot` projects
  directly onto the `MapContainer`'s viewport — the agent can declare
  "the map should be centered on Tokyo" once at the *state* level
  rather than emitting a tool call. The container subscribes to that
  field via the AG-UI client.
- An activity event tagged `kind: "map.tour"` carrying a `stops` array
  can run the tour without a separate tool call, useful when the
  server-side agent wants to drive the UI declaratively.

This pathway is read-only from the container's perspective — the
agent owns those snapshots. Locally-driven changes (tool calls, monty)
update the container directly; if the next AG-UI snapshot reflects
them, great; if not, the local state wins until the next snapshot
arrives.

### Conflict resolution

When two sources write to the same field at the same time:

- **Local writes win during a streaming run**. Tool calls and Monty
  scripts running locally have priority; the user just *saw* their
  effect, snapping back would be jarring.
- **Snapshots win at quiescence**. When no streaming run is active,
  the next AG-UI `StateSnapshot` is authoritative — this is how the
  server can correct drift.
- Each container declares its own merge rules where needed (e.g. for
  markers, set-union; for viewport, last-write-wins).

## Container declares its surface

Each `Container` subclass declares, in one place:

- the `state` shape (a typed signal),
- the LLM tool surface (`List<ClientTool>` getter),
- the Monty externals surface (a `MontyExtension` registration),
- the AG-UI projection (which `state.<path>` field maps to which part
  of `state`, plus which activity events to handle),
- the widget builder (`Widget build(BuildContext, ContainerState)`),
- the serialization story (if any).

This colocation matters because every new container kind otherwise has
to re-derive the same wiring. Once `Container` exposes those slots,
adding a new kind is a single file plus optional Monty extension.

## Open questions

- **Container size / layout** — fixed-height? Aspect ratio? Resizable
  by the user? For the v0 sidepanel mount the chat layout decides; for
  the inline-on-message version the `kind` declares its own preferred
  dimensions (map: 16:9, editor: full-bleed, sql-result: hugContent).
- **Garbage collection** — when does a container get disposed?
  Session-end at minimum. Per-thread? On `discard_container`? TBD.
- **Serialization** — should containers be persisted across sessions
  (so a thread reopened tomorrow shows yesterday's map state)? Probably
  yes for some kinds (map viewport, editor content), no for others.
  Each container declares its serialization story.
- **Authorization** — same access-policy hooks as tools? Yes, treat
  container creation and state changes like tool calls.
- **Cross-container links** — can a chart container point at a sql
  container's last query result? Yes, via id references; but defer
  until two containers want this.

## Recommended first step

Implement the **v0 sidepanel mount** so the maps demo runs *today*,
*and* commit this plan so the v1 refactor isn't lost. The v0 code is
small (~100 lines, edits to `room_screen.dart` only) and the throwaway
risk is acceptable.
