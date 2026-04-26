import 'package:soliplex_client/soliplex_client.dart' show StateProjection;

import 'widget_spec.dart';

/// Projects a list of [WidgetSpec] from `agentState['ui']['widgets']`.
///
/// The agent emits an array of objects with `{name, data}` (and
/// optionally `id`). Bad shapes produce an empty list — projections
/// must be tolerant; the agent may send partial state during
/// streaming.
///
/// Coexists with the other GenUI surface projections
/// (`NarrationProjection`, `MapMarkersProjection`,
/// `MapSpritesProjection`, `MapHudProjection`). Different keyspace
/// under `ui`, different surface, same contract.
class WidgetTreeProjection extends StateProjection<List<WidgetSpec>> {
  /// Const constructor — projection is stateless.
  const WidgetTreeProjection();

  @override
  List<WidgetSpec> project(Map<String, dynamic> agentState) {
    final ui = agentState['ui'];
    if (ui is! Map) return const [];
    final raw = ui['widgets'];
    if (raw is! List) return const [];
    final out = <WidgetSpec>[];
    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is! Map) continue;
      final name = entry['name'];
      if (name is! String) continue;
      final id = entry['id'] is String ? entry['id']! as String : 'w-$i';
      final data = entry['data'];
      out.add(
        WidgetSpec(
          id: id,
          name: name,
          data: data is Map<String, dynamic> ? data : const {},
        ),
      );
    }
    return out;
  }
}
