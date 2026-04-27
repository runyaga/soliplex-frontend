import 'dart:async';

import 'package:meta/meta.dart';
import 'package:signals_core/signals_core.dart';
import 'package:soliplex_client/src/application/json_patch.dart';
import 'package:soliplex_client/src/domain/surface.dart';

/// One bus write — a `setAgentState` (snapshot) or `update`
/// (transformer) call that committed.
///
/// Carries enough information for observers (e.g. the in-app bus
/// inspector) to log, diff, or display the mutation. Emitted AFTER
/// the underlying signal value swaps, so observers see the same
/// post-write state any other reader would.
@immutable
class BusWriteEvent {
  /// Constructs a write event. Use [BusWriteKind.snapshot] for
  /// `setAgentState` callsites, [BusWriteKind.update] for
  /// `update` callsites.
  const BusWriteEvent({
    required this.kind,
    required this.before,
    required this.after,
    required this.timestamp,
    this.tag,
  });

  /// Which API was invoked.
  final BusWriteKind kind;

  /// State immediately before the write. Frozen (unmodifiable).
  final Map<String, dynamic> before;

  /// State immediately after the write. Frozen (unmodifiable). The
  /// same [Map] [StateBus.agentState] now exposes.
  final Map<String, dynamic> after;

  /// Wall-clock at write time.
  final DateTime timestamp;

  /// Optional caller-supplied tag. Conventionally a short identifier
  /// like `"narration"`, `"ag-ui-snapshot"`, or `"map.set_site"` so
  /// observers can attribute the write back to a callsite without a
  /// stack walk.
  final String? tag;
}

/// Flavor of a [BusWriteEvent].
enum BusWriteKind {
  /// `setAgentState(...)` — full replacement.
  snapshot,

  /// `update(transform)` — derived from current state via a transform.
  update,
}

/// Observer callback fired on every committed bus write.
typedef BusObserver = void Function(BusWriteEvent event);

/// Per-thread reactive bus that mirrors AG-UI agent state and runs
/// registered surface projections over it.
///
/// Pure-Dart, no Flutter. The Flutter widget layer subscribes to the
/// signals exposed here through `signals_flutter`.
///
/// Lifecycle: a host (typically the per-thread view state in the
/// app shell) constructs one `StateBus` per active thread, feeds
/// raw agent-state maps into [setAgentState] (or applies deltas
/// via [update]) as AG-UI events arrive, and disposes when the
/// thread is torn down. Surfaces register projections via [project]
/// and read the returned signal.
///
/// This is the M3 plumbing in the GenUI plan — the seam between the
/// AG-UI event pipeline (already wired through
/// `AguiEventProcessor`) and the Surface contract.
class StateBus {
  /// Construct a fresh bus. The initial agent state is empty; feed
  /// the first snapshot via [setAgentState] when one arrives.
  ///
  /// Pass [observer] to receive a [BusWriteEvent] after every
  /// committed write. Observers must not throw; they run on the
  /// writer's microtask. The observer is the foundation for the
  /// in-app bus inspector and the delta log.
  StateBus({
    Map<String, dynamic> initialAgentState = const {},
    BusObserver? observer,
  })  : _agentState = signal(_freeze(initialAgentState)),
        _observer = observer;

  final Signal<Map<String, dynamic>> _agentState;
  final StreamController<SurfaceEvent> _events =
      StreamController<SurfaceEvent>.broadcast();
  final BusObserver? _observer;

  bool _disposed = false;

  /// Read-only feed of the current raw agent-state map.
  ///
  /// Identity changes on every replacement so listeners always fire,
  /// even when delta application produces structurally-equal maps.
  ReadonlySignal<Map<String, dynamic>> get agentState => _agentState.readonly();

  /// Write-back channel for surface-originated events (P6 spike).
  ///
  /// Subscribed by the thread host (typically `ThreadViewState`)
  /// which forwards each event toward the agent — e.g. as a
  /// synthetic user message, a structured tool-call argument, or
  /// (when AG-UI grows a dedicated client→server event type) an
  /// explicit `SurfaceEvent` frame.
  ///
  /// Surfaces emit via [Surface.emit] which calls [emit]; this
  /// stream is the host-side receive end.
  Stream<SurfaceEvent> get events => _events.stream;

