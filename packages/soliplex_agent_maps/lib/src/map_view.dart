import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:signals_flutter/signals_flutter.dart';

import 'package:soliplex_agent_maps/src/map_extension.dart';
import 'package:soliplex_agent_maps/src/map_state.dart';

/// Drop-in widget that renders the map driven by a [MapExtension].
///
/// Designed to be mounted once per session and stay mounted across LLM
/// turns — tool calls update it imperatively via the extension's
/// [MapController] and reactive signals.
class MapView extends StatelessWidget {
  const MapView({required this.extension, super.key});

  final MapExtension extension;

  @override
  Widget build(BuildContext context) {
    final basemap = extension.basemap.watch(context);
    final markers = extension.markers.watch(context);
    final polylines = extension.polylines.watch(context);
    final polygons = extension.polygons.watch(context);
    final images = extension.images.watch(context);

    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // World pixel size at zoom z is 256 * 2^z. To prevent
          // horizontal wrap, the world must be at least as wide as
          // the viewport. Solve: z >= log2(viewportWidth / 256).
          // Rounded up to the next zoom level so we never wrap.
          final wrapMin = (math.log(constraints.maxWidth / 256) / math.ln2)
              .ceilToDouble();
          final minZoom = math.max(1.0, wrapMin);
          return Stack(
            children: [
              FlutterMap(
                mapController: extension.controller,
                options: MapOptions(
                  initialCenter: LatLng(
                    extension.initialViewport.lat,
                    extension.initialViewport.lng,
                  ),
                  initialZoom: math.max(
                    extension.initialViewport.zoom,
                    minZoom,
                  ),
                  initialRotation: extension.initialViewport.rotation,
                  minZoom: minZoom,
                  maxZoom: 19,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  // Long-press anywhere on the map drops a pulsing
                  // pin at that lat/lng. Shares the same code path as
                  // the `add_marker` ClientTool / Monty external —
                  // pins dropped this way are observable from Python
                  // and the LLM via the markers signal.
                  onLongPress: (tapPosition, point) {
                    // Fire-and-forget — long-press just drops the pin.
                    unawaited(
                      extension.addMarker(
                        lat: point.latitude,
                        lng: point.longitude,
                        pulse: true,
                      ),
                    );
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: basemap.urlTemplate,
                    subdomains: basemap.subdomains,
                    maxNativeZoom: basemap.maxNativeZoom,
                    userAgentPackageName: 'ai.soliplex.client',
                  ),
                  if (polygons.isNotEmpty)
                    PolygonLayer(
                      polygons: [
                        for (final p in polygons)
                          Polygon(
                            points: p.points,
                            color: _parseColor(
                                  p.fillColor,
                                  fallback:
                                      Colors.blue.withValues(alpha: 0.2),
                                ) ??
                                Colors.blue.withValues(alpha: 0.2),
                            borderColor: _parseColor(
                                  p.strokeColor,
                                  fallback: Colors.blue,
                                ) ??
                                Colors.blue,
                            borderStrokeWidth: p.strokeWidth,
                          ),
                      ],
                    ),
                  if (polylines.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        for (final line in polylines)
                          Polyline(
                            points: _progressPoints(line),
                            color: _parseColor(
                                  line.color,
                                  fallback: Colors.red,
                                ) ??
                                Colors.red,
                            strokeWidth: line.width,
                          ),
                      ],
                    ),
                  if (markers.isNotEmpty)
                    MarkerLayer(
                      markers: [
                        for (final m in markers)
                          Marker(
                            point: LatLng(m.lat, m.lng),
                            width: 48,
                            height: 56,
                            alignment: Alignment.topCenter,
                            child: _AnimatedPin(
                              key: ValueKey(m.id),
                              marker: m,
                            ),
                          ),
                      ],
                    ),
                  if (images.isNotEmpty)
                    MarkerLayer(
                      markers: [
                        for (final img in images)
                          Marker(
                            key: ValueKey('img:${img.id}'),
                            point: LatLng(img.lat, img.lng),
                            width: img.widthPx,
                            height: img.heightPx,
                            alignment: Alignment.center,
                            child: Opacity(
                              opacity: img.opacity,
                              child: Transform.rotate(
                                angle: img.rotation * 3.14159265 / 180,
                                child: _buildImage(img),
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              Positioned(
                right: 4,
                bottom: 2,
                child: _AttributionPill(text: basemap.attribution),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: _CompassButton(extension: extension),
              ),
              Positioned(
                top: 50,
                right: 8,
                child: _LayerSelector(extension: extension, current: basemap),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: _ZoomControls(extension: extension),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Returns the visible portion of an animated polyline given its
  /// `progress` 0..1.
  static List<LatLng> _progressPoints(PolylineData line) {
    if (!line.animated || line.progress >= 1) return line.points;
    if (line.progress <= 0 || line.points.length < 2) return const [];
    // Compute cumulative length along the line, then cut at progress *
    // total.
    final segLengths = <double>[];
    double total = 0;
    for (var i = 1; i < line.points.length; i++) {
      final a = line.points[i - 1];
      final b = line.points[i];
      final d = math.sqrt(
        math.pow(a.latitude - b.latitude, 2) +
            math.pow(a.longitude - b.longitude, 2),
      );
      segLengths.add(d);
      total += d;
    }
    if (total == 0) return [line.points.first];
    var consumed = line.progress * total;
    final out = <LatLng>[line.points.first];
    for (var i = 0; i < segLengths.length; i++) {
      if (consumed >= segLengths[i]) {
        out.add(line.points[i + 1]);
        consumed -= segLengths[i];
      } else {
        final t = consumed / segLengths[i];
        final a = line.points[i];
        final b = line.points[i + 1];
        out.add(
          LatLng(
            a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t,
          ),
        );
        break;
      }
    }
    return out;
  }
}

class _AttributionPill extends StatelessWidget {
  const _AttributionPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({required this.extension});

  final MapExtension extension;

  void _zoomBy(double delta) {
    final camera = extension.controller.camera;
    final next = (camera.zoom + delta).clamp(1.0, 19.0);
    if (next == camera.zoom) return;
    extension.controller.move(camera.center, next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.surface.withValues(alpha: 0.9);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(6),
      elevation: 2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(
            tooltip: 'Zoom in',
            icon: Icons.add,
            onTap: () => _zoomBy(1),
          ),
          Container(height: 1, width: 28, color: theme.dividerColor),
          _ZoomButton(
            tooltip: 'Zoom out',
            icon: Icons.remove,
            onTap: () => _zoomBy(-1),
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _CompassButton extends StatelessWidget {
  const _CompassButton({required this.extension});

  final MapExtension extension;

  @override
  Widget build(BuildContext context) {
    final vp = extension.viewport.watch(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => extension.controller.rotate(0),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Transform.rotate(
            angle: -vp.rotation * math.pi / 180,
            child: Icon(
              Icons.navigation,
              size: 20,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating button that opens a basemap-style picker. Shipped layers
/// match [BasemapStyle] — the same set Python's `map_set_basemap`
/// accepts. Selecting a style writes through to the same signal the
/// LLM-driven path uses, so the in-map UI and tool calls share state.
class _LayerSelector extends StatelessWidget {
  const _LayerSelector({required this.extension, required this.current});

  final MapExtension extension;
  final BasemapStyle current;

  static const _entries = <(BasemapStyle, String, IconData)>[
    (BasemapStyle.osm, 'OpenStreetMap', Icons.map_outlined),
    (BasemapStyle.cartodbVoyager, 'Carto Voyager', Icons.public),
    (BasemapStyle.cartodbPositron, 'Carto Positron (light)', Icons.light_mode),
    (BasemapStyle.cartodbDark, 'Carto Dark', Icons.dark_mode),
    (BasemapStyle.topo, 'OpenTopoMap', Icons.terrain),
    (BasemapStyle.esriWorldImagery, 'Satellite (Esri)', Icons.satellite_alt),
    (BasemapStyle.esriWorldTopo, 'Esri Topo', Icons.terrain),
    (BasemapStyle.esriNatgeo, 'National Geographic', Icons.travel_explore),
    (BasemapStyle.cyclosm, 'CyclOSM', Icons.directions_bike),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      elevation: 2,
      child: PopupMenuButton<BasemapStyle>(
        tooltip: 'Choose basemap',
        position: PopupMenuPosition.under,
        onSelected: (style) => extension.setBasemapStyle(style.id),
        itemBuilder: (context) => [
          for (final (style, label, icon) in _entries)
            PopupMenuItem<BasemapStyle>(
              value: style,
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: style == current
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: style == current
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: style == current
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            Icons.layers_outlined,
            size: 20,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _AnimatedPin extends StatefulWidget {
  const _AnimatedPin({required this.marker, super.key});
  final MarkerData marker;

  @override
  State<_AnimatedPin> createState() => _AnimatedPinState();
}

class _AnimatedPinState extends State<_AnimatedPin>
    with TickerProviderStateMixin {
  late final AnimationController _drop;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _drop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.marker.dropAnimation) {
      unawaited(_drop.forward());
    } else {
      _drop.value = 1;
    }
    if (widget.marker.pulse) {
      unawaited(_pulse.repeat());
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedPin oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.marker.pulse && !_pulse.isAnimating) {
      unawaited(_pulse.repeat());
    } else if (!widget.marker.pulse && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _drop.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        _parseColor(widget.marker.color, fallback: Colors.red) ?? Colors.red;
    final iconData = _iconFor(widget.marker.icon);

    return AnimatedBuilder(
      animation: Listenable.merge([_drop, _pulse]),
      builder: (context, child) {
        // Drop: slide from -40px with elastic landing.
        final dropDy = (1 - Curves.elasticOut.transform(_drop.value)) * -40;
        // Pulse: 1.0 -> 1.6 scale on a halo, fade out.
        final pulseScale = 1.0 + _pulse.value * 0.6;
        final pulseOpacity = (1 - _pulse.value).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, dropDy),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.marker.pulse)
                Positioned(
                  top: 8,
                  child: Opacity(
                    opacity: pulseOpacity,
                    child: Transform.scale(
                      scale: pulseScale,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                ),
              child!,
            ],
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            iconData,
            color: color,
            size: 36,
            shadows: const [
              Shadow(
                color: Colors.black54,
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          if (widget.marker.label != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                widget.marker.label!,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

IconData _iconFor(String? name) {
  switch (name) {
    case 'flag':
      return Icons.flag;
    case 'star':
      return Icons.star;
    case 'home':
      return Icons.home;
    case 'restaurant':
      return Icons.restaurant;
    case 'hotel':
      return Icons.hotel;
    case 'local_cafe':
      return Icons.local_cafe;
    case 'directions_walk':
      return Icons.directions_walk;
    case 'place':
    default:
      return Icons.place;
  }
}

/// Picks the right Image loader for an [ImageOverlayData].
///
/// Flutter Web cannot reach bundled assets via `Image.network` — relative
/// asset paths resolve against the page URL, but the binary bytes live
/// in Flutter's asset bundle, not at any HTTP endpoint. Use `Image.asset`
/// for URLs that look like bundle paths (starting with `assets/`).
///
/// Anything starting with `http://`, `https://`, or any other scheme
/// goes through `Image.network` as before.
Widget _buildImage(ImageOverlayData img) {
  final isAsset =
      img.url.startsWith('assets/') || img.url.startsWith('packages/');
  Widget brokenIcon(BuildContext context, Object error, StackTrace? stack) {
    // Loud-and-noticeable failure: orange box with the URL printed
    // inside, so visible problems on the map flag themselves with
    // the actionable detail. Logs to console too.
    debugPrint('ImageOverlay load failed url=${img.url}: $error');
    return Container(
      width: img.widthPx,
      height: img.heightPx,
      decoration: BoxDecoration(
        color: Colors.orange.shade400,
        border: Border.all(color: Colors.red, width: 2),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(2),
      child: Text(
        'IMG\n${img.url}',
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        maxLines: 4,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  if (isAsset) {
    return Image.asset(
      img.url,
      width: img.widthPx,
      height: img.heightPx,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: brokenIcon,
    );
  }
  return Image.network(
    img.url,
    width: img.widthPx,
    height: img.heightPx,
    fit: BoxFit.contain,
    gaplessPlayback: true,
    errorBuilder: brokenIcon,
  );
}

Color? _parseColor(String? raw, {required Color fallback}) {
  if (raw == null) return fallback;
  switch (raw.toLowerCase()) {
    case 'red':
      return Colors.red;
    case 'blue':
      return Colors.blue;
    case 'green':
      return Colors.green;
    case 'orange':
      return Colors.orange;
    case 'purple':
      return Colors.purple;
    case 'yellow':
      return Colors.yellow;
    case 'black':
      return Colors.black;
    case 'white':
      return Colors.white;
    case 'pink':
      return Colors.pink;
    case 'teal':
      return Colors.teal;
  }
  // Hex (#RRGGBB or #AARRGGBB).
  final hex = raw.startsWith('#') ? raw.substring(1) : raw;
  if (hex.length == 6) {
    final v = int.tryParse(hex, radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  } else if (hex.length == 8) {
    final v = int.tryParse(hex, radix: 16);
    if (v != null) return Color(v);
  }
  return fallback;
}
