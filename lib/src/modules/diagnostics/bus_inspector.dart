import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

/// One recorded write to a per-thread `StateBus`.
///
/// Captures the [ThreadKey] context (which the bus itself does not
/// carry), the optional [tag] passed by the writer, and a frozen
/// snapshot of the state immediately after the commit.
@immutable
class BusEvent {
  BusEvent({
    required this.timestamp,
    required this.threadKey,
    required this.tag,
    required this.snapshot,
  });

  final DateTime timestamp;
  final ThreadKey threadKey;
  final String? tag;
  final Map<String, dynamic> snapshot;
}

/// Collects bus events for the bus inspector UI.
///
/// Wired into [AgentRuntime] via its `busObserver` constructor parameter,
/// so every commit on every per-thread `StateBus` flows through here.
/// Events are bounded: on overflow, the oldest event is dropped so a
/// long-running session cannot grow memory without bound.
class BusInspector with ChangeNotifier {
  BusInspector({int maxEvents = 1000})
      : _maxEvents = maxEvents > 0
            ? maxEvents
            : throw ArgumentError.value(
                maxEvents,
                'maxEvents',
                'must be positive',
              );

  final int _maxEvents;
  final ListQueue<BusEvent> _events = ListQueue<BusEvent>();
  bool _disposed = false;

  List<BusEvent> get events => List.unmodifiable(_events);

  void clear() {
    if (_disposed) return;
    _events.clear();
    notifyListeners();
  }

  /// Sink callable as a [ThreadBusObserver] from `AgentRuntime`.
  void record(
    ThreadKey threadKey,
    String? tag,
    Map<String, dynamic> snapshot,
  ) {
    if (_disposed) return;
    _events.addLast(
      BusEvent(
        timestamp: DateTime.now(),
        threadKey: threadKey,
        tag: tag,
        snapshot: snapshot,
      ),
    );
    if (_events.length > _maxEvents) _events.removeFirst();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