  /// Push a [SurfaceEvent] toward the agent. Surfaces call this
  /// (or override [Surface.emit] which does) when the user
  /// interacts with the rendered output.
  void emit(SurfaceEvent event) {
    if (_disposed) return;
    _events.add(event);
  }

  /// Replace the entire agent-state map. Call when an AG-UI
  /// `StateSnapshotEvent` arrives.
  ///
  /// Pass [tag] to attribute the write to a callsite for the
  /// observer (e.g. `"ag-ui-snapshot"` from the event processor,
  /// `"history-rehydrate"` from the thread loader). Optional;
  /// `null` is a fine default for ad-hoc writes.
  void setAgentState(Map<String, dynamic> next, {String? tag}) {
    if (_disposed) return;
    final before = _agentState.value;
    final after = _freeze(next);
    _agentState.value = after;
    _notify(BusWriteKind.snapshot, before, after, tag);
  }

  /// Replace via a transform applied to the current map. Convenient
  /// for delta-applying code that wants to compute the next state in
  /// one step:
  ///
  /// ```dart
  /// bus.update((current) => applyJsonPatch(current, deltaOps));
  /// ```
  ///
  /// Pass [tag] to attribute the write to a callsite for the
  /// observer (e.g. `"narration"`, `"map.set_site"`).
  void update(
    Map<String, dynamic> Function(Map<String, dynamic> current) transform, {
    String? tag,
  }) {
    if (_disposed) return;
    final before = _agentState.value;
    final after = _freeze(transform(before));
    _agentState.value = after;
    _notify(BusWriteKind.update, before, after, tag);
  }

  /// Apply a list of RFC 6902 JSON Patch [operations] against the
  /// current agent state and commit the result.
  ///
  /// Wire-aligned with AG-UI's `StateDeltaEvent`. The same
  /// [applyJsonPatch] helper used by `AguiEventProcessor` is invoked
  /// here, so server-side deltas and plugin-side deltas produce
  /// identical results given the same ops.
  ///
  /// Pass [tag] to attribute the write to a callsite for the observer
  /// (e.g. `"ag-ui-delta"`, `"narration.append"`). Idempotent if
  /// [operations] is empty — emits no observer event.
  ///
  /// Plugin authors who want to build computed values (e.g.
  /// `count + 1`) prefer [update]; this method is for callers that
  /// already hold JSON Patch ops in hand.
  void applyDelta(List<dynamic> operations, {String? tag}) {
    if (_disposed) return;
    if (operations.isEmpty) return;
    final before = _agentState.value;
    final after = _freeze(applyJsonPatch(before, operations));
    _agentState.value = after;
    _notify(BusWriteKind.update, before, after, tag);
  }

  void _notify(
    BusWriteKind kind,
    Map<String, dynamic> before,
    Map<String, dynamic> after,
    String? tag,
  ) {
    final observer = _observer;
    if (observer == null) return;
    observer(
      BusWriteEvent(
        kind: kind,
        before: before,
        after: after,
        timestamp: DateTime.now(),
        tag: tag,
      ),
    );
  }

  /// Register a [StateProjection] and receive a derived signal that
  /// recomputes on every agent-state change.
  ///
  /// The returned signal is owned by this bus; it is disposed when
  /// the bus is disposed. Callers should NOT call `.dispose()` on it.
  ReadonlySignal<S> project<S>(StateProjection<S> projection) {
    return computed<S>(() => projection.project(_agentState.value));
  }

  /// Tear down. Idempotent. Disposes the underlying signal so any
  /// derived projections produced via [project] also stop firing,
  /// and closes the [events] stream so subscribers complete.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _agentState.dispose();
    unawaited(_events.close());
  }

  /// True after [dispose] has run. Visible for tests so they can
  /// assert post-tear-down behaviour.
  @visibleForTesting
  bool get isDisposed => _disposed;

  /// Defensive shallow copy so callers can't mutate the value held
  /// by the signal. JSON-Patch–style consumers expect "snapshot
  /// semantics" — every value seen via [agentState] is a frozen
  /// view of the state at that instant.
  static Map<String, dynamic> _freeze(Map<String, dynamic> map) =>
      Map<String, dynamic>.unmodifiable(map);
}
