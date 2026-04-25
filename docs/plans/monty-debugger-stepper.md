# Monty Debugger / Stepper

Status: plan
Owner: alan@enfoldsystems.com
Date: 2026-04-25
Related: `docs/plans/message-containers.md`,
`~/dev/plans/dart-monty-ship-simplify.md`,
`~/dev/plans/monty-client-bridge.md`

---

## TL;DR

A "debugger view" container, mountable in the maps room (and any
`MONTY_ENABLED` room), that visualises a running `dart_monty` Python
script as it executes. Three panes (source / state / tool-call
timeline) plus four controls (reset / pause / step / continue).

We can ship a useful **v0** today using the host-side `MontyInterceptor`
hook to pause execution at every host function call — no upstream
changes to `pydantic/monty` required. A future **v1** would push pausing
down to Python statement boundaries; that needs a debug-step protocol
on the Python interpreter side and is explicitly out of scope.

The debugger is also a forcing function for the
`docs/plans/message-containers.md` refactor: with three concrete
container kinds (`map`, `terminal`, `debugger`), the registry and
fence-dispatch shape becomes the obvious next step.

---

## Goal

Make a running on-device Python script **legible**: show the source,
the running tool call, the per-namespace state, and a chronological
record of every host function call (with arguments, result, and
timing). Let the user pause between calls, single-step, and reset
without rebuilding the runtime.

### Non-goals

- **No** Python statement-level stepping. We pause between host
  function calls (`map_*`, `http_*`, `monty.*`, etc.). The interpreter
  runs Python at full speed between calls.
- **No** breakpoints, conditional breakpoints, or watch expressions.
  Single-stepping is the only control surface in v0.
- **No** variable inspection inside Python frames. State inspection is
  limited to extension-aggregated state via
  `ExtensionCoordinator.statefulObservations()` — i.e. the same
  `(namespace, signal)` tree the existing `ExtensionStatePanel` shows.
- **No** persistence across sessions. Debugger state is per-script-run.
  When the user re-runs, the timeline resets.
- **No** distributed / remote debugging. Local on-device only.
- **No** changes to `dart_monty` or `dart_monty_core` (the v0
  interceptor hook is already public).

---

## v0 scope

### What "step" means

A **step** advances the runtime past exactly one host-function call.

Concretely: the debugger registers a `MontyInterceptor` (the typedef
defined at `dart_monty/lib/src/host/dispatch.dart:18`):

```dart
typedef MontyInterceptor = Future<Object?> Function(
  String name,
  Map<String, Object?> args,
  Future<Object?> Function() next,
);
```

When Python calls a registered host function, the interceptor runs
*before* the handler. Our interceptor:

1. Records a `_PendingCall(name, args, startedAtMs)` into the timeline
   signal.
2. If the debugger is in **paused** mode, awaits a `Completer<void>`
   that the UI completes when the user clicks **step** or **continue**.
3. Calls `next()` to actually execute the host handler.
4. Records the result (or thrown error) and the wall-clock duration.

Because the pause sits in `await next()`'s prologue, the entire
handler runs **after** the user releases it. The pause is
*pre-call*, not post-call. This matches the user's mental model
("pause at line 4, then step over `map_geocode`") — they see the call
appear in the timeline as `running` and only after stepping does the
result appear.

### What "pause" means

`paused == true` causes the interceptor to await a fresh
`Completer<void>` *every* call. **continue** sets `paused = false` and
completes any in-flight pause-completer. **step** keeps `paused = true`
but completes the in-flight completer, so the next call will pause
again.

### What "reset" means

`reset` cancels the current execution (via `handle.cancel()` —
cooperative; see `ExecutionHandle.cancel`), clears the timeline signal,
clears the source-view source, and re-creates a fresh `MontyRuntime`
(via `clearState()` if the runtime is reusable, otherwise a new
runtime). State observations re-subscribe to the new coordinator.

`reset` also forcibly completes any pending pause-completer with
`null` — otherwise an awaited interceptor call would leak.

### Persistence model

Debugger state is **per-script-execution**, not cross-session.
Specifically:

- **Timeline** clears on `reset` and on the next `execute(code)` call.
- **Source view** is the source string passed to `execute(code)` —
  whatever was most recently submitted.
