import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
// ToolExecutionContext is not re-exported from soliplex_agent's public
// barrel; reach into src/ for the type annotation, mirroring
// MontyRuntimeExtension.
// ignore: implementation_imports
import 'package:soliplex_agent/src/tools/tool_execution_context.dart'
    show ToolExecutionContext;

import 'package:soliplex_agent_maps/src/map_state.dart';

/// Result of parsing a tool call's arguments.
///
/// Either a parsed JSON object (`_ArgsOk`) or an error JSON string
/// already encoded for direct return from a tool executor (`_ArgsErr`).
sealed class _ArgsResult {
  const _ArgsResult();
}

class _ArgsOk extends _ArgsResult {
  const _ArgsOk(this.value);
  final Map<String, Object?> value;
}

class _ArgsErr extends _ArgsResult {
  const _ArgsErr(this.encoded);
  final String encoded;
}

/// Unique id seed for auto-generated marker / polyline / polygon ids.
int _idSeed = 0;
String _autoId(String prefix) {
  _idSeed += 1;
  return '$prefix-${DateTime.now().millisecondsSinceEpoch}-$_idSeed';
}

/// Bridges a `MapController` into a soliplex [AgentSession].
///
/// Owns a long-lived `MapController` so the LLM-callable [ClientTool]s
/// can drive the camera, drop pins, and draw geometry on a `MapView`
/// that stays mounted across LLM turns.
///
/// The aggregated `state` map shape:
///
/// - `viewport` — `{lat, lng, zoom, rotation}` of the current camera.
/// - `markerCount` — number of markers currently on the map.
/// - `lastEvent` — short tag for the most recent change
///   (`move`, `zoom`, `rotate`, `add_marker`, `clear_markers`,
///   `add_polyline`, `add_polygon`, `set_basemap`, `tour`).
/// - `basemap` — current tile source id.
class MapExtension extends SessionExtension
    with StatefulSessionExtension<Map<String, Object?>> {
  MapExtension({
    Viewport initialViewport = const Viewport(
      lat: 0,
      lng: 0,
      zoom: 2,
      rotation: 0,
    ),
    BasemapStyle initialBasemap = BasemapStyle.osm,
    String userAgent = 'soliplex-agent-maps/0.1 (geocoding via Nominatim)',
    http.Client? httpClient,
  })  : _initialViewport = initialViewport,
        _userAgent = userAgent,
        _httpClient = httpClient ?? http.Client(),
        _basemap = signal(initialBasemap),
        _markers = signal(<MarkerData>[]),
        _polylines = signal(<PolylineData>[]),
        _polygons = signal(<PolygonData>[]),
        _viewport = signal(initialViewport) {
    setInitialState(_buildState(lastEvent: 'init'));
  }

  final Viewport _initialViewport;
  final String _userAgent;
  final http.Client _httpClient;

  final MapController _controller = MapController();

  // Inner reactive state — exposed to the widget; aggregated into
  // `state` for the public observation surface.
  final Signal<BasemapStyle> _basemap;
  final Signal<List<MarkerData>> _markers;
  final Signal<List<PolylineData>> _polylines;
  final Signal<List<PolygonData>> _polygons;
  final Signal<Viewport> _viewport;

  StreamSubscription<MapEvent>? _mapEventSub;
  DateTime _lastGeocodeAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Controller backing the `MapView` widget.
  MapController get controller => _controller;

  /// Inner signals — consumed by `MapView`. Public so consumers can
  /// build alternative UIs against the same state.
  ReadonlySignal<BasemapStyle> get basemap => _basemap.readonly();
  ReadonlySignal<List<MarkerData>> get markers => _markers.readonly();
  ReadonlySignal<List<PolylineData>> get polylines => _polylines.readonly();
  ReadonlySignal<List<PolygonData>> get polygons => _polygons.readonly();
  ReadonlySignal<Viewport> get viewport => _viewport.readonly();

  Viewport get initialViewport => _initialViewport;

  @override
  String get namespace => 'map';

  @override
  int get priority => 0;

  @override
  Future<void> onAttach(AgentSession session) async {
    // Idempotent — the same instance may attach to many sessions over
    // time when used as an app-level singleton. Cancel any prior
    // subscription before resubscribing to the controller's event
    // stream.
    await _mapEventSub?.cancel();
    _mapEventSub = _controller.mapEventStream.listen(_onMapEvent);
  }

  @override
  void onDispose() {
    // Cancel only the per-session subscription. Controllers, the HTTP
    // client, and inner signals are intentionally retained so the same
    // [MapExtension] instance can be reused across sessions (singleton
    // pattern in `lib/src/maps_singleton.dart`). The widget bound to
    // this controller stays alive across session boundaries.
    unawaited(_mapEventSub?.cancel());
    _mapEventSub = null;
    super.onDispose();
  }

  void _onMapEvent(MapEvent event) {
    final cam = event.camera;
    _viewport.value = Viewport(
      lat: cam.center.latitude,
      lng: cam.center.longitude,
      zoom: cam.zoom,
      rotation: cam.rotation,
    );
    final tag = switch (event) {
      MapEventMove() => 'move',
      MapEventMoveStart() => 'move',
      MapEventMoveEnd() => 'move',
      MapEventFlingAnimation() => 'move',
      MapEventDoubleTapZoom() => 'zoom',
      MapEventScrollWheelZoom() => 'zoom',
      MapEventRotate() => 'rotate',
      MapEventRotateStart() => 'rotate',
      MapEventRotateEnd() => 'rotate',
      _ => null,
    };
    if (tag != null) {
      _refreshState(lastEvent: tag);
    } else {
      _refreshState();
    }
  }

  void _refreshState({String? lastEvent}) {
    state = _buildState(
      lastEvent: lastEvent ?? (state['lastEvent'] as String?) ?? 'idle',
    );
  }

  Map<String, Object?> _buildState({required String lastEvent}) {
    final vp = _viewport.value;
    return <String, Object?>{
      'viewport': vp.toJson(),
      'markerCount': _markers.value.length,
      'polylineCount': _polylines.value.length,
      'polygonCount': _polygons.value.length,
      'basemap': _basemap.value.id,
      'lastEvent': lastEvent,
    };
  }

  // ---- Tools ------------------------------------------------------------

  @override
  List<ClientTool> get tools => [
        ClientTool.simple(
          name: 'set_map_view',
          description: 'Animates the map camera to a target latitude / '
              'longitude with optional zoom and rotation. Use this for '
              'cinematic transitions ("slow zoom to Tokyo over 4 seconds"). '
              'durationMs defaults to 800ms; pass a longer value for a '
              'dramatic fly-to. animated=false snaps instantly.',
          parameters: const {
            'type': 'object',
            'properties': {
              'lat': {'type': 'number'},
              'lng': {'type': 'number'},
              'zoom': {'type': 'number'},
              'rotation': {
                'type': 'number',
                'description': 'Bearing in degrees, clockwise from north.',
              },
              'animated': {'type': 'boolean'},
              'durationMs': {'type': 'integer'},
            },
            'required': ['lat', 'lng'],
          },
          executor: _setMapView,
        ),
        ClientTool.simple(
          name: 'get_map_view',
          description: 'Returns the current viewport as '
              '{lat, lng, zoom, rotation}.',
          executor: _getMapView,
        ),
        ClientTool.simple(
          name: 'add_marker',
          description: 'Drops a pin on the map at lat/lng. Returns the '
              'auto-generated marker id which can be passed to '
              'pulse_marker to draw attention later. Pins drop with a '
              'short bounce animation by default.',
          parameters: const {
            'type': 'object',
            'properties': {
              'lat': {'type': 'number'},
              'lng': {'type': 'number'},
              'label': {'type': 'string'},
              'color': {
                'type': 'string',
                'description': 'CSS hex color (e.g. "#FF0000") or named '
                    'color (red, blue, green, orange, purple).',
              },
              'icon': {
                'type': 'string',
                'description': 'Material icon name — one of "place", '
                    '"flag", "star", "home", "restaurant", "hotel", '
                    '"local_cafe", "directions_walk".',
              },
              'dropAnimation': {'type': 'boolean'},
            },
            'required': ['lat', 'lng'],
          },
          executor: _addMarker,
        ),
        ClientTool.simple(
          name: 'clear_markers',
          description: 'Removes every marker, polyline, and polygon from '
              'the map.',
          executor: _clearMarkers,
        ),
        ClientTool.simple(
          name: 'add_polyline',
          description: 'Draws a polyline through the given points. Set '
              'animated=true to progressively draw the line over '
              'durationMs (defaults 1500). Useful for routes, paths, and '
              'tracing journeys.',
          parameters: const {
            'type': 'object',
            'properties': {
              'points': {
                'type': 'array',
                'items': {
                  'type': 'array',
                  'items': {'type': 'number'},
                  'minItems': 2,
                  'maxItems': 2,
                },
                'description': 'List of [lat, lng] pairs.',
              },
              'color': {'type': 'string'},
              'width': {'type': 'number'},
              'animated': {'type': 'boolean'},
              'durationMs': {'type': 'integer'},
            },
            'required': ['points'],
          },
          executor: _addPolyline,
        ),
        ClientTool.simple(
          name: 'add_polygon',
          description: 'Draws a filled polygon. Useful for highlighting '
              'regions, neighborhoods, or service areas.',
          parameters: const {
            'type': 'object',
            'properties': {
              'points': {
                'type': 'array',
                'items': {
                  'type': 'array',
                  'items': {'type': 'number'},
                  'minItems': 2,
                  'maxItems': 2,
                },
              },
              'fillColor': {'type': 'string'},
              'strokeColor': {'type': 'string'},
              'strokeWidth': {'type': 'number'},
            },
            'required': ['points'],
          },
          executor: _addPolygon,
        ),
        ClientTool.simple(
          name: 'fit_bounds_to_markers',
          description: 'Animates the camera to fit every marker on screen.',
          parameters: const {
            'type': 'object',
            'properties': {
              'padding': {
                'type': 'number',
                'description': 'Padding in logical pixels.',
              },
            },
          },
          executor: _fitBoundsToMarkers,
        ),
        ClientTool.simple(
          name: 'pulse_marker',
          description: 'Toggles a pulsing halo on a marker by id to draw '
              "the user's attention.",
          parameters: const {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
              'pulse': {'type': 'boolean'},
            },
            'required': ['id'],
          },
          executor: _pulseMarker,
        ),
        ClientTool.simple(
          name: 'set_basemap',
          description: 'Switches the tile source. Options: '
              '"osm" (default OSM), "topo" (terrain), "cartodb_positron" '
              '(minimal light), "cartodb_dark" (dark theme).',
          parameters: const {
            'type': 'object',
            'properties': {
              'style': {
                'type': 'string',
                'enum': ['osm', 'topo', 'cartodb_positron', 'cartodb_dark'],
              },
            },
            'required': ['style'],
          },
          executor: _setBasemap,
        ),
        ClientTool.simple(
          name: 'geocode',
          description: 'Resolves a free-form place name to lat/lng via '
              "OpenStreetMap's Nominatim service. Returns "
              '{lat, lng, displayName}. Rate-limited to 1 req/sec per '
              "Nominatim's ToS. Some networks block Nominatim; the tool "
              'returns an error payload in that case so the model can '
              'recover gracefully.',
          parameters: const {
            'type': 'object',
            'properties': {
              'query': {'type': 'string'},
            },
            'required': ['query'],
          },
          executor: _geocode,
        ),
        ClientTool.simple(
          name: 'tour',
          description: 'Performs a guided cinematic tour: flies between a '
              'sequence of stops, dwelling at each for the given dwellMs, '
              'and dropping a labelled marker on arrival. The single most '
              'demo-friendly tool — call it once and the map performs the '
              'whole show.',
          parameters: const {
            'type': 'object',
            'properties': {
              'stops': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'lat': {'type': 'number'},
                    'lng': {'type': 'number'},
                    'label': {'type': 'string'},
                    'zoom': {'type': 'number'},
                    'dwellMs': {'type': 'integer'},
                    'flyMs': {'type': 'integer'},
                  },
                  'required': ['lat', 'lng'],
                },
              },
              'connectStops': {
                'type': 'boolean',
                'description': 'When true, draws a polyline through each '
                    'stop after the tour completes.',
              },
            },
            'required': ['stops'],
          },
          executor: _tour,
        ),
      ];

  // ---- Tool executors ---------------------------------------------------

  Future<String> _setMapView(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    final parsed = _parseArgs(toolCall);
    if (parsed is _ArgsErr) return parsed.encoded;
    final args = (parsed as _ArgsOk).value;
    final lat = _asDouble(args, 'lat');
    final lng = _asDouble(args, 'lng');
    if (lat == null || lng == null) {
      return _err('set_map_view', '"lat" and "lng" are required numbers');
    }
    final zoom = _asDouble(args, 'zoom');
    final rotation = _asDouble(args, 'rotation');
    final animated = (args['animated'] as bool?) ?? true;
    final durationMs = _asInt(args, 'durationMs') ?? 800;

    final target = LatLng(lat, lng);
    final targetZoom = zoom ?? _viewport.value.zoom;
    final targetRot = rotation ?? _viewport.value.rotation;

    if (!animated || durationMs <= 0) {
      _controller.moveAndRotate(target, targetZoom, targetRot);
    } else {
      await _animateCamera(
        target: target,
        targetZoom: targetZoom,
        targetRotation: targetRot,
        durationMs: durationMs,
      );
    }
    _refreshState(lastEvent: 'move');
    return jsonEncode({'ok': true, 'viewport': _viewport.value.toJson()});
  }

  Future<String> _getMapView(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    return jsonEncode({'viewport': _viewport.value.toJson()});
  }

  Future<String> _addMarker(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    final parsed = _parseArgs(toolCall);
    if (parsed is _ArgsErr) return parsed.encoded;
    final args = (parsed as _ArgsOk).value;
    final lat = _asDouble(args, 'lat');
    final lng = _asDouble(args, 'lng');
    if (lat == null || lng == null) {
      return _err('add_marker', '"lat" and "lng" are required numbers');
    }
    final marker = MarkerData(
      id: _autoId('marker'),
      lat: lat,
      lng: lng,
      label: args['label'] as String?,
      color: args['color'] as String?,
      icon: args['icon'] as String?,
      dropAnimation: (args['dropAnimation'] as bool?) ?? true,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _markers.value = [..._markers.value, marker];
    _refreshState(lastEvent: 'add_marker');
    return jsonEncode({'ok': true, 'id': marker.id});
  }

  Future<String> _clearMarkers(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    _markers.value = const [];
    _polylines.value = const [];
    _polygons.value = const [];
    _refreshState(lastEvent: 'clear_markers');
    return jsonEncode({'ok': true});
  }

  Future<String> _addPolyline(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    final parsed = _parseArgs(toolCall);
    if (parsed is _ArgsErr) return parsed.encoded;
    final args = (parsed as _ArgsOk).value;
    final pts = _parsePoints(args['points']);
    if (pts == null || pts.length < 2) {
      return _err(
        'add_polyline',
        '"points" must be a list of at least 2 [lat,lng] pairs',
      );
    }
    final id = _autoId('polyline');
    final animated = (args['animated'] as bool?) ?? false;
    final line = PolylineData(
      id: id,
      points: pts,
      color: args['color'] as String?,
      width: _asDouble(args, 'width') ?? 4,
      animated: animated,
      progress: animated ? 0 : 1,
    );
    _polylines.value = [..._polylines.value, line];
    _refreshState(lastEvent: 'add_polyline');
    if (animated) {
      final durationMs = _asInt(args, 'durationMs') ?? 1500;
      unawaited(_animatePolyline(id, durationMs));
    }
    return jsonEncode({'ok': true, 'id': id});
  }

  Future<String> _addPolygon(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    final parsed = _parseArgs(toolCall);
    if (parsed is _ArgsErr) return parsed.encoded;
    final args = (parsed as _ArgsOk).value;
    final pts = _parsePoints(args['points']);
    if (pts == null || pts.length < 3) {
      return _err(
        'add_polygon',
        '"points" must be a list of at least 3 [lat,lng] pairs',
      );
    }
    final poly = PolygonData(
      id: _autoId('polygon'),
      points: pts,
      fillColor: args['fillColor'] as String?,
      strokeColor: args['strokeColor'] as String?,
      strokeWidth: _asDouble(args, 'strokeWidth') ?? 2,
    );
    _polygons.value = [..._polygons.value, poly];
    _refreshState(lastEvent: 'add_polygon');
    return jsonEncode({'ok': true, 'id': poly.id});
  }

  Future<String> _fitBoundsToMarkers(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    final parsed = _parseArgs(toolCall);
    if (parsed is _ArgsErr) return parsed.encoded;
    final args = (parsed as _ArgsOk).value;
    if (_markers.value.isEmpty) {
      return _err('fit_bounds_to_markers', 'no markers to fit');
    }
    final padding = _asDouble(args, 'padding') ?? 48;
    final pts =
        _markers.value.map((m) => LatLng(m.lat, m.lng)).toList(growable: false);
    final bounds = LatLngBounds.fromPoints(pts);
    _controller.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: EdgeInsets.all(padding),
      ),
    );
    _refreshState(lastEvent: 'move');
    return jsonEncode({'ok': true});
  }

  Future<String> _pulseMarker(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    final parsed = _parseArgs(toolCall);
    if (parsed is _ArgsErr) return parsed.encoded;
    final args = (parsed as _ArgsOk).value;
    final id = args['id'] as String?;
    if (id == null) return _err('pulse_marker', '"id" is required');
    final pulse = (args['pulse'] as bool?) ?? true;
    final list = _markers.value;
    final idx = list.indexWhere((m) => m.id == id);
    if (idx < 0) {
      return _err('pulse_marker', 'no marker with id="$id"');
    }
    final updated = [...list];
    updated[idx] = list[idx].copyWith(pulse: pulse);
    _markers.value = updated;
    _refreshState(lastEvent: 'pulse_marker');
    return jsonEncode({'ok': true});
  }

  Future<String> _setBasemap(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    final parsed = _parseArgs(toolCall);
    if (parsed is _ArgsErr) return parsed.encoded;
    final args = (parsed as _ArgsOk).value;
    final raw = args['style'] as String?;
    if (raw == null) return _err('set_basemap', '"style" is required');
    final style = BasemapStyle.parse(raw);
    if (style == null) {
      return _err('set_basemap', 'unknown style "$raw"');
    }
    _basemap.value = style;
    _refreshState(lastEvent: 'set_basemap');
    return jsonEncode({'ok': true, 'style': style.id});
  }

  Future<String> _geocode(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    final parsed = _parseArgs(toolCall);
    if (parsed is _ArgsErr) return parsed.encoded;
    final args = (parsed as _ArgsOk).value;
    final query = args['query'] as String?;
    if (query == null || query.isEmpty) {
      return _err('geocode', '"query" is required');
    }

    // 1 req/sec per Nominatim ToS.
    final now = DateTime.now();
    final since = now.difference(_lastGeocodeAt);
    if (since < const Duration(seconds: 1)) {
      await Future<void>.delayed(const Duration(seconds: 1) - since);
    }
    _lastGeocodeAt = DateTime.now();

    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      {
        'q': query,
        'format': 'json',
        'limit': '1',
      },
    );
    try {
      final headers = <String, String>{'User-Agent': _userAgent};
      final res = await _httpClient
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        return _err('geocode', 'HTTP ${res.statusCode}');
      }
      final body = jsonDecode(res.body);
      if (body is! List || body.isEmpty) {
        return _err('geocode', 'no results for "$query"');
      }
      final first = body.first as Map<String, Object?>;
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lng = double.tryParse(first['lon']?.toString() ?? '');
      final displayName = first['display_name']?.toString();
      if (lat == null || lng == null) {
        return _err('geocode', 'malformed response');
      }
      return jsonEncode({
        'lat': lat,
        'lng': lng,
        if (displayName != null) 'displayName': displayName,
      });
    } on Object catch (e) {
      return _err('geocode', '$e');
    }
  }

  Future<String> _tour(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    final parsed = _parseArgs(toolCall);
    if (parsed is _ArgsErr) return parsed.encoded;
    final args = (parsed as _ArgsOk).value;
    final stopsRaw = args['stops'];
    if (stopsRaw is! List || stopsRaw.isEmpty) {
      return _err('tour', '"stops" must be a non-empty array');
    }
    final tourStart = DateTime.now().millisecondsSinceEpoch;
    final droppedIds = <String>[];
    final pathPoints = <LatLng>[];

    for (final raw in stopsRaw) {
      if (raw is! Map) continue;
      final stop = raw.cast<String, Object?>();
      final lat = _asDouble(stop, 'lat');
      final lng = _asDouble(stop, 'lng');
      if (lat == null || lng == null) continue;
      final zoom = _asDouble(stop, 'zoom') ?? 8;
      final flyMs = _asInt(stop, 'flyMs') ?? 1200;
      final dwellMs = _asInt(stop, 'dwellMs') ?? 800;
      final label = stop['label'] as String?;
      pathPoints.add(LatLng(lat, lng));

      await _animateCamera(
        target: LatLng(lat, lng),
        targetZoom: zoom,
        targetRotation: _viewport.value.rotation,
        durationMs: flyMs,
      );

      final marker = MarkerData(
        id: _autoId('marker'),
        lat: lat,
        lng: lng,
        label: label,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      _markers.value = [..._markers.value, marker];
      droppedIds.add(marker.id);
      _refreshState(lastEvent: 'tour');

      if (dwellMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: dwellMs));
      }
    }

    final connectStops = (args['connectStops'] as bool?) ?? false;
    String? polylineId;
    if (connectStops && pathPoints.length >= 2) {
      polylineId = _autoId('polyline');
      _polylines.value = [
        ..._polylines.value,
        PolylineData(
          id: polylineId,
          points: pathPoints,
          color: '#FF6B35',
        ),
      ];
      _refreshState(lastEvent: 'tour');
    }

    return jsonEncode({
      'ok': true,
      'durationMs': DateTime.now().millisecondsSinceEpoch - tourStart,
      'markerIds': droppedIds,
      if (polylineId != null) 'polylineId': polylineId,
    });
  }

  // ---- Public typed API -------------------------------------------------
  //
  // These mirror the ClientTool surface but take typed Dart arguments so
  // other consumers (e.g. the Monty externals layer in
  // `MapMontyExtension`) can drive the same map state without going via
  // JSON-encoded `ToolCallInfo` round-trips. The `ClientTool` executors
  // above keep their inline arg-parsing for now; see
  // `docs/plans/message-containers.md` for the v1 refactor that
  // collapses both call paths onto these methods.

  /// Imperative camera move. When [animated] is true, performs an
  /// eased tween over [durationMs]; otherwise jumps. Updates the
  /// reactive viewport signal as a side effect (via
  /// `_controller.mapEventStream`).
  Future<void> flyTo({
    required double lat,
    required double lng,
    double? zoom,
    double? rotation,
    bool animated = true,
    int durationMs = 800,
  }) async {
    final target = LatLng(lat, lng);
    final targetZoom = zoom ?? _viewport.value.zoom;
    final targetRot = rotation ?? _viewport.value.rotation;
    if (!animated || durationMs <= 0) {
      try {
        _controller.moveAndRotate(target, targetZoom, targetRot);
      } on Object catch (_) {
        // Widget not laid out yet — drop the call rather than throwing.
      }
    } else {
      await _animateCamera(
        target: target,
        targetZoom: targetZoom,
        targetRotation: targetRot,
        durationMs: durationMs,
      );
    }
    _refreshState(lastEvent: 'move');
  }

  /// Drops a marker and returns its generated id.
  String addMarker({
    required double lat,
    required double lng,
    String? label,
    String? color,
    String? icon,
    bool dropAnimation = true,
    bool pulse = false,
  }) {
    final marker = MarkerData(
      id: _autoId('marker'),
      lat: lat,
      lng: lng,
      label: label,
      color: color,
      icon: icon,
      dropAnimation: dropAnimation,
      pulse: pulse,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _markers.value = [..._markers.value, marker];
    _refreshState(lastEvent: 'add_marker');
    return marker.id;
  }

  /// Removes every marker, polyline, and polygon. Mirrors the
  /// `clear_markers` ClientTool semantics.
  void clearAll() {
    _markers.value = const [];
    _polylines.value = const [];
    _polygons.value = const [];
    _refreshState(lastEvent: 'clear_markers');
  }

  /// Switches the visible tile layer. Returns false if [name] does not
  /// resolve to a known [BasemapStyle].
  bool setBasemapStyle(String name) {
    final style = BasemapStyle.parse(name);
    if (style == null) return false;
    _basemap.value = style;
    _refreshState(lastEvent: 'set_basemap');
    return true;
  }

  /// JSON-friendly snapshot of the current viewport.
  Map<String, Object?> viewportJson() => _viewport.value.toJson();

  // ---- Helpers ----------------------------------------------------------

  /// Manually animates the camera. flutter_map 8 ships [MapController.move]
  /// (instant) — we drive a tween in-process so animation duration is
  /// LLM-controllable.
  Future<void> _animateCamera({
    required LatLng target,
    required double targetZoom,
    required double targetRotation,
    required int durationMs,
  }) async {
    final start = _viewport.value;
    final steps = (durationMs / 16).clamp(1, 240).toInt();
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      // Ease-in-out cubic.
      final eased = t < 0.5
          ? 4 * t * t * t
          : 1 - ((-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2)) / 2;
      final lat = start.lat + (target.latitude - start.lat) * eased;
      final lng = start.lng + (target.longitude - start.lng) * eased;
      final zoom = start.zoom + (targetZoom - start.zoom) * eased;
      final rot = start.rotation + (targetRotation - start.rotation) * eased;
      try {
        _controller.moveAndRotate(LatLng(lat, lng), zoom, rot);
      } on Object catch (_) {
        // MapController throws if the widget hasn't laid out yet — skip.
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _animatePolyline(String id, int durationMs) async {
    final steps = (durationMs / 16).clamp(1, 240).toInt();
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final list = _polylines.value;
      final idx = list.indexWhere((p) => p.id == id);
      if (idx < 0) return;
      final updated = [...list];
      updated[idx] = list[idx].copyWith(progress: t);
      _polylines.value = updated;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  _ArgsResult _parseArgs(ToolCallInfo toolCall) {
    if (toolCall.arguments.isEmpty) {
      return const _ArgsOk(<String, Object?>{});
    }
    try {
      final parsed = jsonDecode(toolCall.arguments);
      if (parsed is! Map) {
        return _ArgsErr(_err(toolCall.name, 'arguments must be a JSON object'));
      }
      return _ArgsOk(parsed.cast<String, Object?>());
    } on Object catch (e) {
      return _ArgsErr(_err(toolCall.name, 'failed to parse arguments: $e'));
    }
  }

  static String _err(String tool, String reason) =>
      jsonEncode({'error': '$tool: $reason'});

  static double? _asDouble(Map<String, Object?> args, String key) {
    final v = args[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _asInt(Map<String, Object?> args, String key) {
    final v = args[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static List<LatLng>? _parsePoints(Object? raw) {
    if (raw is! List) return null;
    final out = <LatLng>[];
    for (final item in raw) {
      if (item is! List || item.length < 2) return null;
      final lat = item[0];
      final lng = item[1];
      if (lat is! num || lng is! num) return null;
      out.add(LatLng(lat.toDouble(), lng.toDouble()));
    }
    return out;
  }

  // Allow tests / debug tools to peek at this without exposing it broadly.
  @visibleForTesting
  Map<String, Object?> debugStateSnapshot() => Map.of(state);
}
