# Lessons learned — `flutter_map` + dart_monty + WASM

What the maps + Python integration taught us. Save yourself the
debugging cycles next time. Sibling to
`docs/integrating-flutter-packages.md` (architecture overview) and
`docs/integrating-js-libraries.md` (figlet pattern).

## TL;DR

It runs. End-to-end, the chain is:

1. LLM emits a `run_python_on_device` tool call with a Python script.
2. `MontyRuntimeExtension` runs it via `dart_monty`'s **WASM** Python
   interpreter in a Web Worker.
3. The script calls `map_*` externals → `MapMontyExtension` →
   `MapExtension`'s typed public API → reactive signals → `MapView`
   widget repaints.
4. The script can also **read** the current state via `map_get_view`,
   `map_get_markers`, `map_get_polylines`, `map_get_polygons`,
   `map_get_state`, `map_get_bounds` — the bridge is bidirectional.

Each step had at least one footgun. The lessons below are in
debugging-order — what we hit, what fixed it.

## 1. `MONTY_ENABLED` is compile-time, not runtime

The flag is `bool.fromEnvironment('MONTY_ENABLED')`. Dart's
`bool.fromEnvironment` is **resolved at compile time** with
`--dart-define`. Build the monty-enabled variant with:

```sh
flutter run -d chrome --wasm \
  --dart-define=MONTY_ENABLED=true
```

When `false` (default) the entire `MontyRuntimeExtension` construction
is dead-coded out and `dart_monty` bytes tree-shake away.

Symptoms when wrong:

- LLM doesn't see `run_python_on_device` in its tool list.
- No console error — the tool just doesn't exist.

Watch out:

- **Incremental builds can keep the old flag value baked in.** A
  `flutter clean && flutter pub get` is sometimes required. If
  `--dart-define` doesn't seem to be taking effect, clean first.
- The "in debug mode" line in the `flutter run` output doesn't change
  with `--dart-define`. The only reliable verification is a `print`
  of the const value at startup, or asking the LLM to list its tools.

## 2. The dart_monty WASM bridge needs three files in `web/`

When `MontyRuntimeExtension` is constructed on web, its underlying
`MontyRuntime` boots a Python interpreter implemented as **a WASM
module loaded by a Web Worker**. The runtime expects three files at
URLs relative to the page origin:

| File | Purpose |
| --- | --- |
| `web/dart_monty_core_bridge.js` | Main-thread JS bridge — instantiated when the page loads. |
| `web/dart_monty_core_worker.js` | Web Worker entrypoint that hosts the WASM. |
| `web/dart_monty_core_native.wasm` | The Python interpreter (~5.9MB). |

These are not auto-copied by `flutter pub get`. Copy them once from
`dart_monty_core/lib/assets/`:

```sh
cp ~/dev/dart_monty_core/lib/assets/dart_monty_core_bridge.js web/
cp ~/dev/dart_monty_core/lib/assets/dart_monty_core_worker.js web/
cp ~/dev/dart_monty_core/lib/assets/dart_monty_core_native.wasm web/
```

Then load the bridge in `web/index.html` **before**
`flutter_bootstrap.js`:

```html
<script src="dart_monty_core_bridge.js"></script>
<script src="flutter_bootstrap.js" async></script>
```

Symptom when missing:

```text
{"value":null,"output":"","error":{"message":
  "TypeError: Cannot read properties of undefined (reading 'init')"}}
```

The TypeError is JS-flavored even though monty is Dart — the bridge JS
is missing the global object the runtime expects to call `init()` on.

## 3. WASM Python needs Cross-Origin Isolation (COI)

The WASM Worker uses `SharedArrayBuffer` to bridge main-thread state
to the Python interpreter. Modern browsers gate `SharedArrayBuffer`
behind COI:

- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: require-corp`

`flutter run` doesn't set these by default. Use `--web-header`:

```sh
flutter run -d chrome --wasm \
  --dart-define=MONTY_ENABLED=true \
  --web-header "Cross-Origin-Opener-Policy=same-origin" \
  --web-header "Cross-Origin-Embedder-Policy=require-corp"
