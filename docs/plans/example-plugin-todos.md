# Example plugin — `soliplex_agent_todos`

A complete working example of a soliplex plugin built on the
reactive-bus architecture (`reactive-bus-redesign.md`). Demonstrates
every architectural pattern in one ~300-LOC plugin.

This doc is **didactic** — it shows what code authors actually write
when building a new plugin, with comments on *why* each piece exists.
It is **not** intended to ship as a real plugin; it's the canonical
reference for "how do I write a plugin?"

## What it does

A simple shared todo list. Operations:

- Add a todo (LLM tool, Python host function).
- Complete a todo (toggle `done`).
- Remove a todo.
- User can click a checkbox in the panel to mark done (write-back via SurfaceEvent).

The list persists across session boundaries within a thread. Multiple
panels in the UI watch the same state and re-render reactively.
Multiple derived views (count of open todos, completed-only filter)
are projections of the same bus state.

## Scenario summary by phase

| Phase | What works |
| --- | --- |
| Phase 1 | LLM can `add_todo`, `complete_todo`, `remove_todo` via tools. UI reads bus state via projections. User can click checkbox to toggle, emitting a `SurfaceEvent` the agent picks up. |
| Phase 2 | Python can do the same three operations via `monty.todos.add(...)` etc. Python can `monty.get('/ui/todos')` to inspect, `monty.wait_for(...)` to block on a state condition, `monty.subscribe(...)` for reactive notification. |

## Package structure

```text
packages/soliplex_agent_todos/
  pubspec.yaml
  lib/
    soliplex_agent_todos.dart      # public exports
    src/
      todo.dart                    # the Todo data class
      todo_plugin.dart             # SessionExtension declaring tools (and hostFunctions in Phase 2)
      todo_list_controller.dart    # read-only render target (Surface)
      todo_projections.dart        # 3 projections off the bus
      todo_panel.dart              # the Flutter widget
  test/
    todo_plugin_test.dart          # unit tests for the plugin
    todo_persistence_test.dart     # persistence across session boundaries
```

The package depends on:

- `soliplex_client` — for `Surface`, `StateProjection`, `StateBus`, `JsonPatchOp`, `SurfaceEvent`.
- `soliplex_agent` — for `SessionExtension`, `SessionContext`, `ClientTool`, (Phase 2) `HostFunction`.
- `signals_flutter` — for the widget's `.watch(context)`.

It does **not** depend on `lib/`, on any other plugin package, or on
`dart_monty`. Layer 2 enforcement.

## Bus state shape

```json
{
  "ui": {
    "todos": [
      {"id": "uuid-1", "title": "Buy milk", "done": false},
      {"id": "uuid-2", "title": "Walk the dog", "done": true}
    ]
  }
}
```

