// HostFunction wraps a closure that captures `_maps`, so the outer
// constructor can't be const. The redundant-arg warnings flag explicit
// `params: const []` and `isRequired: false`, both of which improve
// readability at the cost of matching defaults.
// ignore_for_file: prefer_const_constructors, avoid_redundant_argument_values

import 'dart:async';
import 'dart:convert';

import 'package:dart_monty/dart_monty_bridge.dart'
    show
        HostFunction,
        HostFunctionSchema,
        HostParam,
        HostParamType,
        MontyExtension;
import 'package:http/http.dart' as http;

import 'package:soliplex_agent_maps/src/map_extension.dart';

/// Bridges the singleton [MapExtension] into a `dart_monty` runtime so
/// Python scripts (run via `run_python_on_device`) can drive the same
/// live map the LLM-callable `ClientTool`s drive.
///
/// Register inside the `MontyExtensionSet` you pass to
/// `MontyRuntimeExtension`:
///
/// ```dart
/// MontyRuntimeExtension(
///   extensions: MontyExtensionSet([
///     ...MontyExtensionSet.standard().all,
///     MapMontyExtension(mapExtension),
///   ]),
/// );
/// ```
///
/// Python calls the externals using the `<namespace>_<fn>` prefix
/// convention dart_monty enforces (see
/// `ExtensionCoordinator._checkFunctionCollisions`):
///
/// ```python
/// monty.map_fly_to(40.7128, -74.0060, zoom=12)
/// pin = monty.map_add_marker(40.7128, -74.0060, label="NYC")
/// vp = monty.map_get_view()
/// monty.map_set_basemap("cartodb_dark")
/// monty.map_clear_markers()
/// ```
///
/// This is the v0 of the Monty bridge described in
/// `docs/plans/message-containers.md`. It exposes a deliberately small
/// surface — fly_to, add_marker, clear_markers, set_basemap, get_view —
/// matching what a useful tour script needs. v1 will mirror the full
/// ClientTool surface (polylines, polygons, geocoding, tour) and add
/// signal-based subscriptions.
class MapMontyExtension extends MontyExtension {
  MapMontyExtension(this._maps, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final MapExtension _maps;
  final http.Client _http;

  /// Per Nominatim's usage policy: identify yourself, throttle to <=1 req/s.
  /// We don't enforce the throttle here — Python scripts that batch should
  /// add `map_sleep_ms(1000)` between calls.
  static const _nominatimUserAgent = 'soliplex-frontend (dev)';
  static const _nominatimBase = 'https://nominatim.openstreetmap.org';

  @override
  Future<void> onDispose() async {
    _http.close();
    await super.onDispose();
  }

  @override
  String get namespace => 'map';

  @override
  String? get systemPromptContext =>
      'Externals to drive the chat-side flutter_map widget: '
      'monty.map_fly_to(lat, lng, zoom?, rotation?, animated?, '
      'duration_ms?), monty.map_add_marker(lat, lng, label?, color?, '
      'icon?, pulse?) -> id, monty.map_clear_markers(), '
      'monty.map_set_basemap(style), monty.map_get_view() -> '
      "{lat, lng, zoom, rotation}. The same widget the LLM's map "
      'tools drive — tool calls and Python scripts share state.';

  @override
  List<HostFunction> get functions => [
        HostFunction(
          schema: HostFunctionSchema(
            name: 'map_fly_to',
            description:
                'Move the map camera to (lat, lng), optionally setting '
                'zoom and rotation, animating over duration_ms.',
            params: const [
              HostParam(
                name: 'lat',
                type: HostParamType.number,
                description: 'Latitude in decimal degrees.',
              ),
              HostParam(
                name: 'lng',
                type: HostParamType.number,
                description: 'Longitude in decimal degrees.',
              ),
              HostParam(
                name: 'zoom',
                type: HostParamType.number,
                isRequired: false,
                description: 'Target zoom 1..19.',
              ),
              HostParam(
                name: 'rotation',
                type: HostParamType.number,
                isRequired: false,
                description: 'Bearing in degrees, 0=north.',
              ),
              HostParam(
                name: 'animated',
                type: HostParamType.boolean,
                isRequired: false,
                defaultValue: true,
              ),
              HostParam(
                name: 'duration_ms',
                type: HostParamType.integer,
                isRequired: false,
                defaultValue: 800,
              ),
            ],
          ),
          handler: (args, ctx) async {
            await _maps.flyTo(
              lat: (args['lat']! as num).toDouble(),
              lng: (args['lng']! as num).toDouble(),
              zoom: (args['zoom'] as num?)?.toDouble(),
              rotation: (args['rotation'] as num?)?.toDouble(),
              animated: (args['animated'] as bool?) ?? true,
              durationMs: (args['duration_ms'] as int?) ?? 800,
            );
            return _maps.viewportJson();
          },
        ),
        HostFunction(
          schema: HostFunctionSchema(
            name: 'map_add_marker',
            description: 'Drop a pin at (lat, lng). Returns the marker id.',
            params: const [
              HostParam(name: 'lat', type: HostParamType.number),
              HostParam(name: 'lng', type: HostParamType.number),
              HostParam(
                name: 'label',
                type: HostParamType.string,
                isRequired: false,
              ),
              HostParam(
                name: 'color',
                type: HostParamType.string,
                isRequired: false,
                description:
                    'Named (red/blue/green/...) or hex (#RRGGBB / #AARRGGBB).',
              ),
              HostParam(
                name: 'icon',
                type: HostParamType.string,
                isRequired: false,
                description:
                    'place | flag | star | home | restaurant | hotel | '
                    'local_cafe | directions_walk',
              ),
              HostParam(
                name: 'pulse',
                type: HostParamType.boolean,
                isRequired: false,
                defaultValue: false,
              ),
              HostParam(
                name: 'focus_zoom',
                type: HostParamType.number,
                isRequired: false,
                description:
                    'When set, fly to the marker at this zoom level if '
                    'the current zoom is less. Use 12-14 for "drop a '
                    'pin and snap to it" UX without a separate fly_to.',
              ),
            ],
          ),
          handler: (args, ctx) => _maps.addMarker(
            lat: (args['lat']! as num).toDouble(),
            lng: (args['lng']! as num).toDouble(),
            label: args['label'] as String?,
            color: args['color'] as String?,
            icon: args['icon'] as String?,
            pulse: (args['pulse'] as bool?) ?? false,
            focusZoom: (args['focus_zoom'] as num?)?.toDouble(),
          ),
        ),
        HostFunction(
          schema: HostFunctionSchema(
            name: 'map_add_path',
            description:
                'Draw a polyline/path from a list of [lat, lng] points. '
                'When animated=True, the line reveals itself over '
                'duration_ms — useful for tour traces, flight paths, '
                'route playbacks. Returns the path id.',
            params: const [
              HostParam(
                name: 'points',
                type: HostParamType.list,
                description: 'List of [lat, lng] pairs.',
              ),
              HostParam(
                name: 'color',
                type: HostParamType.string,
                isRequired: false,
                description:
                    'Named color (red/blue/orange/...) or #RRGGBB hex.',
              ),
              HostParam(
                name: 'width',
                type: HostParamType.number,
                isRequired: false,
                defaultValue: 4,
              ),
              HostParam(
                name: 'animated',
                type: HostParamType.boolean,
                isRequired: false,
                defaultValue: true,
                description:
                    'When true, reveal the line gradually over duration_ms.',
              ),
              HostParam(
                name: 'duration_ms',
                type: HostParamType.integer,
                isRequired: false,
                defaultValue: 1500,
              ),
            ],
          ),
          handler: (args, ctx) async {
            final raw = args['points'];
            if (raw is! List) {
              throw FormatException(
                'map_add_path: "points" must be a list of [lat, lng] pairs',
              );
            }
            final pts = <List<num>>[];
            for (final p in raw) {
              if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
                pts.add([p[0] as num, p[1] as num]);
              }
            }
            return _maps.addPolyline(
              points: pts,
              color: args['color'] as String?,
              width: (args['width'] as num?)?.toDouble() ?? 4,
              animated: (args['animated'] as bool?) ?? true,
              animationDurationMs: (args['duration_ms'] as num?)?.toInt(),
            );
          },
        ),
        HostFunction(
          schema: HostFunctionSchema(
            name: 'map_geocode',
            description:
                'Look up a place name and return its coordinates. Uses '
                'Nominatim (OpenStreetMap). When `limit` is 1 (default) '
                'returns a single dict {lat, lng, display_name, type, '
                'importance, bbox: [south, west, north, east]} or null '
                'if no match. When `limit` > 1 returns a list of dicts '
                "(top match first). Be polite — don't loop without "
                '`map_sleep_ms(1000)` between calls; Nominatim caps at '
                '~1 req/sec for the public instance.',
            params: const [
              HostParam(
                name: 'query',
                type: HostParamType.string,
                description: 'Free-text place name (e.g. "Tokyo", '
                    '"123 Main St, Springfield, IL", "Eiffel Tower").',
              ),
              HostParam(
                name: 'limit',
                type: HostParamType.integer,
                isRequired: false,
                defaultValue: 1,
                description: 'Max results. 1 returns a single dict, '
                    '>1 returns a list.',
              ),
            ],
          ),
          handler: (args, ctx) async {
            final query = args['query']! as String;
            final limit = (args['limit'] as num?)?.toInt() ?? 1;
            final uri = Uri.parse('$_nominatimBase/search').replace(
              queryParameters: {
                'q': query,
                'format': 'json',
                'limit': '$limit',
                'addressdetails': '0',
              },
            );
            final res = await _http
                .get(uri, headers: {'User-Agent': _nominatimUserAgent})
                .timeout(const Duration(seconds: 15));
            if (res.statusCode != 200) {
              throw FormatException(
                'map_geocode: ${res.statusCode} ${res.reasonPhrase}',
              );
            }
            final raw = jsonDecode(res.body);
            if (raw is! List) return limit == 1 ? null : <Object?>[];
            final results = [
              for (final item in raw)
                if (item is Map) _formatGeocodeResult(item),
            ];
            if (limit == 1) {
              return results.isEmpty ? null : results.first;
            }
            return results;
          },
        ),
        HostFunction(
          schema: HostFunctionSchema(
            name: 'map_reverse_geocode',
            description:
                'Look up the address at given coordinates. Returns a '
                'dict {display_name, address: {country, state, city, '
                'road, ...}, lat, lng} or null if no match. Same '
                'Nominatim throttle: 1 req/sec.',
            params: const [
              HostParam(name: 'lat', type: HostParamType.number),
              HostParam(name: 'lng', type: HostParamType.number),
            ],
          ),
          handler: (args, ctx) async {
            final lat = (args['lat']! as num).toDouble();
            final lng = (args['lng']! as num).toDouble();
            final uri = Uri.parse('$_nominatimBase/reverse').replace(
              queryParameters: {
                'lat': '$lat',
                'lon': '$lng',
                'format': 'json',
                'addressdetails': '1',
              },
            );
            final res = await _http
                .get(uri, headers: {'User-Agent': _nominatimUserAgent})
                .timeout(const Duration(seconds: 15));
            if (res.statusCode != 200) {
              throw FormatException(
                'map_reverse_geocode: ${res.statusCode} ${res.reasonPhrase}',
              );
            }
            final raw = jsonDecode(res.body);
            if (raw is! Map) return null;
            // Nominatim returns {"error": "..."} on miss.
            if (raw.containsKey('error')) return null;
            return {
              'lat': double.tryParse(raw['lat']?.toString() ?? '') ?? lat,
              'lng': double.tryParse(raw['lon']?.toString() ?? '') ?? lng,
              'display_name': raw['display_name'],
              'address': raw['address'] ?? <String, Object?>{},
              'place_id': raw['place_id'],
              'type': raw['type'],
            };
          },
        ),
        HostFunction(
          schema: HostFunctionSchema(
            name: 'map_move_marker',
            description:
                'Animate an existing marker from its current position '
                'to a new (lat, lng) over duration_ms. Returns True on '
                'success, False if the marker id was not found. Useful '
                'for moving vehicles, helicopter sprites, or a tour '
                'cursor that follows a path. Re-entrant: a newer move '
                'on the same id supersedes any in-flight one.',
            params: const [
              HostParam(
                name: 'id',
                type: HostParamType.string,
                description:
                    'Marker id returned by map_add_marker.',
              ),
              HostParam(name: 'lat', type: HostParamType.number),
              HostParam(name: 'lng', type: HostParamType.number),
              HostParam(
                name: 'duration_ms',
                type: HostParamType.integer,
                isRequired: false,
                defaultValue: 1500,
              ),
            ],
          ),
          handler: (args, ctx) => _maps.moveMarker(
            id: args['id']! as String,
            lat: (args['lat']! as num).toDouble(),
            lng: (args['lng']! as num).toDouble(),
            durationMs: (args['duration_ms'] as num?)?.toInt() ?? 1500,
          ),
        ),
        HostFunction(
          schema: HostFunctionSchema(
            name: 'map_clear_markers',
            description: 'Remove every marker, polyline, and polygon.',
            params: const [],
          ),
          handler: (args, ctx) async {
            _maps.clearAll();
            return null;
          },
        ),
        HostFunction(
          schema: HostFunctionSchema(
            name: 'map_fit_bounds',
            description:
                'Frame a list of [lat, lng] points by computing the '
                'smallest viewport (center + zoom) that contains all of '
                'them with `padding_pct` extra space, then fly there. '
                'Use AFTER dropping multiple markers to ensure they are '
                'all visible. Single point or near-zero extent snaps to '
                'zoom 13.',
            params: const [
              HostParam(
                name: 'points',
                type: HostParamType.list,
                description:
                    'List of [lat, lng] pairs (each a 2-element list).',
              ),
              HostParam(
                name: 'padding_pct',
                type: HostParamType.number,
                isRequired: false,
                defaultValue: 10,
                description:
                    'Percent extra space around the bounds (10 = 10% '
                    'padding on each side). Bigger value = wider view.',
              ),
              HostParam(
                name: 'duration_ms',
                type: HostParamType.integer,
                isRequired: false,
                description:
                    'Animation duration. Defaults to distance-aware.',
              ),
            ],
          ),
          handler: (args, ctx) async {
            final raw = args['points'];
            if (raw is! List) {
              throw FormatException(
                'map_fit_bounds: "points" must be a list of [lat, lng] pairs',
              );
            }
            final pts = <List<double>>[];
            for (final p in raw) {
              if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
                pts.add([(p[0] as num).toDouble(), (p[1] as num).toDouble()]);
              }
            }
            await _maps.fitBounds(
              points: pts,
              paddingPct: (args['padding_pct'] as num?)?.toDouble() ?? 10,
              durationMs: (args['duration_ms'] as num?)?.toInt(),
            );
            return null;
          },
        ),
        HostFunction(
          schema: HostFunctionSchema(
            name: 'map_set_basemap',
            description: 'Switch the tile layer. Valid styles: osm, topo, '
                'cartodb_positron, cartodb_dark.',
            params: const [
              HostParam(name: 'style', type: HostParamType.string),
            ],
          ),
          handler: (args, ctx) async {
            final ok = _maps.setBasemapStyle(args['style']! as String);
            if (!ok) {
              throw FormatException(
                'set_basemap: unknown style "${args['style']}"',
              );
            }
            return null;
          },
        ),
        HostFunction(
          schema: HostFunctionSchema(
            name: 'map_get_view',
            description: 'Return the current viewport: '
                '{lat, lng, zoom, rotation}.',
            params: const [],
          ),
          handler: (args, ctx) async => _maps.viewportJson(),
        ),
        HostFunction(
          schema: HostFunctionSchema(
            name: 'map_sleep_ms',
            description: 'Pause script execution for the given number '
                'of milliseconds. Useful between map_fly_to / '
                'map_add_marker calls so the user has time to see each '
                'step of a tour. Replaces Python `time.sleep` which is '
                'not available in the dart_monty stdlib.',
            params: const [
              HostParam(name: 'ms', type: HostParamType.integer),
            ],
          ),
          handler: (args, ctx) async {
            final ms = args['ms']! as int;
            if (ms > 0) {
              await Future<void>.delayed(Duration(milliseconds: ms));
            }
            return null;
          },
        ),
        HostFunction(
          schema: HostFunctionSchema(
            name: 'map_get_markers',
            description: 'List every marker currently on the map. Each '
                'item: {id, lat, lng, label?, color?, icon?}.',
            params: const [],
          ),
          handler: (args, ctx) async => _maps.markersJson(),
        ),
        HostFunction(
          schema: HostFunctionSchema(
            name: 'map_get_polylines',
            description: 'List every polyline. Each item: '
                '{id, pointCount, color?, width}.',
            params: const [],
          ),
          handler: (args, ctx) async => _maps.polylinesJson(),
        ),
        HostFunction(
          schema: HostFunctionSchema(
            name: 'map_get_polygons',
            description: 'List every polygon. Each item: '
                '{id, pointCount, fillColor?, strokeColor?}.',
            params: const [],
          ),
          handler: (args, ctx) async => _maps.polygonsJson(),
        ),
        HostFunction(
          schema: HostFunctionSchema(
            name: 'map_get_state',
            description: 'Aggregated snapshot: '
                '{viewport, markerCount, polylineCount, polygonCount, '
                'basemap, lastEvent}. Single call to read everything.',
            params: const [],
          ),
          handler: (args, ctx) async => _maps.stateSnapshot(),
        ),
        HostFunction(
          schema: HostFunctionSchema(
            name: 'map_get_bounds',
            description: 'Visible bounds of the current camera view: '
                '{north, south, east, west} in degrees. Returns null if '
                'the map widget has not rendered yet.',
            params: const [],
          ),
          handler: (args, ctx) async => _maps.boundsJson(),
        ),
      ];

  /// Reshape a Nominatim search hit into the dict Python sees.
  Map<String, Object?> _formatGeocodeResult(Map<Object?, Object?> item) {
    final lat = double.tryParse(item['lat']?.toString() ?? '');
    final lng = double.tryParse(item['lon']?.toString() ?? '');
    final bbox = item['boundingbox'];
    List<double>? bboxDeg;
    if (bbox is List && bbox.length == 4) {
      // Nominatim returns [south, north, west, east] as strings —
      // normalize to [south, west, north, east] (numerical order).
      final s = double.tryParse(bbox[0].toString());
      final n = double.tryParse(bbox[1].toString());
      final w = double.tryParse(bbox[2].toString());
      final e = double.tryParse(bbox[3].toString());
      if (s != null && n != null && w != null && e != null) {
        bboxDeg = [s, w, n, e];
      }
    }
    return {
      'lat': lat,
      'lng': lng,
      'display_name': item['display_name'],
      'type': item['type'],
      'importance': item['importance'],
      if (bboxDeg != null) 'bbox': bboxDeg,
    };
  }
}
