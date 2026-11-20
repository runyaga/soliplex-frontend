import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// A new instance has no consent. Persisted layout is a story, never a playlist.
class WalkthroughPlayer extends ChangeNotifier {
  static const suggestion = 'Start the walkthrough.';
  Map<String, dynamic>? state;
  void Function(String action, Map<String, Object?> context)? send;
  Future<void> Function(Map<String, dynamic> step)? perform;
  Timer? _timer;
  final _seen = <String>{};
  bool _authorized = false;
  bool paused = false;
  bool _waiting = false;
  int _generation = 0;
  bool get active => _authorized;
  String? error;

  void authorize() {
    stop();
    _authorized = true;
    paused = false;
    error = null;
    state = null;
    _waiting = true;
    _timer = Timer(const Duration(seconds: 30), () {
      if (state == null) stop();
    });
    notifyListeners();
  }

  void observe(Map<String, dynamic>? next) {
    if (next == null) return;
    final id = next['id'] as String;
    if (!_authorized) {
      _seen.add(id);
      state = next;
      return;
    }
    if (state == null && (_seen.contains(id) || next['step'] != 0)) return;
    if (state != null && next['id'] != state!['id']) return;
    if (state != null && (next['step'] as int) < (state!['step'] as int)) {
      return;
    }
    if (state?['step'] == next['step'] && state?['status'] == next['status']) {
      return;
    }
    _timer?.cancel();
    state = next;
    _seen.add(id);
    _waiting = false;
    if (next['status'] != 'running') {
      _authorized = false;
      notifyListeners();
      return;
    }
    final generation = _generation;
    // Effects run only after the accepted surfaces have mounted this frame.
    unawaited(_play(next, generation));
  }

  Future<void> _play(Map<String, dynamic> step, int generation) async {
    _waiting = true;
    notifyListeners();
    try {
      await perform?.call(step);
      if (!_authorized || generation != _generation) return;
      _waiting = false;
      _schedule();
      notifyListeners();
    } on Object catch (e) {
      // Fixed UI diagnostic: surface contents may include sensitive user edits.
      if (generation != _generation) return;
      stop();
      error =
          'Walkthrough stopped: the expected curated surface was unavailable '
          'or changed (${e.runtimeType}). You can use the canvas normally.';
      notifyListeners();
    }
  }

  void _schedule() {
    if (!_authorized || paused || _waiting) return;
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: state!['delayMs'] as int), next);
  }

  void next() {
    if (!_authorized || _waiting || state == null) return;
    _timer?.cancel();
    _waiting = true;
    send?.call('next', {'id': state!['id'], 'step': state!['step']});
    // A rejected/lost action must not leave a silently frozen tour.
    _timer = Timer(const Duration(seconds: 30), () {
      if (_waiting) stop();
    });
    notifyListeners();
  }

  void togglePause() {
    if (!_authorized) return;
    paused = !paused;
    _timer?.cancel();
    if (!paused) _schedule();
    notifyListeners();
  }

  void draftChanged(String text) {
    if (text.isNotEmpty) stop();
  }

  void stop() {
    final current = state;
    final wasActive = _authorized;
    _authorized = false;
    _waiting = false;
    _generation++;
    _timer?.cancel();
    if (wasActive && current != null && current['status'] == 'running') {
      send?.call('stop', {'id': current['id'], 'step': current['step']});
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _authorized = false;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}

class WalkthroughScope extends InheritedWidget {
  const WalkthroughScope(
      {required this.player, required super.child, super.key});
  final WalkthroughPlayer player;
  static WalkthroughPlayer? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WalkthroughScope>()?.player;
  @override
  bool updateShouldNotify(WalkthroughScope oldWidget) =>
      player != oldWidget.player;
}

class WalkthroughControls extends StatelessWidget {
  const WalkthroughControls({required this.player, super.key});
  final WalkthroughPlayer player;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: player,
        builder: (context, _) => Wrap(
          spacing: SoliplexSpacing.s2,
          children: [
            if (player.error case final error?) Text(error),
            if (player.active) ...[
              SoliplexButton.text(
                  onPressed: player.stop,
                  child: const Text('Stop walkthrough')),
              SoliplexButton.text(
                  onPressed: player.togglePause,
                  child: Text(player.paused ? 'Resume' : 'Pause')),
              SoliplexButton.text(
                  onPressed: player.next, child: const Text('Next')),
            ] else
              const Text(
                  'Walkthrough is not playing. Reload never resumes it.'),
          ],
        ),
      );
}
