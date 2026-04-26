import 'package:soliplex_client/soliplex_client.dart' show StateProjection;

import 'execution_step.dart';

/// Projects the union of execution steps from the per-thread bus.
///
/// Reads `agentState['/_meta']['steps']` as a list of
/// `{label, type, status, ms}` maps and produces a typed
/// `List<ExecutionStep>`. The bus path is **soliplex-internal**; the
/// agent server does not emit it. [ExecutionTrackerExtension]
/// mirrors its tracker map's steps into the bus on every change so
/// downstream readers (cross-session-visible step log, future
/// historical reconstitution) can subscribe via [StateProjection]
/// rather than via the per-session extension signal.
///
/// Phase 1 step 6 — read side. The UI cutover and the
/// historical-reconstitution path are separate follow-ups.
///
/// Plan reference: `docs/plans/reactive-bus-redesign.md` (Phase 1 step 6).
class StepsProjection extends StateProjection<List<ExecutionStep>> {
  /// Const constructor — projection is stateless.
  const StepsProjection();

  @override
  List<ExecutionStep> project(Map<String, dynamic> agentState) {
    final meta = agentState['_meta'];
    if (meta is! Map) return const [];
    final steps = meta['steps'];
    if (steps is! List) return const [];
    final out = <ExecutionStep>[];
    for (final raw in steps) {
      if (raw is! Map) continue;
      final label = raw['label'];
      final typeStr = raw['type'];
      final statusStr = raw['status'];
      final msRaw = raw['ms'];
      if (label is! String || typeStr is! String || statusStr is! String) {
        continue;
      }
      final type = StepType.values.firstWhere(
        (t) => t.name == typeStr,
        orElse: () => StepType.thinking,
      );
      final status = StepStatus.values.firstWhere(
        (s) => s.name == statusStr,
        orElse: () => StepStatus.completed,
      );
      final ms = msRaw is num ? msRaw.toInt() : 0;
      out.add(
        ExecutionStep(
          label: label,
          type: type,
          status: status,
          timestamp: Duration(milliseconds: ms),
        ),
      );
    }
    return out;
  }
}

/// Serialize a list of [ExecutionStep] into the bus-path shape
/// [StepsProjection] reads. Called by [ExecutionTrackerExtension] when
/// it mirrors its tracker map into the bus.
List<Map<String, dynamic>> stepsToBusList(Iterable<ExecutionStep> steps) {
  return [
    for (final step in steps)
      {
        'label': step.label,
        'type': step.type.name,
        'status': step.status.name,
        'ms': step.timestamp.inMilliseconds,
      },
  ];
}
