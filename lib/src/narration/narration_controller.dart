import 'package:signals_flutter/signals_flutter.dart';

import 'narration.dart';

/// Holds the live narration log. Owned by the
/// `narrationController` singleton so both the Python
/// `narrate_say(...)` external and the `NarrationPanel` widget
/// read/write the same signal regardless of session attach state.
///
/// State is intentionally ephemeral — clearing on demo restart or
/// page reload is fine. If persistence becomes a real ask, this is
/// where to wire it.
class NarrationController {
  NarrationController({this.maxEntries = 64});

  final int maxEntries;

  final Signal<List<Narration>> _entries = signal(const <Narration>[]);

  /// Read-only feed for widgets.
  ReadonlySignal<List<Narration>> get entries => _entries.readonly();

  int _seq = 0;

  /// Append a single narration line. Trims oldest when [maxEntries] is
  /// exceeded so the overlay never grows unbounded.
  Narration add({required NarrationActor actor, required String text}) {
    _seq += 1;
    final entry = Narration(
      id: 'n-$_seq',
      actor: actor,
      text: text,
      createdAt: DateTime.now(),
    );
    final next = [..._entries.value, entry];
    if (next.length > maxEntries) {
      next.removeRange(0, next.length - maxEntries);
    }
    _entries.value = next;
    return entry;
  }

  /// Reset the log. Called on script start so each demo run begins
  /// with a clean board.
  void clear() {
    _entries.value = const <Narration>[];
  }
}
