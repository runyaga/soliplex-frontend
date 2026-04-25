import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Snapshot of the map's current viewport.
@immutable
class Viewport {
  const Viewport({
    required this.lat,
    required this.lng,
    required this.zoom,
    required this.rotation,
  });

  final double lat;
  final double lng;
  final double zoom;
  final double rotation;

  Map<String, Object?> toJson() => {
        'lat': lat,
        'lng': lng,
        'zoom': zoom,
        'rotation': rotation,
      };

  Viewport copyWith({
    double? lat,
    double? lng,
    double? zoom,
    double? rotation,
  }) =>
      Viewport(
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        zoom: zoom ?? this.zoom,
        rotation: rotation ?? this.rotation,
      );
}

/// A pin/marker shown on the map.
@immutable
class MarkerData {
  const MarkerData({
    required this.id,
    required this.lat,
    required this.lng,
    this.label,
    this.color,
    this.icon,
    this.dropAnimation = true,
    this.pulse = false,
    this.createdAtMs,
  });

  final String id;
  final double lat;
  final double lng;
  final String? label;

  /// Hex color string (e.g. `#FF0000`) or named color (`red`, `blue`...).
  final String? color;

  /// Material icon code-point name. Defaults to `place` if null.
  final String? icon;

  /// Whether to play the drop-in bounce animation when this marker mounts.
  final bool dropAnimation;

  /// Whether the marker is currently pulsing.
  final bool pulse;

  /// Wall-clock millis the marker was added — used as an AnimatedSwitcher key
  /// hint, not for ordering.
  final int? createdAtMs;

  MarkerData copyWith({
    String? label,
    String? color,
    String? icon,
    bool? dropAnimation,
    bool? pulse,
  }) =>
      MarkerData(
        id: id,
        lat: lat,
        lng: lng,
        label: label ?? this.label,
        color: color ?? this.color,
        icon: icon ?? this.icon,
        dropAnimation: dropAnimation ?? this.dropAnimation,
        pulse: pulse ?? this.pulse,
        createdAtMs: createdAtMs,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'lat': lat,
        'lng': lng,
        if (label != null) 'label': label,
        if (color != null) 'color': color,
        if (icon != null) 'icon': icon,
      };
}

/// A polyline drawn on the map.
@immutable
class PolylineData {
  const PolylineData({
    required this.id,
    required this.points,
    this.color,
    this.width = 4,
    this.animated = false,
    this.progress = 1,
  });

  final String id;
  final List<LatLng> points;
  final String? color;
  final double width;
  final bool animated;

  /// 0..1 — fraction of the polyline currently visible (used for
  /// "drawing" animation).
  final double progress;

  PolylineData copyWith({double? progress}) => PolylineData(
        id: id,
        points: points,
        color: color,
        width: width,
        animated: animated,
        progress: progress ?? this.progress,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'pointCount': points.length,
        if (color != null) 'color': color,
        'width': width,
      };
}

/// A polygon drawn on the map.
@immutable
class PolygonData {
  const PolygonData({
    required this.id,
    required this.points,
    this.fillColor,
    this.strokeColor,
    this.strokeWidth = 2,
  });

  final String id;
  final List<LatLng> points;
  final String? fillColor;
  final String? strokeColor;
  final double strokeWidth;

  Map<String, Object?> toJson() => {
        'id': id,
        'pointCount': points.length,
        if (fillColor != null) 'fillColor': fillColor,
        if (strokeColor != null) 'strokeColor': strokeColor,
      };
}

/// Tile-source basemap selection.
enum BasemapStyle {
  osm,
  topo,
  cartodbPositron,
  cartodbDark;

  static BasemapStyle? parse(String value) {
    switch (value) {
      case 'osm':
        return BasemapStyle.osm;
      case 'topo':
        return BasemapStyle.topo;
      case 'cartodb_positron':
        return BasemapStyle.cartodbPositron;
      case 'cartodb_dark':
        return BasemapStyle.cartodbDark;
    }
    return null;
  }

  String get id {
    switch (this) {
      case BasemapStyle.osm:
        return 'osm';
      case BasemapStyle.topo:
        return 'topo';
      case BasemapStyle.cartodbPositron:
        return 'cartodb_positron';
      case BasemapStyle.cartodbDark:
        return 'cartodb_dark';
    }
  }

  /// Tile-server URL template. All providers serve OSM-derived tiles.
  String get urlTemplate {
    switch (this) {
      case BasemapStyle.osm:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case BasemapStyle.topo:
        return 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
      case BasemapStyle.cartodbPositron:
        return 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
      case BasemapStyle.cartodbDark:
        return 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
    }
  }

  /// Human-readable attribution text required by the tile provider's ToS.
  String get attribution {
    switch (this) {
      case BasemapStyle.osm:
        return '© OpenStreetMap contributors';
      case BasemapStyle.topo:
        return '© OpenTopoMap (CC-BY-SA), © OpenStreetMap contributors';
      case BasemapStyle.cartodbPositron:
      case BasemapStyle.cartodbDark:
        return '© CARTO, © OpenStreetMap contributors';
    }
  }
}
