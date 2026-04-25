# Integrating Flutter packages into the soliplex stack

This is the second pattern after the figlet.js / chat code-fence registry
work captured in `docs/integrating-js-libraries.md`. That doc covers
**static rendered output** — a JS library called once per message,
producing a string we drop into the chat transcript. This doc covers the
next step up: **a live, controller-driven UI** mounted alongside the
chat, fed by multiple input pathways, and observable as reactive state.

The reference integration is `flutter_map`, wired as
`packages/soliplex_agent_maps/`. Cross-link, don't repeat — the
cross-cutting infrastructure (Riverpod-as-DI, signals, ClientTools,
`extraExtensions`) is documented elsewhere.

## 1. Why a Flutter package and not a JS map

A map could have been Leaflet or MapLibre wrapped behind
`dart:js_interop`. That route was rejected for this surface:

- **Pure Dart.** No `dart.library.js_interop` conditional imports, no
  `_web.dart` / `_stub.dart` split, no JS-bridge round-trips for every
  `move`/`zoom` call.
- **One package, every platform.** The same `flutter_map` runs on
  `-d chrome --wasm`, macOS, iOS, and Android. The figlet path is
  web-only by construction; the maps path isn't.
- **Direct controller access.** `MapController` is a Dart object. Tools
  call `controller.moveAndRotate(...)` synchronously instead of marshalling
  a method invocation across a JS boundary.
- **Trade-offs.** Tile rendering is a raster `CanvasKit`/Skia composite,
  not native canvas; no GPU vector tiles like MapLibre offers. For the
  demo surface (OSM raster tiles, a handful of pins, a polyline tour),
  the trade is fine.

The lesson from figlet (CanvasKit can't see system fonts, must bundle
`RobotoMono`) does **not** bite here — `flutter_map`'s text labels
inherit from the parent theme, and tile glyphs are baked into the PNGs.

## 2. Package layout

`packages/soliplex_agent_maps/` mirrors the existing
`packages/soliplex_agent_monty/` shape. Concrete file paths:

| Path | Role |
| --- | --- |
| `packages/soliplex_agent_maps/lib/soliplex_agent_maps.dart` | Public barrel re-exports the four `src/` files. |
| `packages/soliplex_agent_maps/lib/src/map_extension.dart` | `MapExtension extends SessionExtension with StatefulSessionExtension<Map<String, Object?>>`. Owns the `MapController`, the basemap / markers / polylines / polygons / viewport signals, and bridges `MapEvent`s into the aggregated `state` map. |
| `packages/soliplex_agent_maps/lib/src/map_view.dart` | `MapView({extension})` widget. The `FlutterMap` mounts here. |
| `packages/soliplex_agent_maps/lib/src/map_state.dart` | Typed `MarkerData`, `PolylineData`, `PolygonData`, `BasemapStyle`, `Viewport`. |
| `packages/soliplex_agent_maps/lib/src/map_monty_extension.dart` | `dart_monty` bridge — exposes `map_fly_to`, `map_add_marker`, etc. as Python externals. |
| `lib/src/maps_singleton.dart` | App-level `final MapExtension mapExtension = MapExtension();` consumed from `lib/main.dart` and `lib/src/modules/room/ui/room_screen.dart`. |
| `packages/soliplex_agent_maps/test/map_monty_extension_test.dart` | Real-runtime integration test — Python script -> bridge -> signal mutation. |

Reasonable rule of thumb when porting this layout to the next live UI:
one extension class, one view, one typed-state file, one optional
Monty-bridge file, one app-level singleton, one barrel.

## 3. The persistence problem (and the singleton fix)

`MapExtension` is a `SessionExtension`. By default `soliplex_agent`
attaches and detaches extensions per `AgentSession`:

- A getter that walks the active session
  (`_activeSession?.getExtension<MapExtension>()` — see
  `lib/src/modules/room/thread_view_state.dart`) returns `null` once the
  session completes and `_activeSession = null`. Any widget gated on
  that getter unmounts.
- Per-session re-creation also disposes the `MapController`, which kills
  any widget binding even before the unmount.
- Re-creating the extension also resets every signal back to its
  initial state. Drop a pin, finish the turn, send another message —
  pin gone.

**Fix.** Hoist the extension into a top-level singleton.

`lib/src/maps_singleton.dart` is a thirteen-line file:

```dart
import 'package:soliplex_agent_maps/soliplex_agent_maps.dart';

final MapExtension mapExtension = MapExtension();
```

Both `lib/main.dart` (registers it for the Monty bridge) and
`lib/src/modules/room/ui/room_screen.dart` (mounts the widget) import
the same instance. The `extraExtensions` factory passed to
`standard()` returns this same object every time it is invoked, so
every session attaches to the **same** `MapExtension`.

