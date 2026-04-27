import 'dart:async';
import 'dart:convert';

import 'package:dart_monty/dart_monty.dart' show MontyRuntime;
import 'package:dart_monty/dart_monty_bridge.dart'
    show ExtensionCoordinator, MontyExtension;
import 'package:soliplex_agent/soliplex_agent.dart';
// ToolExecutionContext is not re-exported from soliplex_agent's public
import 'package:soliplex_agent_monty/src/monty_extension_set.dart';
import 'package:soliplex_agent_monty/src/monty_host_plugin.dart';

/// Bridges a [MontyRuntime] into a soliplex [AgentSession].
///
/// Lifecycle:
/// - [onAttach] constructs the runtime with [MontyExtensionSet]'s
///   extensions, then subscribes to the inner
///   [ExtensionCoordinator.statefulObservations] and fans each
///   `(namespace, signal)` into the outer [state] map.
/// - [tools] exposes one [ClientTool] — `run_python_on_device` — that
///   runs arbitrary Python code via `runtime.execute(code)` and
///   returns `{value, output, error}` as a JSON string.
/// - [onDispose] cancels all subscriptions and disposes the runtime.
///
/// The [Signal] owned here is NOT the runtime's signal; it's an
/// aggregated map of every inner extension's current state, so the
/// debug panel / other consumers can observe everything through one
/// signal.
class MontyRuntimeExtension extends SessionExtension
    with StatefulSessionExtension<Map<String, Object?>> {
  MontyRuntimeExtension({required MontyExtensionSet extensions})
      : _extensions = extensions {
    setInitialState(const <String, Object?>{});
  }

  final MontyExtensionSet _extensions;
  MontyRuntime? _runtime;
  final List<void Function()> _unsubs = [];

  @override
  String get namespace => 'monty';

  @override
  String get sourcePath =>
      'packages/soliplex_agent_monty/lib/src/monty_runtime_extension.dart';

  @override
  int get priority => 0;

  @override
  List<ClientTool> get tools => [
        ClientTool.simple(
          name: 'run_python_on_device',
          description: "Runs Python on the user's device inside an embedded "
              'dart_monty interpreter. Use for quick computations, small '
              'transformations, or logic the user asked to run locally '
              '(privacy, offline, no upload). Return values and print() '
              'output are both captured.\n\n'
              'Available externals depend on the host build. The '
              'standard set includes (call WITHOUT a `monty.` prefix):\n'
              '  http_get(url, headers?) -> str  (response body)\n'
              '  http_get_json(url, headers?) -> Any  (parsed JSON)\n'
              '  map_fly_to(lat, lng, zoom?, rotation?, animated?, '
              'duration_ms?)\n'
              '  map_add_marker(lat, lng, label?, color?, icon?, '
              'pulse?) -> str\n'
              '  map_clear_markers()\n'
              '  map_set_basemap(style)\n'
              '  map_get_view() -> {lat, lng, zoom, rotation}\n'
              '  map_sleep_ms(ms)\n\n'
              'No filesystem, no subprocess, no `import requests` / '
              '`import time`. Use `http_get_json` for JSON APIs and '
              '`map_sleep_ms` for delays. HTTP is browser-CORS-bound: '
              'only public APIs that send permissive '
              'Access-Control-Allow-Origin headers will succeed.',
          parameters: const {
            'type': 'object',
            'properties': {
              'code': {
                'type': 'string',
                'description': 'Python source to execute.',
              },
            },
            'required': ['code'],
          },
          executor: _runPythonOnDevice,
        ),
      ];

  @override
  Future<void> onAttach(AgentSession session) async {
    // Legacy attach path (no SessionContext). The redesign wires
    // host-function bridging through `onAttachWithContext`; this
    // method is kept for backwards compatibility with extensions
    // that still reach for the session-only signature.
    await _attachInternal(session, hostBridged: const <MontyExtension>[]);
  }

  @override
  Future<void> onAttachWithContext(SessionContext ctx) async {
    // Walk the session's other extensions, gather any
    // soliplex-side `hostFunctions`, and synthesize one
    // `MontyExtension` per sibling. The translation is a 1:1 type
    // rename (see monty_host_plugin.dart). Plugin authors never
    // see dart_monty types — they declare `HostFunction` from
    // soliplex_agent and the bridge does the rest.
    //
    // Plan reference: `docs/plans/reactive-bus-redesign.md` (Phase 2 step 9).
    final synthesized = synthesizeMontyHostExtensions(
      session: ctx.session,
      ctx: ctx,
      skipSelf: this,
    );
    await _attachInternal(ctx.session, hostBridged: synthesized);
  }

  Future<void> _attachInternal(
    AgentSession session, {
    required List<MontyExtension> hostBridged,
  }) async {
    final runtime = MontyRuntime(
      extensions: [..._extensions.all, ...hostBridged],
    );
    _runtime = runtime;

    // Fan each (namespace, signal) pair from the inner coordinator into
    // our aggregated state map. `coordinator` is null in sandbox mode —
    // we don't use sandbox mode here, but guard anyway.
    final coordinator = runtime.coordinator;
    if (coordinator != null) {
      for (final (ns, signal) in coordinator.statefulObservations()) {
        final unsub = signal.subscribe((value) {
          state = {...state, ns: value};
        });
        _unsubs.add(unsub);
      }
    }
  }

  @override
  void onDispose() {
    for (final u in _unsubs) {
      u();
    }
    _unsubs.clear();
    unawaited(_runtime?.dispose());
    _runtime = null;
  }

  /// Runs Python code directly on the attached runtime, bypassing the LLM
  /// tool path. Use this from UI surfaces (e.g. a terminal panel) where the
  /// user pastes code and wants raw output.
  ///
  /// Returns the same `{value, output, error}` shape the
  /// `run_python_on_device` tool emits (as a Dart map this time, not JSON).
  /// Throws [StateError] if no session is currently attached.
  Future<({Object? value, String output, Object? error})> executeUser(
    String code,
  ) async {
    final runtime = _runtime;
    if (runtime == null) {
      throw StateError('MontyRuntimeExtension is not attached to a session');
    }
    final handle = runtime.execute(code);
    final result = await handle.result;
    return (
      value: result.value.toJson(),
      output: result.printOutput ?? '',
      error: result.error?.toJson(),
    );
  }

  /// Executor for `run_python_on_device`. Always returns a JSON string.
  /// Python-level errors are returned in the payload — not thrown — so
  /// the LLM sees a completed tool call with an `error` field rather
  /// than retrying on `status: failed`.
  Future<String> _runPythonOnDevice(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    final String code;
    try {
      final args = toolCall.arguments.isEmpty
          ? const <String, Object?>{}
          : jsonDecode(toolCall.arguments) as Map<String, Object?>;
      final raw = args['code'];
      if (raw is! String) {
        return jsonEncode({
          'error': 'run_python_on_device: "code" argument must be a string',
        });
      }
      code = raw;
    } on Object catch (e) {
      return jsonEncode({
        'error': 'run_python_on_device: failed to parse arguments: $e',
      });
    }

    final runtime = _runtime;
    if (runtime == null) {
      return jsonEncode({
        'error': 'MontyRuntimeExtension is not attached to a session',
      });
    }

    try {
      final handle = runtime.execute(code);
      final result = await handle.result;
      return jsonEncode({
        'value': result.value.toJson(),
        'output': result.printOutput ?? '',
        if (result.error != null) 'error': result.error!.toJson(),
      });
    } on Object catch (e) {
      return jsonEncode({'error': 'run_python_on_device: $e'});
    }
  }
}
