import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// Collects [BusWriteEvent]s for the bus inspector UI.
///
/// Plumbed as the [BusObserver] passed into `StateBus` (and through it
/// into `ThreadState` / `AgentRuntime`). Events are bounded — on
/// overflow the oldest event is dropped so a long-running session
/// cannot grow memory without bound.
///
/// Mirrors `NetworkInspector`'s shape (ChangeNotifier + ring buffer +
/// observer hook) so the diagnostics module's existing patterns
/// translate 1:1.
class BusInspector with ChangeNotifier {
  /// Constructs an inspector with an optional `maxEvents` cap.
  /// Defaults to 1000 — the same cap `NetworkInspector` uses.
  BusInspector({int maxEvents = 1000})
      : _maxEvents = maxEvents > 0
            ? maxEvents
            : throw ArgumentError.value(
                maxEvents,
                'maxEvents',
                'must be positive',
              );

  final int _maxEvents;
  final ListQueue<BusWriteEvent> _events = ListQueue<BusWriteEvent>();
  bool _disposed = false;

  /// Captured write events in chronological order. Read-only.
  List<BusWriteEvent> get events => List.unmodifiable(_events);

  /// Most recent agent-state snapshot, or `null` if no event has been
  /// recorded. The bus state panel renders this as a JSON tree.
  Map<String, dynamic>? get latestState =>
      _events.isEmpty ? null : _events.last.after;

  /// Records a write event. Wire as the observer when constructing
  /// [StateBus] (or threading via [ThreadState] / [AgentRuntime]):
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

  /// Clears the event log. Idempotent.
  void clear() {
    if (_disposed) return;
    if (_events.isEmpty) return;
    _events.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