Two changes to the extension itself made this safe (see
`packages/soliplex_agent_maps/lib/src/map_extension.dart`):

- **`onAttach` is idempotent.** It cancels the prior `_mapEventSub`
  before resubscribing, so attaching to a second session doesn't leak
  the previous subscription. The comment in the source spells this out:
  *"the same instance may attach to many sessions over time when used
  as an app-level singleton."*
- **`onDispose` is narrow.** It cancels only `_mapEventSub`. The
  `MapController`, the `http.Client`, and every signal are intentionally
  retained. The widget bound to the controller stays alive across
  session boundaries.

This is the v0 mount described in `docs/plans/message-containers.md`.
v1 will replace the bare global with a typed *container registry* —
the host owns one controller per container kind, the view binds to
whichever container is currently mounted. The singleton pattern is
fine for the demo scope but doesn't scale to multiple maps in a
thread.

## 4. The `MapController` lifecycle gotcha

`MapController.move(...)`, `moveAndRotate(...)`, and `fitCamera(...)`
all throw if no `FlutterMap` widget has rendered:

> `MapController used before FlutterMap rendered`

This bites in three places:

- **At cold start.** The room screen mounts before any session exists.
  An LLM tool call could (in principle) fire before the user opens the
  map drawer.
- **During session boundaries.** A new session starts, `onAttach`
  re-subscribes to `mapEventStream`, but the widget has already torn
  down once.
- **In unit tests.** Constructing a `MapExtension` and calling `flyTo`
  in a `dart test` suite has no widget tree at all.

The defensive pattern in `map_extension.dart`:

```dart
try {
  _controller.moveAndRotate(LatLng(lat, lng), zoom, rot);
} on Object catch (_) {
  // MapController throws if the widget hasn't laid out yet — skip.
}
```

`_animateCamera` and `flyTo` both swallow these throws. The animation
loop emits 60 calls per second; dropping the calls that fire before
mount is cheaper than gating every call on a widget-mounted flag, and
the visible result is identical (zero frames render anyway).

The drawer pattern in `lib/src/modules/room/ui/room_screen.dart` keeps
the widget alive even when collapsed:

```dart
AnimatedSize(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeOut,
  alignment: Alignment.topCenter,
  child: _mapDrawerOpen
      ? SizedBox(height: 320, child: MapView(extension: mapExtension))
      : const SizedBox(width: double.infinity, height: 0),
),
```

When `_mapDrawerOpen` is false, the `MapView` is **not** in the tree
(this is the conditional). `AnimatedSize` only animates the height
transition. If you need the controller to be valid even with the
drawer closed, mount `MapView` unconditionally inside an `Offstage` or
a zero-height `SizedBox` instead — the `try/catch` in `_animateCamera`
makes either choice safe.

## 5. CanvasKit + WASM specifics

The worktree runs under Flutter's WASM target:

```sh
flutter run -d chrome --wasm
```

A few things are worth knowing:

- Tile loads are plain HTTP fetches. The wired providers are OSM (default),
  OpenTopoMap, CartoDB Voyager Positron, and CartoDB Voyager Dark — see
  `BasemapStyle` in `packages/soliplex_agent_maps/lib/src/map_state.dart`.
- ToS attribution is non-optional. `MapView` renders an `_AttributionPill`
  pinned to the bottom-right that shows the current basemap's attribution
  string (look for the `_AttributionPill` class in
  `packages/soliplex_agent_maps/lib/src/map_view.dart`).
- The `userAgentPackageName` passed to `TileLayer` is hardcoded
  `'ai.soliplex.client'`. Document this in the open-issues section if
  you need a configurable one.
- Unlike the figlet integration, no font shipping is required —
  `flutter_map`'s text inherits from the parent `Theme`, and tile
  rasters carry their own glyphs.

## 6. Three input pathways converge on one `MapController`

This is the architectural payoff and the reason the work generalises to
other live UIs (whiteboards, audio players, code editors). The map has
three orthogonal drive paths, all mutating the same state.

| Pathway | Layer | What drives it | Where it lives |
| --- | --- | --- | --- |
| LLM ClientTool | `MapExtension.tools` | Server emits a tool call, `soliplex_agent` dispatches | `packages/soliplex_agent_maps/lib/src/map_extension.dart` |
| Monty Python externals | `MapMontyExtension.functions` | A `run_python_on_device` script calls `monty.map_fly_to(...)` | `packages/soliplex_agent_maps/lib/src/map_monty_extension.dart` |
| User gesture | `MapView` `onLongPress` callback | Long-press anywhere on the map drops a pin | `packages/soliplex_agent_maps/lib/src/map_view.dart` |

