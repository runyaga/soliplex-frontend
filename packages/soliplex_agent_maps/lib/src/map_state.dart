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
    this.tapImage,
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

  /// When set, tapping the marker spawns this image overlay (and a
  /// second tap dismisses it).
  final TapImageAction? tapImage;

  MarkerData copyWith({
    double? lat,
    double? lng,
    String? label,
    String? color,
    String? icon,
    bool? dropAnimation,
    bool? pulse,
    TapImageAction? tapImage,
  }) =>
      MarkerData(
        id: id,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        label: label ?? this.label,
        color: color ?? this.color,
        icon: icon ?? this.icon,
        dropAnimation: dropAnimation ?? this.dropAnimation,
        pulse: pulse ?? this.pulse,
        createdAtMs: createdAtMs,
        tapImage: tapImage ?? this.tapImage,
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

/// Spec for an image overlay that spawns when a marker is tapped.
@immutable
class TapImageAction {
  const TapImageAction({
    required this.url,
    this.lngOffset = 0.05,
    this.latOffset = 0.05,
    this.width = 140,
    this.height = 140,
  });

  final String url;
  final double latOffset;
  final double lngOffset;
  final double width;
  final double height;
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

/// An image (PNG, JPG, **animated GIF**) anchored at a lat/lng. Renders
/// as a Marker with `Image.network` as its child — Flutter's Image
/// widget handles animated GIFs natively, so dropping a helicopter GIF
/// at a coordinate and letting it loop just works.
@immutable
class ImageOverlayData {
  const ImageOverlayData({
    required this.id,
    required this.url,
    required this.lat,
    required this.lng,
    this.widthPx = 64,
    this.heightPx = 64,
    this.rotation = 0,
    this.opacity = 1,
  });

  final String id;
  final String url;
  final double lat;
  final double lng;
  final double widthPx;
  final double heightPx;
  final double rotation; // degrees, clockwise
  final double opacity; // 0..1

  ImageOverlayData copyWith({
    double? lat,
    double? lng,
    double? widthPx,
    double? heightPx,
    double? rotation,
    double? opacity,
  }) =>
      ImageOverlayData(
        id: id,
        url: url,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        widthPx: widthPx ?? this.widthPx,
        heightPx: heightPx ?? this.heightPx,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'url': url,
        'lat': lat,
        'lng': lng,
        'widthPx': widthPx,
        'heightPx': heightPx,
        'rotation': rotation,
        'opacity': opacity,
      };
}

/// Anchor corner for screen-space HUD overlays.
///
/// HUDs render in a [Stack] above the map, glued to a screen-space
/// position so they don't pan/zoom with the camera. Useful for the
/// classified stamp, callsign card, mission clock, and similar
/// "operator-console" furniture.
enum HudAnchor { topLeft, topRight, bottomLeft, bottomRight, center }

/// A screen-space overlay on top of the map.
///
/// Either an image (via [url]) or a styled text label (via [text]).
/// Text overlays render with a translucent dark background and a
/// monospace stencil-ish look; pass [color] / [background] to override.
@immutable
class HudOverlayData {
  HudOverlayData({
    required this.id,
    required this.anchor,
    this.url,
    this.text,
    this.margin = 16,
    this.colorHex,
    this.backgroundHex,
    this.fontSize = 13,
    this.tick = false,
    this.timeScale = 1.0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final HudAnchor anchor;
  final String? url;
  final String? text;
  final double margin;

  /// When true, the renderer ignores [text] and shows a self-ticking
  /// "T+HH:MM:SS" elapsed-time label that updates every second
  /// regardless of what the script is doing. Use for mission clocks.
  final bool tick;

  /// Multiplier on real elapsed time. `1.0` = real time. `300.0`
  /// compresses a 5-hour mission into ~60 seconds of wall-clock demo.
  /// Only used when [tick] is true.
  final double timeScale;

  /// Wall-clock time the HUD was created. The live-ticking renderer
  /// computes elapsed = (now - createdAt) * timeScale.
  final DateTime createdAt;

  /// Foreground color for text overlays, encoded as 0xAARRGGBB. If
  /// null, renderer picks a sensible default per anchor.
  final int? colorHex;

  /// Background color for text overlays, encoded as 0xAARRGGBB. If
  /// null, renderer picks a translucent dark default.
  final int? backgroundHex;

  final double fontSize;

  Map<String, Object?> toJson() => {
        'id': id,
        'anchor': anchor.name,
        'url': url,
        'text': text,
        'margin': margin,
        'colorHex': colorHex,
        'backgroundHex': backgroundHex,
        'fontSize': fontSize,
        'tick': tick,
        'timeScale': timeScale,
        'createdAtMs': createdAt.millisecondsSinceEpoch,
      };
}

/// Tile-source basemap selection.
///
/// All providers below serve free, no-API-key tiles. Stamen and Mapbox
/// styles are intentionally excluded because they require keys post-2023.
enum BasemapStyle {
  osm,
  topo,
  cartodbPositron,
  cartodbDark,
  cartodbVoyager,
  esriWorldImagery,   // satellite — biggest visual upgrade
  esriWorldTopo,
  esriNatgeo,
  cyclosm;

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
      case 'cartodb_voyager':
        return BasemapStyle.cartodbVoyager;
      case 'satellite':
      case 'esri_satellite':
      case 'esri_imagery':
        return BasemapStyle.esriWorldImagery;
      case 'esri_topo':
        return BasemapStyle.esriWorldTopo;
      case 'esri_natgeo':
      case 'natgeo':
        return BasemapStyle.esriNatgeo;
      case 'cyclosm':
      case 'cycling':
        return BasemapStyle.cyclosm;
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
      case BasemapStyle.cartodbVoyager:
        return 'cartodb_voyager';
      case BasemapStyle.esriWorldImagery:
        return 'esri_satellite';
      case BasemapStyle.esriWorldTopo:
        return 'esri_topo';
      case BasemapStyle.esriNatgeo:
        return 'esri_natgeo';
      case BasemapStyle.cyclosm:
        return 'cyclosm';
    }
  }

  /// Tile-server URL template. Templates with `{s}` need [subdomains].
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
      case BasemapStyle.cartodbVoyager:
        return 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/'
            '{z}/{x}/{y}.png';
      case BasemapStyle.esriWorldImagery:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case BasemapStyle.esriWorldTopo:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'World_Topo_Map/MapServer/tile/{z}/{y}/{x}';
      case BasemapStyle.esriNatgeo:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'NatGeo_World_Map/MapServer/tile/{z}/{y}/{x}';
      case BasemapStyle.cyclosm:
        return 'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/'
            '{z}/{x}/{y}.png';
    }
  }

  /// Subdomains for `{s}` substitution. Empty list when the URL has no `{s}`.
  List<String> get subdomains {
    switch (this) {
      case BasemapStyle.osm:
      case BasemapStyle.topo:
      case BasemapStyle.esriWorldImagery:
      case BasemapStyle.esriWorldTopo:
      case BasemapStyle.esriNatgeo:
        return const [];
      case BasemapStyle.cartodbPositron:
      case BasemapStyle.cartodbDark:
      case BasemapStyle.cartodbVoyager:
        return const ['a', 'b', 'c', 'd'];
      case BasemapStyle.cyclosm:
        return const ['a', 'b', 'c'];
    }
  }

  /// Maximum native zoom the tile provider serves at full resolution.
  /// Above this the layer auto-magnifies (blurry but functional).
  int get maxNativeZoom {
    switch (this) {
      case BasemapStyle.osm:
      case BasemapStyle.cartodbPositron:
      case BasemapStyle.cartodbDark:
      case BasemapStyle.cartodbVoyager:
      case BasemapStyle.esriWorldImagery:
      case BasemapStyle.esriWorldTopo:
      case BasemapStyle.esriNatgeo:
        return 19;
      case BasemapStyle.topo:
        return 17;
      case BasemapStyle.cyclosm:
        return 18;
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
      case BasemapStyle.cartodbVoyager:
        return '© CARTO, © OpenStreetMap contributors';
      case BasemapStyle.esriWorldImagery:
      case BasemapStyle.esriWorldTopo:
      case BasemapStyle.esriNatgeo:
        return 'Tiles © Esri';
      case BasemapStyle.cyclosm:
        return 'CyclOSM, © OpenStreetMap contributors';
    }
  }
}
