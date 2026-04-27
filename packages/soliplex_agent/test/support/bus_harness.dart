/// Layer-B test harness: real `StateBus` + plugin attach lifecycle,
/// no widget pump, no SSE, no HTTP, no Monty.
///
/// Plugin authors write a Layer-B test by:
///
/// ```dart
/// import 'package:flutter_test/flutter_test.dart';
/// import 'package:soliplex_agent/soliplex_agent.dart';
/// import 'package:my_plugin/my_plugin.dart';
///
/// import '../../soliplex_agent/test/support/bus_harness.dart';
///
/// void main() {
///   test('my_tool writes /ui/x', () async {
///     final harness = BusHarness();
///     try {
///       await harness.invokeHostFunction(
///         MyPlugin(),
///         name: 'my_tool',
///         args: {'arg': 1},
///       );
///       expect(harness.state['ui'], equals({'x': 1}));
///       expect(harness.writes, hasLength(1));
///       expect(harness.writes.single.tag, 'my_tool.tag');
///     } finally {
///       harness.dispose();
///     }
///   });
/// }
/// ```
///
/// Scope:
///
/// - Real `StateBus` — every write fires the `BusObserver` hook
///   ([BusHarness.writes] is the captured log).
/// - Real plugin `onAttachWithContext` lifecycle — extensions can
///   stash a `SessionContext` reference if they need one
///   (`NarrationPlugin` does this).
/// - Real `ClientTool.executor` and `HostFunction.handler` paths —
///   exercises the same code the LLM-tool and Python-bridge surfaces
///   reach at runtime.
///
/// Out of scope (use a different harness):
///
/// - Spawning a real `AgentSession` against a real `AgentRuntime` /
///   `ServerConnection`. Handlers that touch `ctx.session` or
///   `ctx.runtime` will throw [UnsupportedError]; this is a
///   deliberate surface tightening, not a stub. If your plugin needs
///   session/runtime references, fold the real-session surface into
///   a separate harness and exercise the bus through that one.
/// - Driving an AG-UI event stream into the bus. Use
///   `StateBus.setAgentState` / `applyDelta` directly to seed state.
/// - Widget rendering. Layer-C tests live in `integration_test/`.
library;

import 'dart:convert';

import 'package:soliplex_agent/soliplex_agent.dart';

/// Scaffold for testing a `SessionExtension`'s bus-write surfaces
/// against a real [StateBus] without booting an `AgentSession`.
class BusHarness {
  /// Construct a fresh harness with an optional initial state.
  BusHarness({Map<String, dynamic> initialState = const {}}) {
    _bus = StateBus(initialAgentState: initialState, observer: _writes.add);
  }

  late final StateBus _bus;
  final List<BusWriteEvent> _writes = [];

  /// Underlying bus. Tests can read `bus.agentState.value` directly
  /// or seed state via `bus.setAgentState`/`bus.update`/`bus.applyDelta`.
  StateBus get bus => _bus;

  /// Current agent-state snapshot. Shorthand for
  /// `bus.agentState.value`.
  Map<String, dynamic> get state => _bus.agentState.value;

  /// Captured write log — every committed `setAgentState` / `update`
  /// since construction. Read-only.
  List<BusWriteEvent> get writes => List.unmodifiable(_writes);

  /// Build a `SessionContext` backed by this harness's bus, with
  /// throwing `session` / `runtime` accessors. Most plugin handlers
  /// only read `ctx.bus`; if yours needs more, see the library
  /// header.
  SessionContext context() => _BusOnlyContext(_bus);

  /// Attach [plugin] using the real `onAttachWithContext` lifecycle,
  /// then invoke the named [HostFunction] handler with [args] and
  /// return its return value.
  ///
  /// Throws [ArgumentError] if no host function with [name] is
  /// declared on [plugin]. Plugin's `onDispose` is called by
  /// [dispose].
  Future<Object?> invokeHostFunction(
    SessionExtension plugin, {
    required String name,
    Map<String, Object?> args = const {},
  }) async {
    final ctx = context();
    await plugin.onAttachWithContext(ctx);
    _attached.add(plugin);
    final fn = plugin.hostFunctions.firstWhere(
      (f) => f.schema.name == name,
      orElse: () => throw ArgumentError(
        'No host function "$name" on ${plugin.runtimeType} '
        '(found: ${plugin.hostFunctions.map((f) => f.schema.name).toList()})',
      ),
    );
    return fn.handler(args, ctx);
  }

  /// Attach [plugin] using the real `onAttachWithContext` lifecycle,
  /// then invoke the named [ClientTool] executor with [args] and
  /// return its return value.
  ///
  /// Wraps [args] in a synthetic `ToolCallInfo` (JSON-encoded
  /// arguments, pending status). The `ToolExecutionContext` passed
  /// to the executor throws on every method except `cancelToken`
  /// (which returns a fresh, never-cancelled token) — most plugin
  /// executors only read `ctx.cancelToken` or ignore the parameter.
  ///
  /// Throws [ArgumentError] if no tool with [name] is declared on
  /// [plugin].
  Future<String> invokeClientTool(
    SessionExtension plugin, {
    required String name,
    Map<String, Object?> args = const {},
  }) async {
    final ctx = context();
    await plugin.onAttachWithContext(ctx);
    _attached.add(plugin);
    final tool = plugin.tools.firstWhere(
      (t) => t.definition.name == name,
      orElse: () => throw ArgumentError(
        'No client tool "$name" on ${plugin.runtimeType} '
        '(found: ${plugin.tools.map((t) => t.definition.name).toList()})',
      ),
    );
    final toolCall = ToolCallInfo(
      id: 'bus-harness-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      arguments: args.isEmpty ? '' : jsonEncode(args),
    );
    return tool.executor(toolCall, _BusOnlyExecutionContext());
  }

  final List<SessionExtension> _attached = [];
  bool _disposed = false;

  /// Dispose the underlying bus and run `onDispose` on every plugin
  /// that was attached via [invokeHostFunction] or
  /// [invokeClientTool]. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final ext in _attached.reversed) {
      ext.onDispose();
    }
    _attached.clear();
    _bus.dispose();
  }
}

class _BusOnlyContext implements SessionContext {
  _BusOnlyContext(this._bus);

  final StateBus _bus;
  final _StubSession _session = _StubSession();
  final _StubRuntime _runtime = _StubRuntime();

  @override
  StateBus get bus => _bus;

  /// Returns a sentinel stub so plugin `onAttachWithContext`
  /// implementations that forward to `onAttach(ctx.session)`
  /// compile and run. Method calls on the returned object throw —
  /// tests that need a real session need a fuller harness.
  @override
  AgentSession get session => _session;

  /// Returns a sentinel stub — same contract as [session].
  @override
  AgentRuntime get runtime => _runtime;
}

class _StubSession implements AgentSession {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
        'BusHarness session stub does not implement '
        '${invocation.memberName}. Plugins that read or call methods '
        'on `ctx.session` need a fuller harness — see '
        'bus_harness.dart.',
      );
}

class _StubRuntime implements AgentRuntime {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
        'BusHarness runtime stub does not implement '
        '${invocation.memberName}. Plugins that read or call methods '
        'on `ctx.runtime` need a fuller harness — see '
        'bus_harness.dart.',
      );
}

class _BusOnlyExecutionContext implements ToolExecutionContext {
  @override
  CancelToken get cancelToken => CancelToken();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
        'BusHarness ToolExecutionContext does not implement '
        '${invocation.memberName}. Use a fuller harness if your tool '
        'needs spawn/emit/approval/delegate.',
      );
}