All three call into the **same** `MapExtension` public typed methods —
`flyTo`, `addMarker`, `clearAll`, `setBasemapStyle`. All mutations flow
through the same signals. The widget repaints; the aggregated
`state` map updates for any observer (the per-extension state panel in
debug builds, the AG-UI mirror later, any test).

The long-press-to-drop-pin handler in `map_view.dart` is the proof-of-
concept that the user pathway is just another caller, not a special
case:

```dart
onLongPress: (tapPosition, point) {
  extension.addMarker(
    lat: point.latitude,
    lng: point.longitude,
    pulse: true,
  );
},
```

That is exactly the same call the LLM tool executor makes after parsing
JSON arguments, and exactly the same call the Monty bridge handler
makes after parsing typed `HostFunction` arguments.

## 7. Function-naming gotcha for dart_monty extensions

`dart_monty`'s `ExtensionCoordinator._checkFunctionCollisions` requires
that every function name on a `MontyExtension` be prefixed with the
extension's `<namespace>_`. So an extension with `namespace = 'map'`
must declare functions named `map_fly_to`, `map_add_marker`, etc.

Two consequences:

- In Python the call uses the prefixed flat name, **not** dotted
  namespacing:

  ```python
  monty.map_fly_to(40.7128, -74.0060, zoom=12)   # correct
  monty.map.fly_to(40.7128, -74.0060, zoom=12)   # wrong
  ```

- If you forget the prefix you get this exception at extension
  registration:

  ```text
  Invalid argument(s): Function "fly_to" in extension "map" must be
  prefixed with "map_"
  ```

The dartdoc on `MapMontyExtension` in
`packages/soliplex_agent_maps/lib/src/map_monty_extension.dart` cites
`ExtensionCoordinator._checkFunctionCollisions` directly — track the
rule down there if you suspect it's changed.

## 8. Public typed API on `MapExtension` — the dual-call-path solution

Two dispatchers need to do the same work:

- ClientTool executors take `(ToolCallInfo, ToolExecutionContext)` and
  return a JSON-encoded string. Arguments come in as a JSON string on
  `toolCall.arguments`.
- Monty `HostFunction` handlers take `(Map<String, Object?> args, ctx)`
  and return any JSON-serialisable value. Arguments come in already
  parsed and type-coerced.

The duplication-avoiding pattern is to hoist a typed Dart method on
the extension and have **both** dispatchers call it. The current code
does this for the four most-used calls (the `// ---- Public typed API`
section of `packages/soliplex_agent_maps/lib/src/map_extension.dart`):

```dart
Future<void> flyTo({...});
String addMarker({...});
void clearAll();
bool setBasemapStyle(String name);
Map<String, Object?> viewportJson();
```

`MapMontyExtension` calls each of these directly. The ClientTool
executors *also* end up here, but they still inline their JSON
arg-parsing. A v1 refactor (also tracked in
`docs/plans/message-containers.md`) collapses both pathways onto these
methods plus a single arg-coercion helper.

## 9. Testing pattern for Python ⇄ Dart-state integration

The end-to-end test that proves the bridge actually bridges lives at
`packages/soliplex_agent_maps/test/map_monty_extension_test.dart`. The
shape:

1. Construct a `MapExtension` directly.
2. Construct a `MontyRuntime(extensions: [...defaultExtensions(),
   MapMontyExtension(mapExt)])`.
3. Run a Python script via `runtime.execute(code)`.
4. `await handle.result` and assert against `mapExt.markers.value` (or
   any other signal).

This proves the entire chain: Python script → `MapMontyExtension`
handler → `MapExtension` public typed method → signal mutation. No
Flutter widget tree required.

Two caveats called out in the test file's leading comment:

- `flyTo` doesn't change the viewport signal in unit tests because no
  `FlutterMap` widget is mounted, so `MapController.moveAndRotate`
  throws and the `try/catch` swallows it. The signal is updated by the
  `mapEventStream` listener, which never fires. To assert viewport
  mutation, write a widget test that mounts `MapView`.
- These tests exercise the FFI dart_monty backend by default. WASM
  coverage requires `-p chrome` plus the dart_monty WASM assets — a
  follow-up.

## 10. UX details that matter

A small grab-bag of decisions that turned out to matter for the live-UI
shape, captured here so the next consumer doesn't relitigate them:

- **Long-press to drop a pin.** Single-tap conflicts with pan-after-tap
  on touch devices. Long-press is unambiguous. See the `MapOptions`
  block in `packages/soliplex_agent_maps/lib/src/map_view.dart`.