```

Symptom: `SharedArrayBuffer is not defined` in the Worker console, or
the Worker fails to instantiate. (Memory note from earlier work:
"Flutter web COI — use Python COI server not SW" — same family of
issue, different starting point.)

## 4. dart_monty function names MUST be prefixed `<namespace>_`

`ExtensionCoordinator._checkFunctionCollisions` enforces that every
host function inside an extension be prefixed with the extension's
namespace. So an extension with `namespace = 'map'` must declare
functions `map_fly_to`, `map_add_marker`, …

In Python the call is the **prefixed name**:

```python
map_fly_to(40.7, -74.0)        # ✅
monty.map.fly_to(40.7, -74.0)  # ❌ — there's no `monty.map` namespace
```

Functions are top-level Python globals, not dotted-namespaced.

Symptom when forgotten:

```text
Invalid argument(s): Function "fly_to" in extension "map" must be
prefixed with "map_".
```

## 5. Python's `time` module is not in dart_monty's stdlib

Most CPython stdlib is unavailable. Notably **`time.sleep` is missing**,
which kills the most common pause pattern in tour scripts. We added a
`map_sleep_ms(ms)` external that wraps `Future.delayed` on the Dart
side. Pattern for any new "needs to wait" spot:

```dart
HostFunction(
  schema: HostFunctionSchema(
    name: 'map_sleep_ms',
    params: const [HostParam(name: 'ms', type: HostParamType.integer)],
    description: '...',
  ),
  handler: (args, ctx) async {
    final ms = args['ms']! as int;
    if (ms > 0) await Future<void>.delayed(Duration(milliseconds: ms));
    return null;
  },
),
```

Also missing in our environment: `math` (no `sin`/`cos`), `random`,
`json` (you get a Python dict back from externals; you don't need to
parse strings). Cardinal-direction math is fine; arbitrary-bearing
trig needs precomputed tables until we add a math external (or land
the dart_monty signals/streaming/callable plan that lets
`monty_http_get` return parsed JSON).

## 6. `MapExtension` must be a session-spanning singleton

`SessionExtension`s normally attach/detach per `AgentSession`. The
default lifecycle:

- `onAttach` when a session spawns.
- `onDispose` when the session ends — which **disposes the
  `MapController`** in the agent-built version.
- `_activeSession = null` between sessions.

If `MapView` is gated on `_activeSession?.getExtension<MapExtension>()`
(which our v0 was), the widget unmounts the moment the agent finishes
its run and the user is left looking at empty space.

Fix: a top-level singleton (`lib/src/maps_singleton.dart`):

```dart
final MapExtension mapExtension = MapExtension();
```

The same instance is returned by `extraExtensions` for every session.
Two changes inside `MapExtension` make this safe:

- `onAttach` cancels any prior `_mapEventSub` before resubscribing
  (idempotent — same instance can be attached to many sessions).
- `onDispose` only cancels the per-session subscription. Controllers,
  HTTP client, and inner signals are intentionally retained.

Documented v1 work: a typed `Container` registry that owns this state
in a more principled way (`docs/plans/message-containers.md`).

## 7. `MapController` throws if `FlutterMap` hasn't rendered

flutter_map's `MapController.move()` and friends throw with:

```text
You need to have the FlutterMap widget rendered at least once before
using the MapController.
```

If the LLM calls a map tool *before* the widget mounts, the call
fails. There are two layers of mitigation in the current code:

- The `_animateCamera` helper wraps each `_controller.moveAndRotate`
  in `try { ... } on Object catch (_) { /* drop */ }` so calls before
  layout are silently skipped.
- The drawer keeps `MapView` mounted even when collapsed —
  `AnimatedSize` shrinks the parent box to height 0 but `FlutterMap`
  itself stays in the tree, controller stays bound. Don't replace
  `MapView` with `null` when the drawer closes.

## 8. Layout overflow when the drawer opens

`AnimatedSize` revealing a fixed `SizedBox(height: 320)` overflowed the
chat column by ~120px on small viewports — visible in debug builds as
yellow-stripe stripes. Fix:

```dart
ClipRect(
  child: LayoutBuilder(
    builder: (context, _) {
      final maxH = MediaQuery.of(context).size.height;
      final h = (maxH * 0.4).clamp(180.0, 360.0);
      return AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: _open ? SizedBox(height: h, child: MapView(...))
                      : const SizedBox(width: double.infinity, height: 0),
      );
    },
  ),
)
```

`ClipRect` swallows tween overflow, `LayoutBuilder + MediaQuery` keeps
the drawer to a fraction of the screen, `clamp(180, 360)` keeps it
useful on phone-sized viewports.

## 9. A wider lesson — chat-pasted text is unreliable evidence

The user pasted "what the figlet copy button copies" several times
during debugging. Different pastes showed different leading-whitespace
counts, so we chased a phantom markdown-strips-leading-spaces bug for
30 minutes. Eventually instrumented `_FigletBlock` and proved the
widget received the original whitespace intact. The chat UI we were
talking through was trimming pastes.

Lesson: **trust debug prints, screenshots of the running app, or
`pbpaste | xxd`. Not text the user typed back at you.** This applies
to monty Python output too — wrap anything you want to inspect in a
delimiter so trim-on-paste can't silently mangle it.

## 10. CanvasKit doesn't see system fonts

This bit us on figlet but the principle is general. `fontFamily:
'monospace'` on Flutter Web (CanvasKit renderer) does *not* fall
through to the system's monospace font. CanvasKit's font manager
ships Roboto + Noto and only knows about fonts you bundle as Flutter
assets. For figlet alignment we had to vendor `RobotoMono-Regular.ttf`
in `pubspec.yaml`'s `flutter:fonts:` section.

Same will apply to any future container that needs a specific font
(SQL editor with a programming font, code blocks, etc.). Bundle it,
don't trust generic family names.

## 11. Test the bridge end-to-end with real `MontyRuntime`

The test pattern that proves Monty + Dart-state integration:

```dart
final mapExt = MapExtension();
final runtime = MontyRuntime(
  extensions: [...defaultExtensions(), MapMontyExtension(mapExt)],
);
final handle = runtime.execute('''
  pin = map_add_marker(40.7, -74.0, label="NYC")
''');
final result = await handle.result;
expect(result.error, isNull);
expect(mapExt.markers.value, hasLength(1));
expect(mapExt.markers.value.first.label, 'NYC');
```

See `packages/soliplex_agent_maps/test/map_monty_extension_test.dart`
— 7 tests covering each external, plus a "shared state" test that
proves Dart-side `addMarker` and Python-side `map_add_marker` write to
the same signal. The `tour script` test runs an actual loop visiting
NYC/London/Tokyo and asserts the markers are present afterward.

These run on FFI (the default for `dart test`); WASM coverage is the
follow-up — see `~/dev/plans/dart-monty-extension-api-additions.md`
for the upstream signal/streaming work that would make WASM tests
trivial.

## 12. Things still missing — known unknowns

- **Python `import` of any non-trivial module** is hit-or-miss.
  Don't assume `math`, `random`, `json`, `urllib`, etc.
- **HTTP from Python is now supported** — `http_get(url)` and
  `http_get_json(url)` ship in `lib/src/http_monty_extension.dart`.
  Subject to browser CORS. (Was an open item; see lesson #13 below.)
- **Subscriptions and streams from Python to Dart state** don't exist.
  Python can `map_get_view()` to poll, but there's no
  `for vp in map_viewport_stream(): ...`. The dart_monty plan
  (`~/dev/plans/dart-monty-extension-api-additions.md`) addresses this.
- **AG-UI state pathway** is not yet wired into containers. The plan
  document `docs/plans/message-containers.md` describes the three-way
  merge (LLM tools / Monty / AG-UI) — currently only two of three are
  live.

## 13. `MontyExtensionSet` must be a factory, not a singleton

Symptom (took ~30 min to find):

```text
Bad state: Cannot execute on a disposed EventLoopExtension
```

What happened: the terminal panel (in
`lib/src/modules/room/ui/terminal_panel.dart`) opens with a fresh
`MontyRuntime` constructed from a top-level `MontyExtensionSet` —
seeded once in `lib/src/monty_singleton.dart`. The session-attached
`MontyRuntimeExtension` separately constructs its own `MontyRuntime`
from the same shared set. Two `MontyRuntime`s now hold references to
the same extension instances (e.g. one `EventLoopExtension`,
one `MessageBusExtension`, etc.).

`MontyRuntime` takes **lifecycle ownership** of its extensions. When
the first runtime is disposed (the terminal dialog closes, or the
session ends), it disposes its extensions — which were *also* the
second runtime's extensions. Next call into the surviving runtime
fails with the disposed-state error.

Fix: change the singleton to a factory:

```dart
// monty_singleton.dart
MontyExtensionSet makeMontyExtensionSet() => MontyExtensionSet([
      ...MontyExtensionSet.standard().all,
      MapMontyExtension(mapExtension),
      HttpMontyExtension(),
    ]);
