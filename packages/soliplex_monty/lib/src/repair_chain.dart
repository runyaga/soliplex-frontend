import 'dart:math';

import 'package:flutter/foundation.dart';

/// Where a [RepairChain] stands.
enum RepairStatus {
  /// Repairs may be requested and a repaired editor may run on arrival.
  active,

  /// The user pressed Stop or unchecked AI Fix; automatic runs stop.
  ended,

  /// A repaired program ran without an error.
  fixed,
}

/// One bounded series of model repairs that a user's Run click started.
///
/// The client owns the count. [max] comes from the client's limits and grows
/// only on an explicit user request, never from a server payload.
class RepairChain extends ChangeNotifier {
  RepairChain._(this.id, this.max, this.autoRun);

  final String id;

  /// Whether AI Fix authorized running the delivered repair at failure time.
  final bool autoRun;

  /// Repair rounds the chain may request.
  int max;

  /// Repair rounds requested so far.
  int rounds = 0;

  /// Completed executions, retained across repair surface replacements.
  int runs = 0;

  /// The attempt a repaired editor must carry to run on arrival, or null
  /// when no repair is pending.
  int? awaiting;

  /// Delivered source awaiting replacement; remounting it cannot claim a fix.
  String? awaitingSource;

  RepairStatus status = RepairStatus.active;

  bool get isActive => status == RepairStatus.active;

  /// Whether the chain may request another round without asking the user.
  bool get hasBudget => isActive && awaiting == null && rounds < max;

  /// Requests the next round and returns its attempt number, or null when a
  /// round is already pending, the chain ended or the budget is spent.
  int? request() {
    if (!hasBudget) return null;
    awaiting = ++rounds;
    notifyListeners();
    return rounds;
  }

  /// Grants one round beyond the current budget after a manual AI Fix click,
  /// and reopens an ended chain.
  void grant() {
    if (awaiting != null) return;
    status = RepairStatus.active;
    if (rounds >= max) max = rounds + 1;
    notifyListeners();
  }

  /// Takes the pending round for a repaired editor carrying [attempt].
  ///
  /// True at most once per round, and only while the chain is active.
  bool claim(int attempt) {
    if (!isActive || awaiting != attempt || attempt > max) return false;
    awaiting = null;
    notifyListeners();
    return true;
  }

  /// Ends the chain. A pending repair no longer runs when it arrives.
  void end() {
    if (status == RepairStatus.ended && awaiting == null) return;
    status = RepairStatus.ended;
    awaiting = null;
    notifyListeners();
  }

  void markFixed() {
    status = RepairStatus.fixed;
    awaiting = null;
    notifyListeners();
  }
}

/// Repair chains created by user Run clicks in this app session.
///
/// Held in memory only: a reloaded page has none, so nothing restored from
/// history can find a chain to continue.
class RepairChains {
  RepairChains({this.capacity = 64});

  /// The chains of the app session.
  static final RepairChains shared = RepairChains();

  /// Pending chains keyed by stable program surface, never persisted.
  final Map<String, String> surfaceChains = {};

  final int capacity;
  final Map<String, RepairChain> _chains = {};
  final Random _random = Random.secure();

  RepairChain? operator [](String id) => _chains[id];

  /// Starts a chain allowed [max] rounds.
  RepairChain start(int max, {bool autoRun = false}) {
    final id =
        'chain-${List.generate(
          8,
          (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join()}';
    while (_chains.length >= capacity) {
      final id = _chains.keys.first;
      _chains.remove(id)?.end();
      surfaceChains.removeWhere((_, chainId) => chainId == id);
    }
    return _chains[id] = RepairChain._(id, max, autoRun);
  }
}
