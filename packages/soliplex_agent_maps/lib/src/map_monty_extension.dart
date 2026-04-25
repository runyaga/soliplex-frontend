// HostFunction wraps a closure that captures `_maps`, so the outer
// constructor can't be const. The redundant-arg warnings flag explicit
// `params: const []` and `isRequired: false`, both of which improve
// readability at the cost of matching defaults.
// ignore_for_file: prefer_const_constructors, avoid_redundant_argument_values

import 'package:dart_monty/dart_monty_bridge.dart'
    show
        HostFunction,
        HostFunctionSchema,
        HostParam,
        HostParamType,
        MontyExtension;

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
  MapMontyExtension(this._maps);

  final MapExtension _maps;

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
}