```

Each `MontyRuntime` constructor calls the factory to get a fresh set,
so each runtime owns its own disposable instances. Only the things
that are themselves singletons (`mapExtension` here — see lesson #6)
are shared by reference; the wrappers around them are fresh.

### General rule — singleton vs factory vs per-instance

We discovered we have three distinct lifetime patterns operating in
the same codebase:

| Pattern | When | Example |
|---|---|---|
| **App-level singleton** | One on-screen widget, must survive session boundaries | `mapExtension` — the `MapView` widget binds to it; sessions come and go but the user keeps looking at the same map |
| **Factory (fresh per runtime)** | Wraps something a runtime takes ownership of and disposes | `makeMontyExtensionSet()` — every `MontyRuntime` gets fresh `EventLoopExtension`, `MessageBusExtension`, etc. |
| **Per-dialog / per-screen state** | Owned by a Flutter widget's State; lives as long as the widget | `TerminalPanel`'s internal `MontyRuntime` (built in `initState`, disposed in `dispose`) |

Mixing the first two is the trap. If you have `final foo = Foo()` at
top level and Foo is a thing-that-gets-disposed, you've built a
singleton that only survives until the first dispose. Use a factory
for those.

### Heuristic

When deciding singleton vs factory, ask:

- "Will more than one consumer take ownership of this?"
   - **Yes** → factory. Each consumer gets its own.
- "Does the on-screen widget tied to this need to survive across
  sessions / runs?"
   - **Yes** → singleton (and make `onAttach`/`onDispose` idempotent
     per lesson #6).
- "Is this owned exclusively by one StatefulWidget?"
   - **Yes** → just construct in `initState`. No global anything.

## What "Python can read more from the widget" got us

Five new readback externals (`map_get_markers`, `map_get_polylines`,
`map_get_polygons`, `map_get_state`, `map_get_bounds`) on top of the
already-existing `map_get_view`. Now Python can:

- Iterate over current markers and react: `if any(m["label"] == "NYC" for m in map_get_markers()): ...`
- Check what's on the map without keeping a parallel Python copy:
  `map_get_state()["markerCount"]`.
- Compute "where is the user looking?" and respond:
  `bounds = map_get_bounds(); center_lat = (bounds["north"] + bounds["south"]) / 2`.
- Verify a tour reached its destinations:
  `assert {m["label"] for m in map_get_markers()} == {"Paris","Berlin"}`.

Plus the imperative writes (`map_fly_to`, `map_add_marker`, …) we
already had. The bridge is properly bidirectional now.

## 14. Chroma-keying generated sprites — magenta beats checker

Image-generation models love returning PNGs with a transparency-grid
checker baked in as opaque pixels. Two days of saturation-mask and
flood-fill iteration showed why this is a losing fight:

- **Saturation mask** (`-level low%,high%` on the HSL S channel)
  always leaks: JPEG compression introduces saturation noise around
  the sprite's edge, and pushing the upper bound high enough to kill
  it eats into desaturated parts of the sprite (helicopter
  windscreen, gunmetal panels).
- **Corner flood-fill** with sampled checker colors only catches the
  exact shade you sampled. JPEG dithers the checker into 4–8
  near-identical greys with sub-1% noise. Each shade needs its own
  flood, and the boundary anti-aliasing remains as a halo.

The fix: **ask the generator for a flat magenta `#FF00FF` background**.
Magenta is rare in real photography, so a single `-fuzz 12%
-transparent "#FF00FF"` knocks out the background AND its
JPEG-compressed fringe in one pass. ~75% of pixels become transparent
and the sprite has no halo.

