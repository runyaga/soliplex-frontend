import 'package:meta/meta.dart';
import 'package:soliplex_agent/src/runtime/session_context.dart';

/// A foreign-runtime-callable function declared by a `SessionExtension`.
///
/// Shape mirrors `dart_monty.HostFunction` exactly — same fields, same
/// names — so the translation layer in `soliplex_agent_monty`'s
/// `MontyHostPlugin` is a 1:1 type rename, not a structural conversion:
///
/// ```dart
/// // dart_monty (foreign runtime adapter, never imported here)
/// dart_monty.HostFunction(
///   schema: dart_monty.HostFunctionSchema(
///     name: 'add_marker',
///     params: [
///       dart_monty.HostParam(
///         name: 'lat',
///         type: dart_monty.HostParamType.float,
///       ),
///     ],
///   ),
///   handler: (call) async => ...,
/// );
///
/// // soliplex (this file, plugin authors write this)
/// HostFunction(
///   schema: HostFunctionSchema(
///     name: 'add_marker',
///     params: [HostParam(name: 'lat', type: HostParamType.float)],
///   ),
///   handler: (args, ctx) async => ...,
/// );
/// ```
///
/// The bridge layer (in `soliplex_agent_monty`) walks each declaration,
/// renames `soliplex.HostParam` → `dart_monty.HostParam` (and the same
/// for `HostParamType`, `HostFunctionSchema`), and adapts the handler
/// signature: dart_monty hands the handler a `call` object;
/// soliplex hands its handler the args map plus a [SessionContext]
/// for `bus` / `session` / `runtime` access.
///
/// For LLM-tool consumption, [HostFunctionSchema.toJsonSchema] produces
/// the equivalent JSON Schema fragment so the same declaration can
/// drive both Python (via the bridge) and LLM (via a `ClientTool`).
///
/// Plan reference: `docs/plans/reactive-bus-redesign.md` (Phase 2 step 8).
@immutable
class HostFunction {
  /// Constructs a host function.
  const HostFunction({required this.schema, required this.handler});

  /// Static description of the function — its name, description,
  /// and parameter list.
  final HostFunctionSchema schema;

  /// Async handler invoked when a foreign runtime calls this function.
  /// Receives the decoded argument map and the per-session
  /// [SessionContext] (which exposes `bus`, `session`, `runtime`).
  ///
  /// Return value is conveyed back to the foreign runtime — `String`
  /// for simple text, `Map`/`List` for structured returns, or `null`
  /// to signal void.
  final HostFunctionHandler handler;
}

/// Static description of a [HostFunction]: its name, description, and
/// parameter list.
///
/// Mirrors `dart_monty.HostFunctionSchema` exactly. Add
/// [toJsonSchema] for LLM-side consumption when the same handler is
/// also exposed as a `ClientTool`.
@immutable
class HostFunctionSchema {
  const HostFunctionSchema({
    required this.name,
    this.description = '',
    this.params = const [],
  });

  /// Function name. Used as the dart_monty host function name and
  /// (typically) the LLM tool name when this function is also
  /// exposed as a `ClientTool`.
  final String name;

  /// Human-readable description. Surfaced to LLM consumers; useful
  /// for Python `help(monty.foo)` style introspection too.
  final String description;

  /// Parameter declarations in declaration order.
  final List<HostParam> params;

  /// Produces the JSON Schema fragment equivalent to this schema, for
  /// LLM-tool consumption (the AG-UI wire format expects JSON Schema
  /// in `Tool.parameters`).
  Map<String, Object?> toJsonSchema() {
    final required = <String>[
      for (final p in params)
        if (p.isRequired) p.name,
    ];
    return <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        for (final p in params) p.name: p._toJsonSchemaProperty(),
      },
      if (required.isNotEmpty) 'required': required,
    };
  }
}

/// One parameter on a [HostFunctionSchema]. Mirrors
/// `dart_monty.HostParam` field-for-field.
@immutable
class HostParam {
  const HostParam({
    required this.name,
    required this.type,
    this.description = '',
    this.isRequired = true,
  });

  /// Parameter name (the key in the args map the handler receives).
  final String name;

  /// Parameter type. Mapped 1:1 to `dart_monty.HostParamType` by the
  /// bridge.
  final HostParamType type;

  /// Optional human-readable description.
  final String description;

  /// Whether this parameter must be present in the args map.
  /// Defaults to `true`.
  final bool isRequired;

  Map<String, Object?> _toJsonSchemaProperty() => <String, Object?>{
        'type': _jsonSchemaTypeName(type),
        if (description.isNotEmpty) 'description': description,
      };
}

/// Parameter primitive types, mirroring `dart_monty.HostParamType`.
enum HostParamType {
  /// Dart `String`.
  string,

  /// Dart `int`.
  integer,

  /// Dart `double` / `num`.
  float,

  /// Dart `bool`.
  boolean,

  /// Dart `List`.
  array,

  /// Dart `Map`.
  object,
}

/// Async handler signature for [HostFunction]. Receives the decoded
/// argument map and the per-session [SessionContext].
typedef HostFunctionHandler = Future<Object?> Function(
  Map<String, Object?> args,
  SessionContext ctx,
);

String _jsonSchemaTypeName(HostParamType type) {
  switch (type) {
    case HostParamType.string:
      return 'string';
    case HostParamType.integer:
      return 'integer';
    case HostParamType.float:
      return 'number';
    case HostParamType.boolean:
      return 'boolean';
    case HostParamType.array:
      return 'array';
    case HostParamType.object:
      return 'object';
  }
}
