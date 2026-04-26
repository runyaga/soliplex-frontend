import 'dart:async';

import 'package:soliplex_agent_maps/soliplex_agent_maps.dart'
    show HudAnchor, MapExtension;
import 'package:soliplex_client/soliplex_client.dart' show StateBus;

/// Compressed timeline driver for the AID DISTRIBUTION GenUI demo.
///
/// Mimics what a server-side agent would emit over AG-UI: an opening
/// state snapshot followed by a sequence of patches (route the
/// convoy, flip site statuses, append narrations, update the HUD).
/// Each tick replaces the bus's agent state with the next snapshot.
///
/// No real agent or backend involved. The point is to prove the
/// state-projection pipeline end-to-end — the same Surface
/// projections will work against a real backend later.
///
/// Cancel by passing a [Completer] for [cancel] and completing it.
/// The replay tears down on the next tick.
Future<void> runAidDistributionReplay(
  StateBus bus, {
  Duration tick = const Duration(milliseconds: 700),
  Completer<void>? cancel,
  MapExtension? map,
}) async {
  // Northern District: a fictionalized humanitarian-relief scenario.
  // Coordinates are illustrative — fictional region, civilian-only
  // framing.
  const hubLat = 40.0;
  const hubLng = -90.0;

  final sites = [
    {
      'id': 'camp-a',
      'name': 'Camp Northwind',
      'lat': 40.18,
      'lng': -90.06,
      'status': 'pending',
      'supplies': <String, int>{},
    },
    {
      'id': 'camp-b',
      'name': 'Camp Riverbend',
      'lat': 40.12,
      'lng': -89.74,
      'status': 'pending',
      'supplies': <String, int>{},
    },
    {
      'id': 'camp-c',
      'name': 'Camp Southlake',
      'lat': 39.78,
      'lng': -89.96,
      'status': 'pending',
      'supplies': <String, int>{},
    },
    {
      'id': 'camp-d',
      'name': 'Camp Ridgeway',
      'lat': 39.92,
      'lng': -90.32,
      'status': 'pending',
      'supplies': <String, int>{},
    },
  ];

  final narrations = <Map<String, String>>[];

  Map<String, dynamic> snapshot({
    required double convoyLat,
    required double convoyLng,
    required double convoyHeading,
    required String banner,
    required double tonnage,
    required int elapsedMin,
  }) {
    return <String, dynamic>{
      'ui': <String, dynamic>{
        'map': <String, dynamic>{
          'convoy': <String, dynamic>{
            'lat': convoyLat,
            'lng': convoyLng,
            'heading': convoyHeading,
          },
          'sites': List<Map<String, dynamic>>.from(sites),
        },
        'hud': <String, dynamic>{
          'tonnage_delivered': tonnage,
          'elapsed_minutes': elapsedMin,
          'status_banner': banner,
        },
        'narrations': List<Map<String, String>>.from(narrations),
      },
    };
  }

  bool isCancelled() => cancel?.isCompleted ?? false;

  Future<void> wait() async {
    if (isCancelled()) return;
    await Future<void>.delayed(tick);
  }

  void log(String actor, String text) {
    narrations.add({'actor': actor, 'text': text});
  }

  // ---- Opening pose --------------------------------------------------------
  // Imperative map drive (P4 will move this to a MapProjection over
  // the same agent state). For now, paint pins + HUD + sprite by
  // hand so the demo has something visible to back the narration.
  // Camera flight + the live ticking clock are still imperative —
  // those concerns aren't carried in agent state (camera is the
  // viewer's, not the agent's; the clock is a Dart-side ticker).
  // Markers, sprites, HUD banners are all driven by projections
  // over agent state — see room_screen.dart wireMarkers /
  // wireImages / wireHuds calls.
  if (map != null) {
    await map.flyTo(lat: hubLat, lng: hubLng, zoom: 8, durationMs: 1200);
    map.addHud(
      anchor: HudAnchor.bottomRight,
      colorHex: 0xFF66C7FF,
      backgroundHex: 0xCC0B0E12,
      tick: true,
      timeScale: 30,
    );
  }

  bus.setAgentState(
    snapshot(
      convoyLat: hubLat,
      convoyLng: hubLng,
      convoyHeading: 0,
      banner: 'Standing by',
      tonnage: 0,
      elapsedMin: 0,
    ),
  );
  await wait();
  if (isCancelled()) return;

  log('coordinator', 'Convoy 1, depart for Camp Northwind.');
  log('primary', 'Convoy 1 rolling, ETA 8 min.');
  bus.setAgentState(
    snapshot(
      convoyLat: hubLat,
      convoyLng: hubLng,
      convoyHeading: 320,
      banner: 'Convoy departing hub',
      tonnage: 0,
      elapsedMin: 0,
    ),
  );
  await wait();
  if (isCancelled()) return;

  // ---- Visit each site ----------------------------------------------------
  var tonnage = 0.0;
  var elapsed = 0;

  for (var i = 0; i < sites.length; i++) {
    if (isCancelled()) return;
    final site = sites[i];
    final lat = site['lat']! as double;
    final lng = site['lng']! as double;
    final fromLat = i == 0 ? hubLat : sites[i - 1]['lat']! as double;
    final fromLng = i == 0 ? hubLng : sites[i - 1]['lng']! as double;

    // Camera flight is the viewer's concern, not the agent's —
    // keep this imperative even after the projection refactor.
    if (map != null) {
      unawaited(map.flyTo(lat: lat, lng: lng, zoom: 9, durationMs: 2400));
    }

    // Approach (3 micro-steps for a smooth-ish track)
    for (var t = 1; t <= 3; t++) {
      if (isCancelled()) return;
      final f = t / 3;
      bus.setAgentState(
        snapshot(
          convoyLat: fromLat + (lat - fromLat) * f,
          convoyLng: fromLng + (lng - fromLng) * f,
          convoyHeading: i * 90 + 30,
          banner: 'En route to ${site['name']}',
          tonnage: tonnage,
          elapsedMin: elapsed,
        ),
      );
      await wait();
    }

    elapsed += 18;
    log('field', '${site['name']} receiving convoy.');

    // Offload
    site['status'] = 'served';
    site['supplies'] = <String, int>{
      'water_l': 1500,
      'food_kg': 800,
      'medkits': 40,
    };
    tonnage += 1.6;

    log('primary', 'Offload complete at ${site['name']}.');
    bus.setAgentState(
      snapshot(
        convoyLat: lat,
        convoyLng: lng,
        convoyHeading: i * 90 + 30,
        banner: '${site['name']} served',
        tonnage: tonnage,
        elapsedMin: elapsed,
      ),
    );
    await wait();
    if (isCancelled()) return;

    if (i < sites.length - 1) {
      log('coordinator', 'Push to ${sites[i + 1]['name']}.');
    }
  }

  if (isCancelled()) return;

  // ---- Return to hub -------------------------------------------------------
  log('primary', 'Last camp served. Returning to hub.');
  if (map != null) {
    unawaited(
      map.flyTo(lat: hubLat, lng: hubLng, zoom: 8, durationMs: 2200),
    );
  }
  for (var t = 1; t <= 3; t++) {
    if (isCancelled()) return;
    final f = t / 3;
    final last = sites.last;
    final lastLat = last['lat']! as double;
    final lastLng = last['lng']! as double;
    bus.setAgentState(
      snapshot(
        convoyLat: lastLat + (hubLat - lastLat) * f,
        convoyLng: lastLng + (hubLng - lastLng) * f,
        convoyHeading: 90,
        banner: 'Returning to hub',
        tonnage: tonnage,
        elapsedMin: elapsed + (5 * t),
      ),
    );
    await wait();
  }

  log('coordinator', 'Excellent work. Mission complete.');
  bus.setAgentState(
    snapshot(
      convoyLat: hubLat,
      convoyLng: hubLng,
      convoyHeading: 0,
      banner: 'Mission complete — convoy returned to hub',
      tonnage: tonnage,
      elapsedMin: elapsed + 15,
    ),
  );
}
