import 'dart:convert';

import 'package:soliplex_agent/soliplex_agent.dart';

/// A [SessionExtension] that declares LLM tools writing the per-thread
/// bus at `agentState['ui']['map']`.
///
/// Phase 1 step 5 — first map operations converted to the bus-write
/// pattern. The existing `MapExtension` singleton (and its imperative
/// tool surface like `add_marker`) is carried forward; both
/// `MapMontyExtension` (Python bridge) and the legacy LLM tools on
/// `MapExtension` keep working unchanged. Phase 2 retires them in
/// favor of the bus-write path established here.
///
/// The bus paths used by [MapPlugin] are the same the existing
/// projections in `map_projections.dart` already read:
///
/// - `set_site` / `clear_sites` → `/ui/map/sites` (read by
///   `MapMarkersProjection`)
/// - `move_convoy_to` → `/ui/map/convoy` (read by
///   `MapSpritesProjection`)
///
/// So bus-write tools feed the same render pipeline AG-UI server
/// state events feed today, with no projection changes required.
///
/// Plan reference: `docs/plans/reactive-bus-redesign.md` (Phase 1 step 5).
class MapPlugin extends SessionExtension {
  MapPlugin();

  SessionContext? _ctx;

  @override
  String get namespace => 'map_plugin';

  @override
  Future<void> onAttach(AgentSession session) async {}

  @override
  Future<void> onAttachWithContext(SessionContext ctx) async {
    _ctx = ctx;
    await onAttach(ctx.session);
  }

  @override
  void onDispose() {
    _ctx = null;
  }

  @override
  List<ClientTool> get tools => [
        ClientTool.simple(
          name: 'set_site',
          description: 'Add or update a site marker on the map. Sites '
              'render via the existing markers projection. Status flips '
              'colors: "served" → green, anything else → orange.',
          parameters: const {
            'type': 'object',
            'properties': {
              'id': {
                'type': 'string',
                'description': 'Stable site identifier. Reusing an id '
                    'updates the existing site.',
              },
              'name': {'type': 'string'},
              'lat': {'type': 'number'},
              'lng': {'type': 'number'},
              'status': {
                'type': 'string',
                'description': '"pending" (default, orange) or "served" '
                    '(green).',
              },
            },
            'required': ['id', 'lat', 'lng'],
          },
          executor: _executeSetSite,
        ),
        ClientTool.simple(
          name: 'clear_sites',
          description: 'Remove every site from the map.',
          executor: _executeClearSites,
        ),
        ClientTool.simple(
          name: 'move_convoy_to',
          description: 'Move the convoy sprite to a lat/lng. The '
              'sprite tween picks up the new position from the bus.',
          parameters: const {
            'type': 'object',
            'properties': {
              'lat': {'type': 'number'},
              'lng': {'type': 'number'},
              'heading': {
                'type': 'number',
                'description': 'Heading in degrees (0 = north). '
                    'Optional.',
              },
            },
            'required': ['lat', 'lng'],
          },
          executor: _executeMoveConvoyTo,
        ),
      ];

  Future<String> _executeSetSite(
    ToolCallInfo toolCall,
    ToolExecutionContext _,
  ) async {
    final ctx = _ctx;
    if (ctx == null) return 'set_site: plugin not attached';
    final args = _decodeArgs(toolCall);
    final id = args['id']?.toString();
    final lat = args['lat'];
    final lng = args['lng'];
    if (id == null || id.isEmpty) {
      return 'set_site: "id" is required';
    }
    if (lat is! num || lng is! num) {
      return 'set_site: "lat" and "lng" are required numbers';
    }
    final site = <String, dynamic>{
      'id': id,
      'lat': lat.toDouble(),
      'lng': lng.toDouble(),
      if (args['name'] is String) 'name': args['name'],
      if (args['status'] is String) 'status': args['status'],
    };
    ctx.bus.update((current) {
      final next = Map<String, dynamic>.from(current);
      final ui = _mapAt(next, 'ui');
      final mapState = _mapAt(ui, 'map');
      final sites = List<Map<String, dynamic>>.from(
        (mapState['sites'] as List?)?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[],
      );
      final idx = sites.indexWhere((s) => s['id'] == id);
      if (idx >= 0) {
        sites[idx] = {...sites[idx], ...site};
      } else {
        sites.add(site);
      }
      mapState['sites'] = sites;
      ui['map'] = mapState;
      next['ui'] = ui;
      return next;
    });
    return jsonEncode({'ok': true, 'id': id});
  }

  Future<String> _executeClearSites(
    ToolCallInfo toolCall,
    ToolExecutionContext _,
  ) async {
    final ctx = _ctx;
    if (ctx == null) return 'clear_sites: plugin not attached';
    ctx.bus.update((current) {
      final next = Map<String, dynamic>.from(current);
      final ui = _mapAt(next, 'ui');
      final mapState = _mapAt(ui, 'map');
      mapState['sites'] = const <Map<String, dynamic>>[];
      ui['map'] = mapState;
      next['ui'] = ui;
      return next;
    });
    return jsonEncode({'ok': true});
  }

  Future<String> _executeMoveConvoyTo(
    ToolCallInfo toolCall,
    ToolExecutionContext _,
  ) async {
    final ctx = _ctx;
    if (ctx == null) return 'move_convoy_to: plugin not attached';
    final args = _decodeArgs(toolCall);
    final lat = args['lat'];
    final lng = args['lng'];
    if (lat is! num || lng is! num) {
      return 'move_convoy_to: "lat" and "lng" are required numbers';
    }
    final heading = args['heading'];
    final convoy = <String, dynamic>{
      'lat': lat.toDouble(),
      'lng': lng.toDouble(),
      if (heading is num) 'heading': heading.toDouble(),
    };
    ctx.bus.update((current) {
      final next = Map<String, dynamic>.from(current);
      final ui = _mapAt(next, 'ui');
      final mapState = _mapAt(ui, 'map');
      mapState['convoy'] = convoy;
      ui['map'] = mapState;
      next['ui'] = ui;
      return next;
    });
    return jsonEncode({'ok': true});
  }

  static Map<String, Object?> _decodeArgs(ToolCallInfo toolCall) {
    if (!toolCall.hasArguments) return const <String, Object?>{};
    final decoded = jsonDecode(toolCall.arguments);
    if (decoded is! Map) return const <String, Object?>{};
    return decoded.cast<String, Object?>();
  }

  static Map<String, dynamic> _mapAt(Map<String, dynamic> parent, String key) {
    return Map<String, dynamic>.from(
      (parent[key] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}
