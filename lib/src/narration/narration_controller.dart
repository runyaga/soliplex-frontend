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
/// Two input paths feed [entries]:
///
/// - **Imperative** ([add] / [clear]) — used by the Python external,
///   the demo replay, and any direct caller. Always available.
/// - **Projection** ([wireProjection]) — when wired, the controller
///   replaces [entries] with the projected signal so UI surfaces
///   stay in sync with agent-side state. Conforms to [Surface] for
///   the GenUI plan.
///
/// State is intentionally ephemeral — clearing on demo restart or
/// page reload is fine. If persistence becomes a real ask, this is
/// where to wire it.
class NarrationController implements Surface<List<Narration>> {
  /// Construct with [maxEntries] capacity for the imperative buffer.
  NarrationController({this.maxEntries = 64});

  /// Buffer ceiling for [add]; ignored when a projection is wired
  /// (the projected list is the source of truth in that mode).
  final int maxEntries;

  final Signal<List<Narration>> _imperative = signal(const <Narration>[]);

  /// When non-null, [entries] reads from this projected signal
  /// instead of the imperative buffer.
  ReadonlySignal<List<Narration>>? _projected;
  void Function()? _projectedUnsub;

  @override
  String get id => 'narration';

  @override
  ReadonlySignal<List<Narration>> get state => entries;

  /// No-op write-back. Narration is read-only from the UI side; user
  /// interactions (clicking a line, etc.) don't push events to the
  /// agent in v1. P6 will revisit when interactive surfaces ship.
  @override
  void emit(SurfaceEvent event) {}

  /// Read-only feed for widgets. Shows the projected state when a
  /// projection has been wired; otherwise the imperative buffer.
  ReadonlySignal<List<Narration>> get entries => _projected ?? _imperative;

  int _seq = 0;

  /// Wire a projected source. The controller's [entries] signal
  /// becomes the projection's output until [unwireProjection] is
  /// called or a different projection replaces it.
  ///
  /// Pass `null` to detach the current projection (equivalent to
  /// [unwireProjection]).
  void wireProjection(ReadonlySignal<List<Narration>>? projected) {
    _projectedUnsub?.call();
    _projectedUnsub = null;
    _projected = projected;
  }

  /// Detach the current projection if any. Imperative buffer
  /// resumes as the source.
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
    if (_projected != null) return entry;
    final next = [..._imperative.value, entry];
    if (next.length > maxEntries) {
      next.removeRange(0, next.length - maxEntries);
    }
    _imperative.value = next;
    return entry;
  }

  /// Reset the log. Called on script start so each demo run begins
  /// with a clean board. Only clears the imperative buffer; a wired
  /// projection is left alone.
  void clear() {
    _imperative.value = const <Narration>[];
  }

  @override
  void dispose() {
    _projectedUnsub?.call();
    _projectedUnsub = null;
    _projected = null;
    _imperative.dispose();
  }
}
