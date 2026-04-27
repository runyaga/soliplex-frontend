import 'dart:convert';

import 'package:soliplex_agent/soliplex_agent.dart';

/// A [SessionExtension] exposing bus-write map operations on two
/// surfaces: LLM `tools` and Python `hostFunctions`.
///
/// All three operations — `set_site`, `clear_sites`, `move_convoy_to` —
/// are declared on both surfaces and delegate to the same private
/// helpers, so the LLM-driven path and the Python-driven path mutate
/// the bus identically.
///
/// The bus paths used here are the same the existing projections in
/// `map_projections.dart` already read:
///
/// - `set_site` / `clear_sites` → `/ui/map/sites` (read by
///   `MapMarkersProjection`)
/// - `move_convoy_to` → `/ui/map/convoy` (read by
///   `MapSpritesProjection`)
///
/// So bus-write tools feed the same render pipeline AG-UI server
/// state events feed today, with no projection changes required.
///
/// The bridge in `soliplex_agent_monty` (Phase 2 step 9) synthesizes
/// a `MontyExtension` from [hostFunctions] automatically — this
/// package stays `dart_monty`-free.
///
/// `MapMontyExtension` (the legacy singleton-driving Python bridge for
/// `map_fly_to` / `map_add_marker` / etc.) is unchanged and still
/// registered separately. Phase 2 cleanup retires it.
///
/// Plan reference: `docs/plans/reactive-bus-redesign.md` (Phase 1 step 5
/// + Phase 2 step 10).
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

  // hostFunctions intentionally NOT declared here.
  //
  // Phase 2 step 10b initially exposed `set_site` / `clear_sites` /
  // `move_convoy_to` as host functions, but dart_monty enforces a
  // namespace-prefix rule (function name must start with
  // `${namespace}_`) that the plugin's namespace `'map_plugin'`
  // doesn't satisfy. Renaming to `map_plugin_set_site` etc. would
  // break the public Python API; renaming the namespace to `map`
  // collides with the legacy `MapMontyExtension`.
  //
  // Map plugin is in maintenance-only mode (per user direction);
  // the LLM tool path on this plugin keeps working — only the
  // never-yet-used Python bridge path is removed. The proper fix
  // belongs in the bridge layer (allow plugin authors to declare a
  // separate `montyNamespace` or strip the prefix check for
  // synthesized extensions).

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
    final rawName = args['name'];
    final rawStatus = args['status'];
    _setSite(
      ctx,
      id: id,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      name: rawName is String ? rawName : null,
      status: rawStatus is String ? rawStatus : null,
    );
    return jsonEncode({'ok': true, 'id': id});
  }

  Future<String> _executeClearSites(
    ToolCallInfo toolCall,
    ToolExecutionContext _,
  ) async {
    final ctx = _ctx;
    if (ctx == null) return 'clear_sites: plugin not attached';
    _clearSites(ctx);
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
    _moveConvoyTo(
      ctx,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      heading: heading is num ? heading.toDouble() : null,
    );
    return jsonEncode({'ok': true});
  }

  void _setSite(
    SessionContext ctx, {
    required String id,
    required double lat,
    required double lng,
    String? name,
    String? status,
  }) {
    final site = <String, dynamic>{
      'id': id,
      'lat': lat,
      'lng': lng,
      if (name != null) 'name': name,
      if (status != null) 'status': status,
    };
    ctx.bus.update(
      (current) {
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
      },
      tag: 'map.set_site',
    );
  }

  void _clearSites(SessionContext ctx) {
    ctx.bus.update(
      (current) {
        final next = Map<String, dynamic>.from(current);
        final ui = _mapAt(next, 'ui');
        final mapState = _mapAt(ui, 'map');
        mapState['sites'] = const <Map<String, dynamic>>[];
        ui['map'] = mapState;
        next['ui'] = ui;
        return next;
      },
      tag: 'map.clear_sites',
    );
  }

  void _moveConvoyTo(
    SessionContext ctx, {
    required double lat,
    required double lng,
    double? heading,
  }) {
    final convoy = <String, dynamic>{
      'lat': lat,
      'lng': lng,
      if (heading != null) 'heading': heading,
    };
    ctx.bus.update(
      (current) {
        final next = Map<String, dynamic>.from(current);
        final ui = _mapAt(next, 'ui');
        final mapState = _mapAt(ui, 'map');
        mapState['convoy'] = convoy;
        ui['map'] = mapState;
        next['ui'] = ui;
        return next;
      },
      tag: 'map.move_convoy_to',
    );
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