- **Animated drop.** `_AnimatedPin` tweens the pin sliding down with an
  elastic curve. Without it, programmatically-dropped pins look like
  teleports.
- **Optional pulse.** `MarkerData.pulse: true` draws a halo around the
  pin to direct attention — used by `pulse_marker` and by the long-press
  handler.
- **Explicit zoom buttons.** Pinch-zoom works on trackpads; desktop mice
  and laptops without trackpads need `_ZoomControls` (top-left). Don't
  rely on scroll-wheel zoom alone.
- **Compass with reset.** `_CompassButton` (top-right) shows the current
  rotation as a rotating needle and resets to north on tap. Without it,
  rotation is a one-way trip.
- **Drawer closed by default.** The map is *interesting* but it is also
  *320 pixels tall*. Closed-by-default keeps the chat usable until the
  user wants the map.

## 11. Open issues / deferred

Captured here so the next consumer doesn't think they're a regression:

- `flutter_map` 8.x's `MapController` is single-instance — two
  `MapView`s contesting the same controller behave badly. The container
  plan addresses this (a single host-side controller bound to whichever
  view is currently visible).
- **No serialization yet.** A page reload loses all markers and the
  camera position. The aggregated `state` map is JSON-serialisable on
  purpose, so persistence will plug into the existing soliplex
  S1/S2/S3 activity-persistence stack rather than inventing a new one.
- **Hardcoded user-agent.** `userAgentPackageName: 'ai.soliplex.client'`
  in `map_view.dart`'s `TileLayer` should be configurable per consumer.
- **Geocode is best-effort.** `geocode` uses Nominatim, rate-limits
  itself to 1 req/sec per the Nominatim ToS, and returns an error
  payload (not a throw) on 4xx/5xx so the LLM can recover. Some
  corporate networks block `nominatim.openstreetmap.org` — document
  this for downstream consumers.
- **AG-UI state pathway not wired.** The third pathway envisaged in the
  message-containers plan — server-pushed state mirroring the same
  signals — is not wired in this worktree.
- **Python-side reactive subscriptions.** Subscribing from a Python
  script to viewport changes (e.g. "tell me when the user pans
  somewhere") needs the dart_monty callable / streaming / signals
  additions tracked in `~/dev/plans/dart-monty-extension-api-additions.md`.
  The Python-to-Dart direction works today; Dart-to-Python doesn't.

## 12. Quick consumer checklist for the next live UI integration

Adding a whiteboard? An audio player? A code editor? An ag-ui-driven
form? The "container-style" Flutter package recipe:

- New package under `packages/soliplex_agent_<name>/`. Mirror the
  `soliplex_agent_maps/lib/src/` layout: `<name>_extension.dart`,
  `<name>_view.dart`, `<name>_state.dart`, plus an optional
  `<name>_monty_extension.dart`.
- One `<Name>Extension extends SessionExtension with
  StatefulSessionExtension<Map<String, Object?>>`. Aggregate all
  per-extension state into the `state` map so observers see one shape.
- One `<Name>View({extension})` widget. Document any controller-
  lifecycle pitfalls in the file's leading dartdoc — anything analogous
  to "`MapController` throws before mount" needs a comment.
- Public typed API on the extension. ClientTools and (optional)
  MontyExtension both call into it. Don't duplicate logic across both
  dispatchers.
- Singleton in `lib/src/<name>_singleton.dart` if state must persist
  across sessions. Make `onAttach` idempotent. Make `onDispose` narrow —
  cancel per-session subscriptions only; keep controllers, signals,
  and external clients alive.
- Mount the widget in `lib/src/modules/room/ui/room_screen.dart`. Gate
  on the singleton, not on the active session. A drawer or fixed-mount
  is fine; either way, keep the widget in the tree (or be willing to
  swallow controller-before-mount throws as `MapExtension` does).
- If wiring Monty: prefix every function name with `<namespace>_`.
  Export the `MontyExtension` class from the package barrel.
- Add ToS / attribution disclosures if the package fetches third-party
  data (`_AttributionPill` is the precedent).
- Test by exercising **both** pathways — at minimum a real-runtime
  Python integration test (see `test/map_monty_extension_test.dart`),
  ideally a Flutter widget test that drives the ClientTool side.

## See also

- `docs/integrating-js-libraries.md` — the static-rendered-output
  pattern (figlet.js + chat code-fence registry).
- `docs/plans/message-containers.md` — the v1 plan that supersedes the
  singleton mount with a typed container registry.
- `~/dev/plans/dart-monty-extension-api-additions.md` — the
  callable / streaming / signals additions that close the
  Dart-to-Python reactive gap.