```bash
magick input.jpeg -resize 768x \
  -fuzz 12% -transparent "#FF00FF" \
  -trim +repage -resize 384x output.png
```

Verify by compositing over a non-magenta solid color (e.g. `#2a7a2a`
green) and inspecting at 1× — any leftover magenta fringe is obvious
when it abuts an unrelated colour.

## 15. Arc-camera drop scaling — soft curve, not hard floor

The original arc formula was `dropPerKm = log2(distKm / 100)`. For
Tokyo→Seoul (1160km) that's a 3.5-level drop, which combined with a
`max(3, ...)` floor sent the camera to zoom 3 — full continental
view — for what should be a regional hop. Result: every leg of an
inter-city tour did a gratuitous "out to space and back".

Replacement: **soft curve with a 800km dead zone**.

```dart
final ratio = distKm / 800.0;
final drop = ratio <= 1
    ? 0.0
    : math.log(ratio) / math.ln2 / 1.2;
final arcZoom = math.max<double>(2, baseZoom - drop);
```

Drops by leg length:

| Leg                     | km   | drop | arcZoom from base 5 |
| ----------------------- | ---- | ---- | ------------------- |
| Tokyo → Seoul           | 1160 | 0.45 | 4.55                |
| Tokyo → Shanghai        | 1770 | 0.95 | 4.05                |
| LA → New York           | 3940 | 1.92 | 3.08                |
| Tokyo → Cape Town       | 14730| 3.50 | 2.00 (floored)      |

