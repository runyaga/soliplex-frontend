import 'package:dart_monty/dart_monty_bridge.dart' as monty
    show HostFunction, HostFunctionSchema, HostParam, HostParamType;
import 'package:dart_monty/dart_monty_bridge.dart' show MontyExtension;
import 'package:soliplex_agent/soliplex_agent.dart' as soliplex
    show HostFunction, HostFunctionSchema, HostParam, HostParamType;
import 'package:soliplex_agent/soliplex_agent.dart'
    show AgentSession, SessionContext, SessionExtension;

/// Synthesizes one [MontyExtension] per soliplex [SessionExtension]
/// that declares `hostFunctions`, so plugin authors never see
/// `dart_monty` types.
///
/// The translation is intentionally a 1:1 type rename — soliplex's
/// [soliplex.HostFunction] / [soliplex.HostFunctionSchema] /
/// [soliplex.HostParam] / [soliplex.HostParamType] mirror dart_monty's
/// shape member-for-member. The bridge layer here:
///
/// - Walks every sibling [SessionExtension] on a session.
/// - For any sibling whose `hostFunctions` is non-empty, creates one
///   `_BridgedMontyExtension` keyed by the sibling's `namespace`.
/// - Each synthesized extension translates each
///   [soliplex.HostFunction] into a [monty.HostFunction] and wraps the
///   handler so it receives the per-session [SessionContext]
///   (captured at attach time) instead of dart_monty's own
///   `HostContext`.
///
/// Plan reference: `docs/plans/reactive-bus-redesign.md` (Phase 2 step 9).
List<MontyExtension> synthesizeMontyHostExtensions({
  required AgentSession session,
  required SessionContext ctx,
  SessionExtension? skipSelf,
}) {
  final synthesized = <MontyExtension>[];
  for (final ext in session.extensions) {
    if (skipSelf != null && identical(ext, skipSelf)) continue;
    if (ext.hostFunctions.isEmpty) continue;
    synthesized.add(
      _BridgedMontyExtension(
        sourceNamespace: ext.namespace,
        soliplexFunctions: ext.hostFunctions,
        ctx: ctx,
      ),
    );
  }
  return synthesized;
}

/// One [MontyExtension] backed by a soliplex extension's host
/// functions. Each synthesized instance is bound to a single
/// [SessionContext] — never reuse across sessions.
class _BridgedMontyExtension extends MontyExtension {
  _BridgedMontyExtension({
    required String sourceNamespace,
    required List<soliplex.HostFunction> soliplexFunctions,
    required SessionContext ctx,
  })  : _namespace = sourceNamespace,
        _functions = soliplexFunctions
            .map((fn) => _bridge(fn, ctx))
            .toList(growable: false);

  final String _namespace;
  final List<monty.HostFunction> _functions;

  @override
  String get namespace => _namespace;

  @override
  List<monty.HostFunction> get functions => _functions;
}

monty.HostFunction _bridge(soliplex.HostFunction src, SessionContext ctx) {
  return monty.HostFunction(
    schema: monty.HostFunctionSchema(
      name: src.schema.name,
      description: src.schema.description.isEmpty
          ? null
          : src.schema.description,
      params: [
        for (final p in src.schema.params)
          monty.HostParam(
            name: p.name,
            type: _bridgeType(p.type),
            description: p.description.isEmpty ? null : p.description,
            isRequired: p.isRequired,
          ),
      ],
    ),
    handler: (args, _) => src.handler(args, ctx),
  );
}

monty.HostParamType _bridgeType(soliplex.HostParamType t) => switch (t) {
      soliplex.HostParamType.string => monty.HostParamType.string,
      soliplex.HostParamType.integer => monty.HostParamType.integer,
      soliplex.HostParamType.number => monty.HostParamType.number,
      soliplex.HostParamType.boolean => monty.HostParamType.boolean,
      soliplex.HostParamType.list => monty.HostParamType.list,
      soliplex.HostParamType.map => monty.HostParamType.map,
      soliplex.HostParamType.any => monty.HostParamType.any,
    };
