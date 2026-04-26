import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show StateProjection, Surface, SurfaceEvent;

import 'narration.dart';

/// Projects a list of [Narration] from the agent state map.
///
/// Reads `agentState['ui']['narrations']` as a list of
/// `{actor, text}` maps. Bad shapes produce an empty list — projections
/// must be tolerant; the agent may send partial state during streaming.
class NarrationProjection extends StateProjection<List<Narration>> {
  /// Const constructor — projection is stateless.
  const NarrationProjection();

  @override
  List<Narration> project(Map<String, dynamic> agentState) {
    final ui = agentState['ui'];
    if (ui is! Map) return const [];
    final raw = ui['narrations'];
    if (raw is! List) return const [];
    final out = <Narration>[];
    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is! Map) continue;
      final text = entry['text'];
      if (text is! String) continue;
      out.add(
        Narration(
          id: 'agent-$i',
          actor: NarrationActor.parse(entry['actor'] as String?),
          text: text,
          createdAt: DateTime.now(),
        ),
      );
    }
    return out;
  }
}

/// Holds the live narration log. Owned by the
/// `narrationController` singleton so both the Python
/// `narrate_say(...)` external and the `NarrationPanel` widget
/// read/write the same signal regardless of session attach state.
///
/// One stable [entries] signal is the only thing widgets watch. Two
/// input paths feed it:
///
/// - **Imperative** ([add] / [clear]) — used by the Python external,
///   the demo replay, and any direct caller. Always available when
///   no projection is wired.
/// - **Projection** ([wireProjection]) — when wired, the controller
///   subscribes to the projected signal and forwards each emission
///   into [entries]. Imperative writes are dropped while wired.
///   Conforms to [Surface] for the GenUI plan.
///
/// State is intentionally ephemeral — clearing on demo restart or
/// page reload is fine. If persistence becomes a real ask, this is
/// where to wire it.
class NarrationController implements Surface<List<Narration>> {
  /// Construct with [maxEntries] capacity for the imperative buffer.
  NarrationController({this.maxEntries = 64});

  /// Buffer ceiling for [add]; ignored while a projection is wired
  /// (the agent owns history in that mode).
  final int maxEntries;

  /// The single stable signal widgets watch. Never replaced —
  /// only its value changes, whether driven by [add] or by a wired
  /// projection forwarding through [wireProjection].
  final Signal<List<Narration>> _entries = signal(const <Narration>[]);

  /// When non-null, [add] is dropped because the agent owns state.
  void Function()? _projectedUnsub;

  @override
  String get id => 'narration';

  @override
  ReadonlySignal<List<Narration>> get state => _entries.readonly();

  /// Read-only feed for widgets — the same stable signal whether
  /// driven imperatively or by a projection.
  ReadonlySignal<List<Narration>> get entries => _entries.readonly();

  int _seq = 0;

  /// Wire a projected source. The controller forwards every
  /// emission from [projected] into [entries]. Imperative writes
  /// are dropped while a projection is wired. Pass `null` (or call
  /// [unwireProjection]) to detach.
  ///
  /// The first emission also seeds [entries] synchronously, so the
  /// panel renders any current projection state immediately.
  void wireProjection(ReadonlySignal<List<Narration>>? projected) {
    _projectedUnsub?.call();
    _projectedUnsub = null;
    if (projected == null) return;
    // Seed synchronously with the projection's current value.
    _entries.value = projected.value;
    _projectedUnsub = projected.subscribe((value) {
      _entries.value = value;
    });
  }

  /// Detach the current projection if any. Imperative writes
  /// resume; the [entries] signal keeps its last value until
  /// [add] / [clear] is called.
  void unwireProjection() => wireProjection(null);

  /// Append a single narration line. Trims oldest when [maxEntries] is
  /// exceeded so the overlay never grows unbounded. No-op when a
  /// projection is wired (the agent owns state in that mode).
  Narration add({required NarrationActor actor, required String text}) {
    _seq += 1;
    final entry = Narration(
      id: 'n-$_seq',
      actor: actor,
      text: text,
      createdAt: DateTime.now(),
    );
    if (_projectedUnsub != null) return entry;
    final next = [..._entries.value, entry];
    if (next.length > maxEntries) {
      next.removeRange(0, next.length - maxEntries);
    }
    _entries.value = next;
    return entry;
  }

  /// Reset the log. Called on script start so each demo run begins
  /// with a clean board. No-op when a projection is wired (the
  /// agent owns state in that mode).
  void clear() {
    if (_projectedUnsub != null) return;
    _entries.value = const <Narration>[];
  }

  /// No-op write-back. Narration is read-only from the UI side; user
  /// interactions (clicking a line, etc.) don't push events to the
  /// agent in v1. P6 will revisit when interactive surfaces ship.
  @override
  void emit(SurfaceEvent event) {}

  @override
  void dispose() {
    _projectedUnsub?.call();
    _projectedUnsub = null;
    _entries.dispose();
  }
}