Close hops glide; long-haul still pulls out cinematically.

## 16. World-wrap prevention — compute `minZoom` from viewport width

`flutter_map` 8 wraps the world horizontally whenever the world's
pixel width (`256 * 2^z`) is smaller than the viewport. A static
`minZoom` is viewport-blind: 3 is too restrictive on phones and not
enough on a 4K monitor.

`MapOptions.cameraConstraint` has the right shape conceptually
(`CameraConstraint.contain(bounds: ...)` clips to a single Earth
copy), but its `constrain()` returns `null` when the camera is
zoomed too far out — and that trips this assertion the moment the
constraint is hot-reloaded into a session whose camera doesn't
already satisfy it:

```text
'newOptions.cameraConstraint.constrain(newCamera) == newCamera':
MapCamera is no longer within the cameraConstraint after an option
change.
```

The right approach is to compute the equivalent `minZoom` per-frame
from the actual viewport width:

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final wrapMin = (math.log(constraints.maxWidth / 256) / math.ln2)
        .ceilToDouble();
    final minZoom = math.max(1.0, wrapMin);
    return FlutterMap(
      options: MapOptions(
        minZoom: minZoom,
        maxZoom: 19,
        // no cameraConstraint — minZoom alone makes wrap unreachable
      ),
      ...
    );
  },
);
```

You also need to clamp `initialZoom` to be `>= minZoom`, since a
config with `initialZoom: 4` lands below the wrap floor on a 1280px
monitor.

This gives the user "zoom out exactly until just before the world
would wrap, then stop" with no assertions.

## 17. Image-overlay layer order — last child wins

`FlutterMap`'s `children` paints in declaration order: first child
goes down first, last child goes on top. If you want a sprite
(helicopter, vehicle marker) to be visible above paths and pin
markers, put its `MarkerLayer` LAST in the list. The instinct to
group "all the marker-shaped layers together" puts image overlays
right after the basemap, which sandwiches them under everything else.

## 18. Driving `flutter run` from a non-TTY needs a pty

`flutter_tools` enables single-char keys (`r`, `R`, `q`) only when
stdin is a TTY (`stdin.hasTerminal && terminal.singleCharMode =
true`). Spawning `flutter run` from a background shell — e.g.
Claude Code's `run_in_background: true` — gives flutter a pipe-stdin,
and `R` written to that pipe is silently ignored.

Two consequences:

- `dart-mcp`'s `launch_app` works (it spawns its own pty internally),
  but its schema has no way to pass `--dart-define=KEY=VALUE`, so any
  build that depends on a compile-time flag (e.g. `MONTY_ENABLED`)
  can't go through it.
- A direct `flutter run --dart-define=...` from bash needs a pty
  wrapper. `expect` works:

```tcl
#!/usr/bin/expect -f
set timeout -1
log_file -a /tmp/flutter_run.log
cd /path/to/project
spawn flutter run -d chrome --dart-define=MONTY_ENABLED=true
set fifo [open "/tmp/flutter_cmd_fifo" "RDWR"]
fconfigure $fifo -blocking 0 -buffering none -translation binary
proc poll {} {
    global fifo
    set d [read $fifo]
    if {[string length $d] > 0} { send -- $d }
    after 200 poll
}
after 100 poll
expect eof
```

Open the FIFO `RDWR` (not `r`) so the read end stays open even when
no writer is connected — otherwise `read` returns EOF and the poll
loop exits. Drive hot reload/restart from anywhere with
`printf 'R' > /tmp/flutter_cmd_fifo`.