- **State pane** is a live mirror of the current
  `ExtensionCoordinator.statefulObservations()` and survives reset
  only insofar as the runtime survives reset (it doesn't, by default).

### Long-running tool calls (e.g. `map_fly_to(duration_ms=5000)`)

We pause at host-call **boundaries only**. A 5-second `flyTo` is one
boundary at the start, then 5 seconds of animation, then one
boundary at the end (the result). We do **not** step through the
animation frames. The plan should call this out in the docstring on
`DebuggerPanel` so users aren't surprised.

---

## Architecture

### Layering

```text
   ┌──────────────────────────────────────────────────────┐
   │            DebuggerPanel  (Flutter widget)           │
   │  ┌──────────┬──────────┐                             │
   │  │ source   │ state    │   ← reads from extension    │
   │  ├──────────┴──────────┤                             │
   │  │ timeline             │                            │
   │  └──────────────────────┘                            │
   │  ⏮ reset  ⏸ pause  ⏭ step  ▶ continue  ← writes      │
   └────────────┬─────────────────────────────────────────┘
                │ signals + method calls
   ┌────────────▼─────────────────────────────────────────┐
   │       MontyDebuggerExtension : SessionExtension      │
   │  - timeline: Signal<List<TimelineEntry>>             │
   │  - sourceCode: Signal<String?>                       │
   │  - paused: Signal<bool>                              │
   │  - currentCallId: Signal<String?>                    │
   │  - step(), continueRun(), pause(), reset()           │
   │  - run(String code) -> ExecutionHandle               │
   │  - constructs the MontyInterceptor that bridges      │
   │    BridgeFunctionCallStart/End -> timeline           │
   └────────────┬─────────────────────────────────────────┘
                │ owns
   ┌────────────▼─────────────────────────────────────────┐
   │   MontyRuntime  (with interceptor: ourInterceptor)   │
   │   handle = runtime.execute(code)                     │
   │     handle.events  : Stream<BridgeEvent>             │
   │     handle.result  : Future<MontyResult>             │
   │     handle.cancel()                                  │
   └──────────────────────────────────────────────────────┘
```

`MontyDebuggerExtension` parallels `MontyRuntimeExtension` (same package
shape, different responsibility). It does *not* expose a
`run_python_on_device` ClientTool — the LLM does not drive the
debugger. The debugger is a UI-only surface.

### Why a separate extension instead of reusing `MontyRuntimeExtension`

`MontyRuntimeExtension` already owns one `MontyRuntime` and exposes the
`run_python_on_device` LLM tool. Adding the interceptor and the
timeline state to it would:

- Force every LLM-driven Python execution through the interceptor (slow
  & not useful).
- Mix the LLM-tool runtime lifecycle with the user-driven debugger
  lifecycle (which the user controls via `reset`).

Cleaner: a new `MontyDebuggerExtension` with its **own** `MontyRuntime`,
just like the terminal panel has its own. Both runtimes can attach
extensions that share singletons (e.g. `mapExtension`), so a Python
script in the debugger drives the same on-screen `MapView` as the LLM.

This mirrors the pattern already in
`lib/src/modules/room/ui/terminal_panel.dart` where the dialog
constructs its own `MontyRuntime` via `makeMontyExtensionSet()`.

### Shared runtime construction

`makeMontyExtensionSet()` in `lib/src/monty_singleton.dart` returns a
**fresh** set on every call. The debugger extension calls it once on
construction:

```dart
MontyDebuggerExtension({
  required MontyExtensionSet Function() extensionSetFactory,
}) : _extensionSetFactory = extensionSetFactory;

Future<void> onAttach(AgentSession session) async {
  _runtime = MontyRuntime(
    extensions: _extensionSetFactory().all,
    interceptor: _intercept,
  );
  // subscribe to coordinator.statefulObservations() (see below)
}
```

### Interceptor sketch

```dart
Future<Object?> _intercept(
  String name,
  Map<String, Object?> args,
  Future<Object?> Function() next,
) async {
  final id = _nextCallId();
  final entry = TimelineEntry.running(
    callId: id,
    name: name,
    args: args,
    startedAtMs: DateTime.now().millisecondsSinceEpoch,
  );
  _appendTimeline(entry);
  _currentCallId.value = id;

  // Pause gate: every call awaits an opt-in completer when paused.
  if (_paused.value) {
    final gate = Completer<void>();
    _pendingGate = gate;
    await gate.future;
    _pendingGate = null;
  }

  final t0 = DateTime.now().millisecondsSinceEpoch;
  try {
    final result = await next();
    _replaceTimeline(id, entry.completed(
      result: result,
      durationMs: DateTime.now().millisecondsSinceEpoch - t0,
    ));
    return result;
  } on Object catch (e) {
    _replaceTimeline(id, entry.failed(
      error: e.toString(),
      durationMs: DateTime.now().millisecondsSinceEpoch - t0,
    ));
    rethrow;
  } finally {
    if (_currentCallId.value == id) _currentCallId.value = null;
  }
}
```

### Step / continue / pause API

```dart
void pause() {
  _paused.value = true;
}

void continueRun() {
  _paused.value = false;
  _pendingGate?.complete();
}

void step() {
  // Stay paused; release one gate so the next call also pauses.
  _paused.value = true;
  _pendingGate?.complete();
}

Future<void> reset() async {
  // Force the in-flight pause to release so the awaiting interceptor
  // returns to its caller, then cancel and rebuild.
  _pendingGate?.complete();
  await _currentHandle?.cancel();
  _timeline.value = const [];
  _sourceCode.value = null;
  _paused.value = false;
  _currentCallId.value = null;
  _runtime.clearState();
}
```

### Timeline shape

```dart
sealed class TimelineEntry {
  String get callId;
  String get name;
  Map<String, Object?> get args;
  int get startedAtMs;
}

class TimelineRunning extends TimelineEntry { /* ... */ }
class TimelineCompleted extends TimelineEntry {
  final Object? result;
  final int durationMs;
}
class TimelineFailed extends TimelineEntry {
  final String error;
  final int durationMs;
}
```

The timeline is a `Signal<List<TimelineEntry>>` so the panel can
`watch(context)` it. Append-on-write semantics; entries are replaced by
`callId` when a call transitions running -> completed/failed.

### State inspection

`MontyRuntime.coordinator` (added pre-ship in
`~/dev/plans/dart-monty-ship-simplify.md`) exposes
`statefulObservations()`. We aggregate exactly the way
`MontyRuntimeExtension` already does:

```dart
for (final (ns, signal) in _runtime.coordinator!.statefulObservations()) {
  final unsub = signal.subscribe((value) {
    _aggregateState.value = {..._aggregateState.value, ns: value};
  });
  _unsubs.add(unsub);
}
```

The state pane just renders `_aggregateState.value` as a JSON tree.
Falls through to `ExtensionStatePanel` if we want to reuse that widget.

### Source view & current-line highlight

Today, host calls do not carry a Python source-line callsite. Without
that we cannot point an arrow at line 4. Two options:

- **v0a (simple, ship today)**: highlight the **first occurrence of
  the function name** in the source via a regex pass when a call goes
  running. Wrong sometimes, fine for demo. No upstream changes.
- **v0b (slightly more)**: extend `BridgeFunctionCallStart` with an
  optional `(file, line)` field if the Rust REPL exposes it. Out of
  scope for this plan; tracked as a future enhancement.

Pick v0a. The line marker is useful as a "you are here" hint; it
doesn't have to be exact.

---

## Files

Three new files in this repo, no external changes:

```text
lib/src/modules/room/
  monty_debugger_extension.dart          (new — SessionExtension)
  ui/
    debugger_panel.dart                  (new — three-pane Widget)
    source_view.dart                     (new — line-numbered code view)
```

Plus a small edit to:

```text
lib/src/modules/room/ui/room_screen.dart   (mount + toggle button)
```

### `monty_debugger_extension.dart`

```dart
class MontyDebuggerExtension extends SessionExtension
    with StatefulSessionExtension<Map<String, Object?>> {
  MontyDebuggerExtension({
    required MontyExtensionSet Function() extensionSetFactory,
  });

  @override String get namespace => 'debugger';

  // Public reactive surface for the panel.
  ReadonlySignal<List<TimelineEntry>> get timeline;
  ReadonlySignal<String?> get sourceCode;
  ReadonlySignal<bool> get paused;
  ReadonlySignal<String?> get currentCallId;
  ReadonlySignal<Map<String, Object?>> get aggregateState;
  ReadonlySignal<bool> get running;       // true while result pending

  // User-driven controls.
  Future<MontyResult> run(String code);    // sets sourceCode, kicks off
  void pause();
  void continueRun();
  void step();
  Future<void> reset();
}
```

`run(code)` is the entry point both the panel's "run" button and a
hand-off from the terminal panel can call.

### `debugger_panel.dart`

Three-row CustomScrollView-ish layout:

```text
┌───────────────────────────────────────────────────────┐
│ ┌── source ──────────┬── state ───────────────────┐   │
│ │ SourceView         │ JSON tree (aggregateState) │   │
│ │ (highlight current │                            │   │
│ │  call's name)      │                            │   │
│ └────────────────────┴────────────────────────────┘   │
│ ┌── tool calls timeline ─────────────────────────┐   │
│ │ ListView.builder of TimelineEntry              │   │
│ └────────────────────────────────────────────────┘   │
│ ┌── controls ────────────────────────────────────┐   │
│ │ ⏮ reset    ⏸ pause / ▶ continue    ⏭ step      │   │
│ └────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────┘
```

The `pause` button toggles to `continue` based on `paused.watch()`.
`step` is enabled iff `running.value && paused.value`.

A "load source" affordance: a TextField + Run button, just like
`TerminalPanel` has. The pasted source becomes the *only* source the
debugger has tracked; on `Run`, `sourceCode` is set and `run(code)` is
called. v0 doesn't preserve a history of previous runs.

### `source_view.dart`

A scrollable, line-numbered, monospace code display. One reactive
input: `currentCallId` plus the source string. Highlights the line
where the current call's name first textually appears. Can be reused
later for the SQL/script-editor container.

---

## Wiring (room_screen.dart)

Mirror the existing `_mapDrawerOpen` pattern.

Add at top of `_RoomScreenState`:

```dart
bool _debuggerPanelOpen = false;
late final MontyDebuggerExtension _debugger = MontyDebuggerExtension(
  extensionSetFactory: makeMontyExtensionSet,
);
```

Dispose in `_RoomScreenState.dispose`.

In the bottom button row (next to map / terminal buttons, gated by
`_kMontyEnabled`):

```dart
if (_kMontyEnabled)
  IconButton(
    tooltip: _debuggerPanelOpen ? 'Close debugger' : 'Open debugger',
    icon: Icon(_debuggerPanelOpen
        ? Icons.bug_report
        : Icons.bug_report_outlined),
    onPressed: () =>
        setState(() => _debuggerPanelOpen = !_debuggerPanelOpen),
  ),
```

In `_buildThreadBody`, add a `ClipRect` slot identical in shape to the
existing map drawer (`MapView(...)` -> `DebuggerPanel(extension: _debugger)`).
Use the same `(maxH * 0.4).clamp(180, 360)` height heuristic so the
chat input stays on screen.

The debugger does **not** need a session attach to be usable; like the
terminal, it owns its own runtime and is alive as long as the
RoomScreen is mounted.

### Open question — ownership

Two reasonable choices:

1. Ext is per-RoomScreen state (above). Disposed when the user
   navigates away from the room.
2. Ext is a singleton (akin to `mapExtension`). Survives navigation.

v0 picks (1) — simpler, no global state, and consistent with the
terminal panel's per-dialog runtime. Plan to revisit when implementing
the container registry.

---

## Integration with existing terminal

When the user has both the **terminal** dialog open *and* the
**debugger panel** mounted, pasting code in the terminal and clicking
"Send to debugger" (a new button) hands off the source string to the
debugger extension via `extension.run(code)`. The terminal stays open
for follow-up REPL queries; the debugger animates through the run.

This requires:

- A way to look up the current `MontyDebuggerExtension` from the
  `TerminalPanel` (it's modal — pass a callback into the constructor
  when opening from `_openMontyTerminal`).

Concretely, modify `_openMontyTerminal`:

```dart
Future<void> _openMontyTerminal(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => TerminalPanel(
      extensionSetFactory: makeMontyExtensionSet,
      onSendToDebugger: _debuggerPanelOpen
          ? (code) => _debugger.run(code)
          : null,
    ),
  );
}
```

And in `TerminalPanel`, render an extra "Step in debugger" button
next to "Run" when `onSendToDebugger != null`.

This is optional for v0; the debugger panel has its own input field
and can be used standalone. Ship without the hand-off if it adds risk.

---

## Tests

Three integration tests in
`test/modules/room/monty_debugger_extension_test.dart`:

### 1. Timeline accumulates

```dart
test('host function calls become timeline entries', () async {
  final ext = MontyDebuggerExtension(
    extensionSetFactory: () => testExtensionSet(),
  );
  await ext.onAttach(FakeSession());

  await ext.run('''
    set_x(1)
    set_x(2)
    set_x(3)
  ''');

  expect(ext.timeline.value, hasLength(3));
  expect(ext.timeline.value.map((e) => e.name),
      everyElement(equals('set_x')));
  expect(ext.timeline.value, everyElement(isA<TimelineCompleted>()));
});
```

### 2. Step actually pauses

```dart
test('paused interceptor halts at next call', () async {
  final ext = MontyDebuggerExtension(...);
  await ext.onAttach(FakeSession());

  ext.pause();
  final fut = ext.run('set_x(1); set_x(2)');
  // pump event loop a few times
  await Future<void>.delayed(const Duration(milliseconds: 50));
  expect(ext.timeline.value.first, isA<TimelineRunning>());
  expect(fut.isCompleted, isFalse);

  ext.step();
  await Future<void>.delayed(const Duration(milliseconds: 50));
  expect(ext.timeline.value.first, isA<TimelineCompleted>());
  // Second call now paused.
  expect(ext.timeline.value, hasLength(2));
  expect(ext.timeline.value.last, isA<TimelineRunning>());

  ext.continueRun();
  await fut;
  expect(ext.timeline.value, everyElement(isA<TimelineCompleted>()));
});
```

### 3. Reset mid-run starts clean

```dart
test('reset clears timeline and runs subsequent script clean', () async {
  final ext = MontyDebuggerExtension(...);
  await ext.onAttach(FakeSession());

  ext.pause();
  unawaited(ext.run('set_x(1); set_x(2); set_x(3)'));
  await Future<void>.delayed(const Duration(milliseconds: 50));
  expect(ext.timeline.value, isNotEmpty);

  await ext.reset();
  expect(ext.timeline.value, isEmpty);
  expect(ext.paused.value, isFalse);

  await ext.run('set_x(99)');
  expect(ext.timeline.value, hasLength(1));
  expect(ext.timeline.value.first.args['n'], 99);
});
```

The "test extension set" provides a tiny `set_x(int)` host function
that writes to a signal, so the tests don't depend on map/http
reachability.

---

## Risks / open questions

### Does `MontyInterceptor` support arbitrary delay?

Yes. `_invoke` in `dart_monty/lib/src/host/dispatch.dart:47` is just
`return interceptor(name, args, () => fn.handler!(args, ctx));` — the
returned `Future<Object?>` is awaited by the dispatch. As long as we
eventually call `next()` and return its result, the bridge waits.

There is one wrinkle: `dispatchToolCallAsFuture`
(dispatch.dart:373) is the futures-capable path used in some
backends. It calls `_invoke` *inside a try/catch for synchronous
throws*, then enqueues the returned future for resolution at the
next `MontyResolveFutures` step. Long pauses there may delay the
Python interpreter's own scheduling. Current `MontyRuntime`
constructor (runtime.dart:69) builds `PlatformBridge` with
`useFutures: false` for shared mode, so we land on `dispatchToolCall`
(the sync path) — fine for v0. Document that switching to the
futures path will need re-validation.

### Does the per-script-run lifecycle conflict with per-dialog terminal?

No. The debugger panel is mounted **inside** the RoomScreen; the
terminal is a `showDialog` popover. They have independent runtimes.
The only shared piece is `mapExtension` (a true singleton) — both
runtimes' `MapMontyExtension` wrappers point at it, so calls from
either drive the same widget. This is already the established pattern
(`lib/src/monty_singleton.dart`).

### Long-running tool calls and stepping UX

A `map_fly_to(duration_ms=5000)` step looks like: user hits step ->
arrow snaps to that line -> animation plays -> 5s later the call
appears as completed and execution pauses at the next call. Document
this in the panel UI (a small footer note) so users know the pause
is **between** calls, not within them.

### Source-line highlighting accuracy

v0a (regex match on function name) is wrong if the same name appears
multiple times. Acceptable for demo; tracked.

### Cancellation safety

`reset` -> `handle.cancel()` is cooperative. If the runtime's current
host handler is uninterruptible (e.g. an animation using
`Future.delayed`), cancel will fall through but the
`BridgeFunctionCallResult` will eventually arrive. Our interceptor
needs to be tolerant of late results landing on the *previous*
runtime — guard the timeline replace by `_runtimeGeneration` (a
counter we bump on every reset) and drop late events.

### Memory: timeline growth

A long-running script can produce thousands of timeline entries.
Cap to last 1000 in v0 (configurable). Older entries get dropped from
the widget but the run is unaffected.

---

## Future (v1)

- **Statement-level stepping**. Requires a debug-step protocol exposed
  by `dart_monty_core`'s Rust REPL — bytecode-level breakpoint hook
  that suspends after each statement and emits a
  `BridgeStatementBoundary{file, line}` event. Tracked separately;
  expect a few hundred lines of Rust + dart_monty bridge plumbing.
- **Watch expressions**. `runtime.execute(expr)` between user-paused
  states with sandbox-mode guard so they don't leak state.
- **Time-travel**. Persist the timeline + state snapshots so the user
  can scrub back to call N and see the state pane as it was. Cheap
  for state pane (just remember the JSON), expensive for the actual
  REPL heap (would need WASM snapshots — non-trivial).
- **Container-driven mount**. Once the registry lands (see below),
  the debugger is just another `Container` kind. The LLM can spawn
  a debugger inline by emitting:

  ````markdown
  ```container
  {"id": "debug-1", "kind": "debugger"}
  ```
  ````

  ...and the panel renders inline in the chat, attached to whichever
  runtime drove the script.

---

## Step 2 — Container registry refactor

This plan is "Step 1". Step 2 is the
`docs/plans/message-containers.md` refactor, lightly re-stated here
in light of the debugger as a **third** concrete container kind.

With three kinds in hand —

| Kind        | State                       | Controller  | Lifetime           |
|-------------|-----------------------------|-------------|--------------------|
| `map`       | viewport, markers, polylines| MapController| singleton          |
| `terminal`  | history list, runtime       | none        | per-dialog         |
| `debugger`  | timeline, source, runtime   | none        | per-room (today)   |

— the registry shape called for in `message-containers.md` becomes
concrete:

```dart
abstract class Container {
  String get id;                             // stable handle
  String get kind;                           // 'map' | 'terminal' | 'debugger' | ...
  ReadonlySignal<Map<String, Object?>> get state;
  void dispose();
}

class ContainerRegistry {
  Container? get(String id);
  void register(Container c);
  void discard(String id);
  List<Container> list();   // for the `list_containers` tool
}
```

`MapContainer`, `TerminalContainer`, and `DebuggerContainer` are the
three first implementations. `MapExtension`,
`MontyRuntimeExtension`/`TerminalPanel`, and the new
`MontyDebuggerExtension` each become "the SessionExtension wrapper for
container kind X" — exposing ClientTools and Monty externals that
*reach into the registry to find the container by id*.

The fence dispatch in `code_block_builder.dart` learns one new branch:

```dart
if (language == 'container') {
  final spec = jsonDecode(code) as Map<String, Object?>;
  return ContainerView(id: spec['id'], kind: spec['kind']);
}
```

`ContainerView` looks up the kind in a kind-registry and delegates to
the right widget (`MapView`, `TerminalPanel`, `DebuggerPanel`).

Don't try to fully spec the registry now — the message-containers plan
already covers the shape. The point of this Step 2 stub is: **with
three kinds, the abstraction is testable**. Two kinds is too few to
generalise.

---

## Done when

- [ ] `MontyDebuggerExtension` exists in
      `lib/src/modules/room/monty_debugger_extension.dart` and passes
      its three integration tests.
- [ ] `DebuggerPanel` and `SourceView` widgets exist and render the
      three-pane layout under `MaterialApp` test harness.
- [ ] `room_screen.dart` exposes a debugger toggle button (gated by
      `_kMontyEnabled`) and mounts the panel parallel to the map
      drawer.
- [ ] Pasting `for c in ['Tokyo', 'Sydney']: map_geocode(c);
      map_add_marker(...)` in the panel:
   - Shows two timeline entries with arguments and durations.
   - Highlights the active line in the source view as each call
     starts.
   - Updates the state pane's `map.markerCount` after each marker.
- [ ] Hitting **pause** mid-run halts execution at the next host
      call; **step** advances one call; **continue** runs to
      completion; **reset** wipes timeline and lets the next run
      start clean.
- [ ] `flutter analyze` is zero-warning, `mcp__dart__dart_format` is
      clean, and `markdownlint-cli2` passes on this plan.

---

## Critical files for implementation

- `/Users/runyaga/dev/soliplex-frontend-merged/lib/src/modules/room/ui/room_screen.dart`
- `/Users/runyaga/dev/soliplex-frontend-merged/lib/src/monty_singleton.dart`
- `/Users/runyaga/dev/soliplex-frontend-merged/packages/soliplex_agent_monty/lib/src/monty_runtime_extension.dart`
- `/Users/runyaga/dev/soliplex-frontend-merged/lib/src/modules/room/ui/terminal_panel.dart`
- `/Users/runyaga/dev/dart_monty/lib/src/host/dispatch.dart`
  (for the `MontyInterceptor` typedef + `_invoke` semantics)
