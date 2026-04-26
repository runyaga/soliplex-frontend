import 'package:latlong2/latlong.dart';
import 'package:soliplex_agent_maps/src/map_state.dart';
import 'package:soliplex_client/soliplex_client.dart' show StateProjection;

/// Projects map markers from `agentState['ui']['map']['sites']`.
///
/// Each site is `{id, name, lat, lng, status, supplies}`. The
/// projection produces one [MarkerData] per site with the label
/// composed from `name` + `status`. Color is derived from status:
/// `served` → green, anything else → orange.
class MapMarkersProjection extends StateProjection<List<MarkerData>> {
  /// Const constructor — projection is stateless.
  const MapMarkersProjection();

  @override
  List<MarkerData> project(Map<String, dynamic> agentState) {
    final ui = agentState['ui'];
    if (ui is! Map) return const [];
    final mapState = ui['map'];
    if (mapState is! Map) return const [];
    final sites = mapState['sites'];
    if (sites is! List) return const [];
    final out = <MarkerData>[];
    for (final raw in sites) {
      if (raw is! Map) continue;
      final id = raw['id'];
      final lat = raw['lat'];
      final lng = raw['lng'];
      if (id is! String || lat is! num || lng is! num) continue;
      final name = raw['name'] is String ? raw['name']! as String : id;
      final status =
          raw['status'] is String ? raw['status']! as String : 'pending';
      final color = status == 'served' ? 'green' : 'orange';
      out.add(
        MarkerData(
          id: id,
          lat: lat.toDouble(),
          lng: lng.toDouble(),
          label: '$name\nstatus: $status',
          color: color,
          icon: 'flag',
        ),
      );
    }
    return out;
  }
}

/// Projects sprite overlays (convoy + helpers) from
/// `agentState['ui']['map']['convoy']` (and optionally
/// `agentState['ui']['map']['sprites']` for additional ones).
///
/// The convoy is rendered as a single 64x64 overlay using the
/// shared helicopter asset. Future demos may emit a `sprites` list
/// for multi-vehicle scenarios; that's wired here too.
class MapSpritesProjection extends StateProjection<List<ImageOverlayData>> {
  /// Construct with the URL to use for the canonical convoy sprite.
  const MapSpritesProjection({
    this.convoyUrl = 'assets/maps/helicopter.png',
    this.convoyWidthPx = 64,
    this.convoyHeightPx = 64,
  });

  /// URL the convoy sprite is rendered with.
  final String convoyUrl;

  /// Width of the convoy sprite in screen pixels.
  final double convoyWidthPx;

  /// Height of the convoy sprite in screen pixels.
  final double convoyHeightPx;

  @override
  List<ImageOverlayData> project(Map<String, dynamic> agentState) {
    final ui = agentState['ui'];
    if (ui is! Map) return const [];
    final mapState = ui['map'];
    if (mapState is! Map) return const [];
    final out = <ImageOverlayData>[];

    final convoy = mapState['convoy'];
    if (convoy is Map) {
      final lat = convoy['lat'];
      final lng = convoy['lng'];
      if (lat is num && lng is num) {
        final heading = convoy['heading'] is num
            ? (convoy['heading']! as num).toDouble()
            : 0.0;
        out.add(
          ImageOverlayData(
            id: 'convoy-1',
            url: convoyUrl,
            lat: lat.toDouble(),
            lng: lng.toDouble(),
            widthPx: convoyWidthPx,
            heightPx: convoyHeightPx,
            rotation: heading,
          ),
        );
      }
    }

    final extras = mapState['sprites'];
    if (extras is List) {
      for (var i = 0; i < extras.length; i++) {
        final raw = extras[i];
        if (raw is! Map) continue;
        final id = raw['id'] is String ? raw['id']! as String : 'sprite-$i';
        final url = raw['url'] is String ? raw['url']! as String : convoyUrl;
        final lat = raw['lat'];
        final lng = raw['lng'];
        if (lat is! num || lng is! num) continue;
        out.add(
          ImageOverlayData(
            id: id,
            url: url,
            lat: lat.toDouble(),
            lng: lng.toDouble(),
            widthPx: raw['widthPx'] is num
                ? (raw['widthPx']! as num).toDouble()
                : convoyWidthPx,
            heightPx: raw['heightPx'] is num
                ? (raw['heightPx']! as num).toDouble()
                : convoyHeightPx,
            rotation: raw['rotation'] is num
                ? (raw['rotation']! as num).toDouble()
                : 0,
          ),
        );
      }
    }

    return out;
  }
}

/// Projects HUD overlays from `agentState['ui']['hud']`.
///
/// Today the agent state's HUD slice is `{tonnage_delivered,
/// elapsed_minutes, status_banner}`. The projection turns those
/// fields into corner-anchored HUDs. Live-ticking elapsed-time
/// clocks remain Dart-driven (set `tick=True` on the imperative
/// addHud) — this projection only handles agent-driven static text.
class MapHudProjection extends StateProjection<List<HudOverlayData>> {
  /// Const constructor — projection is stateless.
  const MapHudProjection();

  @override
  List<HudOverlayData> project(Map<String, dynamic> agentState) {
    final ui = agentState['ui'];
    if (ui is! Map) return const [];
    final hud = ui['hud'];
    if (hud is! Map) return const [];
    final out = <HudOverlayData>[];

    final banner = hud['status_banner'];
    if (banner is String && banner.isNotEmpty) {
      out.add(
        HudOverlayData(
          id: 'hud-banner',
          anchor: HudAnchor.topRight,
          text: banner,
          colorHex: 0xFFFFE066,
          backgroundHex: 0xCC0B0E12,
          margin: 100,
        ),
      );
    }

    final tonnage = hud['tonnage_delivered'];
    if (tonnage is num) {
      out.add(
        HudOverlayData(
          id: 'hud-tonnage',
          anchor: HudAnchor.topRight,
          text: '${tonnage.toStringAsFixed(1)} t delivered',
          colorHex: 0xFFFFFFFF,
          backgroundHex: 0xCC0B0E12,
          margin: 140,
          fontSize: 12,
        ),
      );
    }

    return out;
  }
}

/// Lightweight bridge — projects a Polyline route from
/// `agentState['ui']['map']['route']` if the agent emits one.
/// Optional today; included so map polylines can be projected too.
class MapRouteProjection extends StateProjection<List<PolylineData>> {
  /// Const constructor — projection is stateless.
  const MapRouteProjection({this.color = 'cyan', this.width = 3});

  /// Polyline color string.
  final String color;

  /// Polyline stroke width in screen pixels.
  final double width;

  @override
  List<PolylineData> project(Map<String, dynamic> agentState) {
    final ui = agentState['ui'];
    if (ui is! Map) return const [];
    final mapState = ui['map'];
    if (mapState is! Map) return const [];
    final route = mapState['route'];
    if (route is! List || route.length < 2) return const [];
    final points = <LatLng>[];
    for (final p in route) {
      if (p is! List || p.length < 2) continue;
      final lat = p[0];
      final lng = p[1];
      if (lat is! num || lng is! num) continue;
      points.add(LatLng(lat.toDouble(), lng.toDouble()));
    }
    if (points.length < 2) return const [];
    return [
      PolylineData(
        id: 'route',
        points: points,
        color: color,
        width: width,
      ),
    ];
  }
}