Path: `/ui/todos`. Stored as a JSON list because that's the
implementation choice for the bus (see "Implementation detail: JSON
internals" in the redesign plan).

## The data class — `todo.dart`

```dart
import 'package:meta/meta.dart';

@immutable
class Todo {
  const Todo({required this.id, required this.title, required this.done});

  final String id;
  final String title;
  final bool done;

  // JSON round-trip for the bus / projection layer.
  factory Todo.fromJson(Map<String, dynamic> j) => Todo(
        id: j['id'] as String,
        title: j['title'] as String,
        done: j['done'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'done': done};

  Todo copyWith({String? title, bool? done}) =>
      Todo(id: id, title: title ?? this.title, done: done ?? this.done);
}
```

Pure value type. The bus stores its `toJson()` form; projections
deserialize back to typed `Todo`.

## The plugin — `todo_plugin.dart` (Phase 1)

```dart
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:uuid/uuid.dart';

import 'todo.dart';

/// The soliplex-side authoring surface. Declares LLM tools (and, in
/// Phase 2, host functions) that mutate the bus.
class TodoPlugin extends SessionExtension {
  TodoPlugin();

  // Library-private path constants. Phantom-typed so the value type
  // is checked at the write site (see bus-path-safety.md §2.4).
  static const _todos = JsonPath<List<Todo>>('/ui/todos');
  static const _todosAppend = JsonPath<Todo>('/ui/todos/-');

  @override
  String get namespace => 'todos';

  @override
  List<ClientTool> get tools => [
        ClientTool.simple(
          name: 'add_todo',
          description: 'Add a todo item.',
          executor: (args, ctx) => _addTodo(args['title'] as String, ctx),
        ),
        ClientTool.simple(
          name: 'complete_todo',
          description: 'Mark a todo as done.',
          executor: (args, ctx) =>
              _completeTodo(args['id'] as String, ctx),
        ),
        ClientTool.simple(
          name: 'remove_todo',
          description: 'Remove a todo by id.',
          executor: (args, ctx) =>
              _removeTodo(args['id'] as String, ctx),
        ),
      ];

  // Phase 2 will add: List<HostFunction> get hostFunctions => [...];
  // For Phase 1 the inherited `const []` default is fine.

  // ---- Typed write methods (one place where path strings live) ------------

  Future<Object?> _addTodo(String title, SessionContext ctx) async {
    final todo = Todo(id: const Uuid().v4(), title: title, done: false);
    ctx.bus.applyDelta([JsonPatchOp.add(_todosAppend, todo.toJson())]);
    return {'id': todo.id};
  }

  Future<Object?> _completeTodo(String id, SessionContext ctx) async {
    final todos = TodoListProjection().compute(ctx.bus.agentState.value);
    final idx = todos.indexWhere((t) => t.id == id);
    if (idx < 0) return {'error': 'unknown id: $id'};
    ctx.bus.applyDelta([
      JsonPatchOp.replace(
        '/ui/todos/$idx/done',
        true,
      ),
    ]);
    return {'ok': true};
  }

  Future<Object?> _removeTodo(String id, SessionContext ctx) async {
    final todos = TodoListProjection().compute(ctx.bus.agentState.value);
    final idx = todos.indexWhere((t) => t.id == id);
    if (idx < 0) return {'error': 'unknown id: $id'};
    ctx.bus.applyDelta([JsonPatchOp.remove('/ui/todos/$idx')]);
    return {'ok': true};
  }
}
```

Things to notice:

- **`SessionExtension` declares tools.** Each tool's executor receives a `SessionContext` exposing `ctx.bus`. No singleton imports.
- **All writes go through `bus.applyDelta(...)`.** There's no `todoListController.add(...)` mutator anywhere.
- **Path strings live exactly once**, in the `_todos` / `_todosAppend` constants at the top of the plugin file. Phantom-typed `JsonPath<T>` (per `bus-path-safety.md`) catches leaf-type mismatches at the write site.
- **The plugin is the only file that knows the path shape.** Downstream code (UI, tests, other plugins) never types `/ui/todos`.

## The render target — `todo_list_controller.dart`

```dart
import 'package:signals_core/signals_core.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'todo.dart';

/// App-singleton render target. Read-only public surface; only the
/// projection forwards into the internal signal.
class TodoListController implements Surface<List<Todo>> {
  TodoListController._(this._bus);

  static late final TodoListController instance;

  static void initialize(StateBus bus) {
    instance = TodoListController._(bus);
  }

  final StateBus _bus;
  final _todos = signal<List<Todo>>(const []);

  // Public read API.
  @override
  String get id => 'todo_list';

  @override
  ReadonlySignal<List<Todo>> get state => _todos.readonly();

  // Library-private write API. Only `TodoListProjection` (in the same
  // package) calls this. Outside callers cannot reach it.
  void _forwardFromProjection(List<Todo> next) {
    if (!_listEquals(_todos.value, next)) {
      _todos.value = next;
    }
  }

  // SurfaceEvent write-back path. The widget calls this when the user
  // toggles a checkbox; the event flows through the bus → forwarded to
  // the agent.
  @override
  Future<void> emit(SurfaceEvent event) => _bus.emit(event);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

Key invariants:

- **No public mutator.** `addTodo`/`removeTodo` etc. don't exist on this class. Compile error if you try to call them.
- **`_forwardFromProjection` is library-private.** Only `TodoListProjection` in the same library can write into the signal.
- **Stable signal.** `_todos` is created once, never replaced. Widgets bind to it for their lifetime; thread switches change *the value*, not *the signal*. (Lesson #11 from `genui-build-lessons.md`.)
- **`emit` forwards SurfaceEvents to the bus.** The widget uses this for write-back; the bus then forwards to the agent.

## The projections — `todo_projections.dart`

```dart
import 'package:soliplex_client/soliplex_client.dart';

import 'todo.dart';
import 'todo_list_controller.dart';

/// Reads `/ui/todos` from bus state, deserializes back to `List<Todo>`.
/// Forwards into `TodoListController._todos` (the same library has
/// access to the library-private `_forwardFromProjection`).
class TodoListProjection extends StateProjection<List<Todo>> {
  @override
  List<Todo> compute(Map<String, dynamic> agentState) {
    final raw = agentState['ui']?['todos'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Todo.fromJson)
        .toList(growable: false);
  }

  // The wiring side — called once when the plugin attaches.
  void wireTo(TodoListController controller, StateBus bus) {
    bus.project(this).subscribe((todos) {
      controller._forwardFromProjection(todos);
    });
  }
}

/// Count of incomplete todos. Same bus state, different derived view.
class OpenTodoCountProjection extends StateProjection<int> {
  @override
  int compute(Map<String, dynamic> agentState) =>
      TodoListProjection().compute(agentState).where((t) => !t.done).length;
}

/// Filtered: completed only. Same bus state, different derived view.
class CompletedTodosProjection extends StateProjection<List<Todo>> {
  @override
  List<Todo> compute(Map<String, dynamic> agentState) =>
      TodoListProjection().compute(agentState).where((t) => t.done).toList();
}
```

What this demonstrates:

- **One bus state → many projections.** `TodoListProjection`, `OpenTodoCountProjection`, `CompletedTodosProjection` all read from the same `agentState['ui']['todos']` and produce different typed outputs. Subscribers can use whichever projection fits their need.
- **Type safety recovered at the read boundary.** The bus stores JSON; the projection layer returns `List<Todo>` / `int`. Consumers never see `Map<String, dynamic>`.
- **Defensive deserialization.** `if (raw is! List) return const [];` — typos in the path or schema drift produce empty lists, not crashes.
- **`wireTo` does the forwarding.** Called when the plugin attaches; subscribes to the bus projection and writes the result into the controller. The closure has access to library-private `_forwardFromProjection`.

## The widget — `todo_panel.dart`

```dart
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'todo.dart';
import 'todo_list_controller.dart';

class TodoPanel extends StatelessWidget {
  const TodoPanel({super.key});

  @override
  Widget build(BuildContext context) {
    // Bound to the stable signal. Switches between threads change the
    // value, not the signal itself; this Watch keeps working.
    final todos = TodoListController.instance.state.watch(context);

    if (todos.isEmpty) {
      return const Center(child: Text('No todos yet.'));
    }

    return ListView.builder(
      itemCount: todos.length,
      itemBuilder: (_, i) {
        final todo = todos[i];
        return CheckboxListTile(
          title: Text(todo.title),
          value: todo.done,
          onChanged: (newValue) {
            // Write-back via SurfaceEvent. Does NOT call a controller
            // mutator (which doesn't exist anyway). The bus + agent
            // round-trips and the next state delta updates the signal.
            TodoListController.instance.emit(
              SurfaceEvent(
                surfaceId: 'todo_list',
                type: 'todo.toggle',
                data: {'id': todo.id, 'done': newValue ?? false},
              ),
            );
          },
        );
      },
    );
  }
}
```

What this demonstrates:

- **Reads via `.watch(context)`.** Standard signals_flutter idiom. The widget rebuilds on every state change.
- **Writes via `emit(SurfaceEvent)`.** No imperative mutator on the controller. The user's checkbox click becomes a `SurfaceEvent`; the bus forwards it; the agent (or a server-side handler) sees it and emits a `StateDeltaEvent` updating the bus; the widget rebuilds with the new value.
- **The widget knows nothing about paths.** It interacts with `TodoListController` and `SurfaceEvent`, which are typed. No `Map<String, dynamic>` and no JSON Patch operations leak through.

## How a plugin is wired up — `soliplex_agent_todos.dart`

```dart
library soliplex_agent_todos;

export 'src/todo.dart' show Todo;
export 'src/todo_panel.dart' show TodoPanel;
export 'src/todo_plugin.dart' show TodoPlugin;
export 'src/todo_projections.dart'
    show OpenTodoCountProjection, CompletedTodosProjection;

// Note: TodoListController is NOT exported. Consumers reach the read
// signal through `TodoPanel` (the widget) or through projections.
// _forwardFromProjection is library-private and unreachable.
```

The library export list is part of the architectural enforcement.
**`TodoListController` is private to the package** — consumers can't
even mention its name from outside. The widget and the projections are
the only public surface.

## What "all features" means — checklist

| Feature | Where it appears in this example |
| --- | --- |
| Plugin lives in its own package | `packages/soliplex_agent_todos/` |
| Plugin extends `SessionExtension` | `todo_plugin.dart` |
| Tools declared on the plugin | `TodoPlugin.tools` |
| Tool executors write the bus, not singletons | `_addTodo` / `_completeTodo` / `_removeTodo` |
| Path strings live in one place per plugin | `_todos` / `_todosAppend` constants |
| Phantom-typed `JsonPath<T>` for write-site type safety | constants are `JsonPath<Todo>` etc. |
| `SessionContext` exposes `bus` to handlers | `ctx.bus.applyDelta(...)` |
| Render target is read-only public | `TodoListController.state` is `ReadonlySignal`; no public mutator |
| Render target uses stable signal forwarded into | `_todos = signal([...])` constructed once; `_forwardFromProjection` writes to it |
| Multiple projections off one bus path | `TodoListProjection`, `OpenTodoCountProjection`, `CompletedTodosProjection` |
| Type safety recovered at read boundary | projections return `List<Todo>` / `int`, not `dynamic` |
| Defensive deserialization | `if (raw is! List) return const [];` |
| Per-thread persistence | bus is per-thread; switching threads and back finds the same todos |
| Per-session persistence | new session on same thread reads existing todos via `cachedHistory.aguiState` |
| SurfaceEvent write-back from widget | checkbox `onChanged` calls `controller.emit(SurfaceEvent(...))` |
| Layer 1 enforcement (visibility) | `_forwardFromProjection` is library-private |
| Layer 2 enforcement (package boundaries) | controller not exported; package depends only on `soliplex_client` and `soliplex_agent` |

## Phase 2 additions

When `hostFunctions` lands in Phase 2 step 8, `TodoPlugin` gains:

```dart
@override
List<HostFunction> get hostFunctions => [
      HostFunction(
        name: 'todos.add',
        handler: (args, ctx) => _addTodo(args['title'] as String, ctx),
      ),
      HostFunction(
        name: 'todos.complete',
        handler: (args, ctx) => _completeTodo(args['id'] as String, ctx),
      ),
      HostFunction(
        name: 'todos.remove',
        handler: (args, ctx) => _removeTodo(args['id'] as String, ctx),
      ),
    ];
```

The handler implementations are **the same `_addTodo` / `_completeTodo`
/ `_removeTodo` methods.** One implementation, two adapters (LLM tool
and Python host function). The bridge layer (`MontyHostPlugin`,
Phase 2 step 9) synthesizes the dart_monty `MontyExtension` from this
declaration; nothing else changes.

### Python usage examples

After Phase 2 ships, this Python script runs on the agent:

```python
# Read current state
todos = monty.get('/ui/todos')
print(f'{len(todos)} todos, {sum(1 for t in todos if t["done"])} done')

# Add a few
monty.todos.add(title='Buy groceries')
monty.todos.add(title='Call mom')
monty.todos.add(title='Walk the dog')

# Wait for the user to mark the first one done (they tap the checkbox in the UI)
monty.wait_for('/ui/todos/0/done', equals=True)
print('First one done!')

# React to every state change
def on_change(todos):
    open_count = sum(1 for t in todos if not t['done'])
    print(f'Now {open_count} open todos')

monty.subscribe('/ui/todos', on_change, throttle_ms=100)

# Bulk complete by id
ids = [t['id'] for t in monty.get('/ui/todos')]
for tid in ids:
    monty.todos.complete(id=tid)
```

This demonstrates the three Phase 2 bridge primitives:

- **`monty.get(path)`** — snapshot read. Returns a deserialized JSON value.
- **`monty.wait_for(path, equals=...)`** — Python suspends until the bus value matches.
- **`monty.subscribe(path, callback, throttle_ms=...)`** — register a callback fired (throttled) on every state change.

Plus the **`monty.todos.*`** namespace, which is the plugin's host
functions exposed to Python with no extra wiring. The plugin author
wrote the function once (in Dart, as `_addTodo`); both the LLM and
Python see it via separate adapters.

## What this example does NOT demonstrate

Honestly listed:

- **Steps → bus** (Phase 1 step 6). The redesign moves `ExecutionTracker` to the bus, but todos don't have a step-log analog. See `ExecutionStepsPlugin` (after Phase 1 step 6) for that pattern.
- **Reactive cross-thread state** (server scope bus). The redesign defers this to a follow-on; `appBus` / `serverBus` aren't built in v1.
- **Cross-browser-reload persistence** for client-only state. Bus state survives in-browser session boundaries; cross-browser-reload survival depends on whether the server emits the path. Todos *do* survive cross-reload because we'd want the agent to round-trip them via `aguiState` — but that's a server-side decision, not the plugin's.
- **JS bidirectional bindings.** Future. CodeMirror-as-plugin would slot into the same shape with one additional adapter on top of the bridge layer.
- **Resolving conflicts when two writers land at once.** v1 uses last-writer-wins on the bus. The todo plugin doesn't have a conflict scenario; for cases that do (e.g. concurrent edits to the same field), the open follow-on "Bus schema validation at applyDelta boundary" plus per-plugin merge logic would handle it.

## Tests this example ships with

```dart
// test/todo_plugin_test.dart
test('add_todo writes to bus', () async {
  final bus = StateBus();
  final ctx = FakeSessionContext(bus: bus);
  final plugin = TodoPlugin();
  await plugin.attach(ctx);

  await plugin.tools.firstWhere((t) => t.name == 'add_todo')
      .executor({'title': 'Buy milk'}, ctx);

  final todos = TodoListProjection().compute(bus.agentState.value);
  expect(todos.length, 1);
  expect(todos.first.title, 'Buy milk');
  expect(todos.first.done, isFalse);
});

test('complete_todo flips done flag', () async { /* ... */ });

test('SurfaceEvent on checkbox toggle reaches the bus', () async {
  // Constructs a TodoPanel, taps the checkbox, asserts a
  // SurfaceEvent('todo.toggle', ...) was emitted on the bus events stream.
});

// test/todo_persistence_test.dart
test('todos persist across session boundaries', () async {
  final runtime = AgentRuntime(...);
  final session1 = await runtime.spawn(roomId: 'demo', threadId: 't1', prompt: '');
  // Add some todos via session1's plugin
  await session1.dispose();
  
  final session2 = await runtime.spawn(roomId: 'demo', threadId: 't1', prompt: '');
  final todos = TodoListProjection().compute(session2.runtime.threadState(...).bus.agentState.value);
  expect(todos.length, 3);  // The three from session1
});
```

The persistence test is the architecturally interesting one — it
demonstrates that the per-thread `ThreadState(bus, conversation)`
pattern from Phase 1 step 3 actually works end-to-end through a real
plugin.

## How to use this doc

For plugin authors:

1. Read `reactive-bus-redesign.md` for the architectural framing.
2. Read this doc for the worked example.
3. Copy `packages/soliplex_agent_todos/` as a starter, replace
   `Todo` / `TodoPlugin` with your domain, ship.

For reviewers of the redesign PRs:

- Use this doc as the spec for what `MapPlugin` and `NarrationPlugin`
  should look like after Phase 1 conversion. If a converted plugin
  looks structurally different from `TodoPlugin`, ask why.
- Phase 2 step 10 (plugin migration) should produce the
  Phase-2-additions shape above — `tools` and `hostFunctions` over the
  same handler methods.
