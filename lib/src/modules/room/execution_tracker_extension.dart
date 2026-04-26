import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_step.dart';
import 'execution_tracker.dart';
import 'steps_projection.dart';
import 'tracker_registry.dart';

/// A [SessionExtension] that reacts to [AgentSession] run-state changes and
/// drives an internal [TrackerRegistry].
///
/// Subscribes to `session.runState` in [onAttach] and routes
/// [RunningState]/terminal states into the registry. The resulting
/// [Map<String, ExecutionTracker>] is exposed via the [stateSignal] and the
/// convenience [trackers] getter.
///
/// [ThreadViewState] absorbs the live trackers into its own historical
/// registry on detach, so execution data persists after the session ends.
class ExecutionTrackerExtension extends SessionExtension
    with StatefulSessionExtension<Map<String, ExecutionTracker>> {
  ExecutionTrackerExtension() : _registry = TrackerRegistry() {
    setInitialState(const <String, ExecutionTracker>{});
  }

  final TrackerRegistry _registry;
  void Function()? _runStateUnsub;
  AgentSession? _session;
  StateBus? _bus;

  @override
  String get namespace => 'execution_tracker';

  @override
  int get priority => 10;

  @override
  List<ClientTool> get tools => const [];

  /// Current tracker map (historical + live for this session).
  Map<String, ExecutionTracker> get trackers => _registry.trackers;

  @override
  Future<void> onAttach(AgentSession session) async {
    _session = session;
    _runStateUnsub = session.runState.subscribe(_onRunState);
  }

  @override
  Future<void> onAttachWithContext(SessionContext ctx) async {
    _bus = ctx.bus;
    await onAttach(ctx.session);
  }

  @override
  void onDispose() {
    _runStateUnsub?.call();
    _runStateUnsub = null;
    _session = null;
    _bus = null;
    _registry.dispose();
    super.onDispose();
  }

  void _onRunState(RunState runState) {
    final session = _session;
    if (session == null) return;
    switch (runState) {
      case RunningState(:final streaming):
        _registry.onStreaming(streaming, session.lastExecutionEvent);
        _sync();
      case CompletedState() || FailedState() || CancelledState():
        _registry.onRunTerminated();
        _sync();
      case IdleState() || ToolYieldingState():
        break;
    }
  }

  void _sync() {
    state = _registry.trackers;
    _mirrorStepsToBus();
  }

  /// Phase 1 step 6 — mirror the union of all live trackers' steps
  /// into the per-thread bus at `agentState['_meta']['steps']` so
  /// downstream consumers (e.g. cross-session-visible step log,
  /// future historical reconstitution) can read via [StepsProjection]
  /// rather than via this per-session signal.
  void _mirrorStepsToBus() {
    final bus = _bus;
    if (bus == null) return;
    final allSteps = <ExecutionStep>[];
    for (final tracker in _registry.trackers.values) {
      allSteps.addAll(tracker.steps.value);
    }
    final serialized = stepsToBusList(allSteps);
    bus.update((current) {
      final next = Map<String, dynamic>.from(current);
      final meta = Map<String, dynamic>.from(
        (next['_meta'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
      meta['steps'] = serialized;
      next['_meta'] = meta;
      return next;
    });
  }
}
