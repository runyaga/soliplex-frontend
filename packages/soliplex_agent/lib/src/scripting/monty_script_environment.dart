import 'dart:async';
import 'dart:convert';

import 'package:dart_monty/dart_monty.dart';
import 'package:soliplex_agent/src/scripting/script_environment.dart';
import 'package:soliplex_agent/src/tools/tool_registry.dart';

/// [ScriptEnvironment] backed by the Monty sandboxed Python interpreter.
///
/// Creates a [Monty] instance per session and exposes an `execute_python`
/// tool that runs Python code in the sandbox with configurable resource
/// limits. The interpreter supports iterative execution with external
/// functions, enabling host-provided data to flow into Python code.
///
/// ```dart
/// final env = await MontyScriptEnvironment.create();
/// // env.tools contains a single `execute_python` ClientTool
/// ```
class MontyScriptEnvironment implements ScriptEnvironment {
  MontyScriptEnvironment._(this._monty, this._limits);

  final Monty _monty;
  final MontyLimits? _limits;

  /// Creates a new scripting environment with a fresh Monty interpreter.
  ///
  /// [limits] applies to every `execute_python` invocation within this
  /// session. Defaults to 5 seconds / 64 MB / 100 stack depth.
  static Future<MontyScriptEnvironment> create({
    MontyLimits? limits = const MontyLimits(
      timeoutMs: 5000,
      memoryBytes: 64 * 1024 * 1024,
      stackDepth: 100,
    ),
  }) async {
    final Monty monty;
    try {
      monty = Monty();
    } on Object catch (e) {
      throw StateError(
        'MontyScriptEnvironment: failed to initialize Monty interpreter. '
        'On native platforms, ensure the Rust toolchain is installed. '
        'On web, the WASM glue (monty_glue.js + worker) must be bundled '
        'into the Flutter web build — this is not yet supported. '
        'Original error: $e',
      );
    }
    return MontyScriptEnvironment._(monty, limits);
  }

  @override
  List<ClientTool> get tools => [_executePythonTool];

  ClientTool get _executePythonTool => ClientTool.simple(
        name: 'execute_python',
        description:
            'Execute Python code in a sandboxed interpreter. '
            'Returns the result value or error. '
            'Available stdlib modules: math, re, json, datetime. '
            'No filesystem, network, or subprocess access.',
        parameters: const {
          'type': 'object',
          'properties': {
            'code': {
              'type': 'string',
              'description': 'Python source code to execute.',
            },
          },
          'required': ['code'],
        },
        executor: (toolCall, context) async {
          final args = jsonDecode(toolCall.arguments) as Map<String, dynamic>;
          final code = args['code'] as String?;
          if (code == null || code.isEmpty) {
            return jsonEncode({'error': 'Missing required parameter: code'});
          }
          try {
            final result = await _monty.run(
              code,
              limits: _limits,
              scriptName: 'agent_tool',
            );
            return jsonEncode({
              'value': result.value,
              if (result.printOutput != null && result.printOutput!.isNotEmpty)
                'print_output': result.printOutput,
              'usage': {
                'time_ms': result.usage.timeElapsedMs,
                'memory_bytes': result.usage.memoryBytesUsed,
              },
            });
          } on MontyException catch (e) {
            return jsonEncode({
              'error': e.message,
              if (e.lineNumber != null) 'line': e.lineNumber,
            });
          }
        },
      );

  @override
  void dispose() {
    unawaited(_monty.dispose());
  }
}
