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

    return ClipRect(
      child: Stack(
        children: [
          FlutterMap(
            mapController: extension.controller,
            options: MapOptions(
              initialCenter: LatLng(
                extension.initialViewport.lat,
                extension.initialViewport.lng,
              ),
              initialZoom: extension.initialViewport.zoom,
              initialRotation: extension.initialViewport.rotation,
              minZoom: 1,
              maxZoom: 19,
              backgroundColor: Theme.of(context).colorScheme.surface,
              // Long-press anywhere on the map drops a pulsing pin at
              // that lat/lng. Shares the same code path as the
              // `add_marker` ClientTool / Monty external — pins
              // dropped this way are observable from Python and the
              // LLM via the markers signal.
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
                              fallback: Colors.blue.withValues(alpha: 0.2),
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
                        color: _parseColor(line.color, fallback: Colors.red) ??
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
            top: 8,
            left: 8,
            child: _ZoomControls(extension: extension),
          ),
        ],
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
