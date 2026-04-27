import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:soliplex_agent/soliplex_agent.dart'
    show RegisteredToolInfo, ToolInvocationEvent;
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
  final Map<String, List<RegisteredToolInfo>> _registeredToolsByScope = {};
  int _eventsTotal = 0;
  int _toolInvocationsTotal = 0;
  bool _disposed = false;

  /// Captured bus-write events in chronological order. Read-only.
  List<BusWriteEvent> get events => List.unmodifiable(_events);

  /// Captured LLM tool-invocation events in chronological order.
  /// Read-only.
  List<ToolInvocationEvent> get toolInvocations =>
      List.unmodifiable(_toolInvocations);

  /// Monotonic count of bus writes recorded since construction
  /// (or since the last `clear()`). Survives ring-buffer rotation
  /// — older events drop out of [events] but still counted here.
  /// The most-recent retained event has absolute sequence number
  /// `eventsTotal - 1`; the oldest retained is
  /// `eventsTotal - events.length`.
  int get eventsTotal => _eventsTotal;

  /// Same monotonic counter for tool invocations.
  int get toolInvocationsTotal => _toolInvocationsTotal;

  /// Latest snapshot of `ClientTool` definitions registered for each
  /// session, keyed by scope (`"serverId/roomId/threadId"`). Wired
  /// via the runtime's [ToolRegistryObserver]. Updated each time a
  /// session is built so re-spawning a thread refreshes its set.
  ///
  /// Returns an unmodifiable view; callers must treat the inner lists
  /// as read-only as well.
  Map<String, List<RegisteredToolInfo>> get registeredToolsByScope =>
      Map.unmodifiable(_registeredToolsByScope);

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
    _eventsTotal++;
    if (_events.length > _maxEvents) _events.removeFirst();
    notifyListeners();
  }

  /// Records the tool-registry snapshot built for one session. Wire
  /// as the `ToolRegistryObserver` when constructing [AgentRuntime]:
  ///
  /// ```dart
  /// AgentRuntime(toolRegistryObserver: inspector.recordToolRegistry, ...);
  /// ```
  void recordToolRegistry(String scope, List<RegisteredToolInfo> tools) {
    if (_disposed) return;
    _registeredToolsByScope[scope] = List.unmodifiable(tools);
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
    _toolInvocationsTotal++;
    if (_toolInvocations.length > _maxToolInvocations) {
      _toolInvocations.removeFirst();
    }
    notifyListeners();
  }

  /// Clears both event logs and resets the monotonic counters.
  /// Idempotent.
  void clear() {
    if (_disposed) return;
    if (_events.isEmpty &&
        _toolInvocations.isEmpty &&
        _registeredToolsByScope.isEmpty) {
      return;
    }
    _events.clear();
    _toolInvocations.clear();
    _registeredToolsByScope.clear();
    _eventsTotal = 0;
    _toolInvocationsTotal = 0;
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
    _registeredToolsByScope.clear();
    super.dispose();
  }
}
