import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show ToolInvocationEvent;
import 'package:soliplex_client/soliplex_client.dart';

/// Collects [BusWriteEvent]s and [ToolInvocationEvent]s for the bus
/// inspector UI.
///
/// Two observation surfaces, one bounded ring buffer per surface:
///
/// - **Bus writes** ([record]) — every committed `setAgentState` /
///   `update` on a runtime-managed `StateBus`. Plumbed via the
///   `BusObserver` passed into `AgentRuntime`.
/// - **Tool invocations** ([recordToolInvocation]) — every
///   `ToolRegistry.execute` call that succeeds or throws. Plumbed
///   via the `ToolObserver` passed into `AgentRuntime`.
///
/// Both surfaces share a single [ChangeNotifier] so the inspector
/// screen can listen once and rebuild any tab when either fires.
/// Each ring buffer is independently bounded so a busy bus doesn't
/// starve the tool log (or vice-versa).
///
/// Mirrors `NetworkInspector`'s shape so the diagnostics module's
/// existing patterns translate 1:1.
class BusInspector with ChangeNotifier {
  /// Constructs an inspector with optional caps for each ring
  /// buffer. Defaults to 1000 each — the same cap `NetworkInspector`
  /// uses.
  BusInspector({int maxEvents = 1000, int maxToolInvocations = 1000})
      : _maxEvents = maxEvents > 0
            ? maxEvents
            : throw ArgumentError.value(
                maxEvents,
                'maxEvents',
                'must be positive',
              ),
        _maxToolInvocations = maxToolInvocations > 0
            ? maxToolInvocations
            : throw ArgumentError.value(
                maxToolInvocations,
                'maxToolInvocations',
                'must be positive',
              );

  final int _maxEvents;
  final int _maxToolInvocations;
  final ListQueue<BusWriteEvent> _events = ListQueue<BusWriteEvent>();
  final ListQueue<ToolInvocationEvent> _toolInvocations =
      ListQueue<ToolInvocationEvent>();
  bool _disposed = false;

  /// Captured bus-write events in chronological order. Read-only.
  List<BusWriteEvent> get events => List.unmodifiable(_events);

  /// Captured LLM tool-invocation events in chronological order.
  /// Read-only.
  List<ToolInvocationEvent> get toolInvocations =>
      List.unmodifiable(_toolInvocations);

  /// Most recent agent-state snapshot, or `null` if no event has been
  /// recorded. The bus state panel renders this as a JSON tree.
  Map<String, dynamic>? get latestState =>
      _events.isEmpty ? null : _events.last.after;

  /// Records a bus-write event. Wire as the [BusObserver] when
  /// constructing [StateBus] (or threading via [ThreadState] /
  /// [AgentRuntime]):
  ///
  /// ```dart
  /// AgentRuntime(busObserver: inspector.record, ...);
  /// ```
  void record(BusWriteEvent event) {
    if (_disposed) return;
    _events.addLast(event);
    if (_events.length > _maxEvents) _events.removeFirst();
    notifyListeners();
  }

  /// Records an LLM tool-invocation event. Wire as the `ToolObserver`
  /// when constructing [AgentRuntime]:
  ///
  /// ```dart
  /// AgentRuntime(toolObserver: inspector.recordToolInvocation, ...);
  /// ```
  void recordToolInvocation(ToolInvocationEvent event) {
    if (_disposed) return;
    _toolInvocations.addLast(event);
    if (_toolInvocations.length > _maxToolInvocations) {
      _toolInvocations.removeFirst();
    }
    notifyListeners();
  }

  /// Clears both event logs. Idempotent.
  void clear() {
    if (_disposed) return;
    if (_events.isEmpty && _toolInvocations.isEmpty) return;
    _events.clear();
    _toolInvocations.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Free the ring-buffer references eagerly. The inspector is
    // typically an app-singleton constructed in `flavors/standard.dart`,
    // so dispose only happens at app teardown — but if a
    // longer-lived test or alternate flavor disposes mid-run, hanging
    // onto stale references prevents collection of the underlying
    // bus / tool-call structures.
    _events.clear();
    _toolInvocations.clear();
    super.dispose();
  }
}
