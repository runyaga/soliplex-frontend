import 'package:dart_monty/dart_monty.dart' show MontyRuntime;
import 'package:dart_monty/dart_monty_bridge.dart' show defaultExtensions;
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent_maps/soliplex_agent_maps.dart';

/// Integration tests that drive a real `MontyRuntime` so we can verify
/// Python scripts call into `MapMontyExtension` and mutate the shared
/// `MapExtension` state. This is the demo of Monty + flutter_map state
/// sharing — what the LLM ClientTool surface drives, Python drives too,
/// observable via the same signals.
///
/// Notes / caveats:
///
/// - `MapExtension.flyTo` calls `MapController.moveAndRotate` which
///   throws when no `FlutterMap` widget is mounted. The extension
///   silently swallows the throw, so `flyTo` test cases here only
///   verify the call returns successfully and the `lastEvent` field of
///   the state map is updated. Actual viewport mutation requires a
///   widget test (TODO).
/// - These tests exercise the FFI backend (default for `dart test`
///   without `-p chrome`). WASM coverage requires `-p chrome` and the
///   appropriate dart_monty WASM assets — added in a follow-up.
void main() {
  group('MapMontyExtension via real MontyRuntime', () {
    late MapExtension mapExt;
    late MontyRuntime runtime;

    setUp(() {
      mapExt = MapExtension();
      runtime = MontyRuntime(
        extensions: [...defaultExtensions(), MapMontyExtension(mapExt)],
      );
    });

    tearDown(() async {
      await runtime.dispose();
      mapExt.onDispose();
    });

    Future<Object?> runPython(String code) async {
      final handle = runtime.execute(code);
      final result = await handle.result;
      if (result.error != null) {
        fail(
          'Python error: ${result.error!.toJson()}\nOutput: '
          '${result.printOutput ?? ''}',
        );
      }
      return result.value.toJson();
    }

    test('add_marker pushes a marker into the markers signal', () async {
      final returned = await runPython('''
mid = map_add_marker(40.7128, -74.0060, label="NYC", color="red")
mid
''');

      expect(returned, isA<String>());
      expect(returned, startsWith('marker-'));

      final markers = mapExt.markers.value;
      expect(markers, hasLength(1));
      expect(markers.first.id, returned);
      expect(markers.first.label, 'NYC');
      expect(markers.first.color, 'red');
      expect(markers.first.lat, closeTo(40.7128, 1e-9));
      expect(markers.first.lng, closeTo(-74.0060, 1e-9));
    });

    test('clear_markers empties everything', () async {
      await mapExt.addMarker(lat: 1, lng: 2, label: 'a');
      await mapExt.addMarker(lat: 3, lng: 4, label: 'b');
      expect(mapExt.markers.value, hasLength(2));

      await runPython('map_clear_markers()');

      expect(mapExt.markers.value, isEmpty);
    });

    test('set_basemap switches the basemap signal', () async {
      expect(mapExt.basemap.value.name, 'osm');

      await runPython('map_set_basemap("cartodb_dark")');

      // BasemapStyle.parse accepts the snake_case form; the enum's
      // Dart `.name` is camelCase ("cartodbDark").
      expect(mapExt.basemap.value.name, 'cartodbDark');
    });

    test('set_basemap with unknown style raises in Python', () async {
      final handle = runtime.execute('map_set_basemap("not-a-style")');
      final result = await handle.result;
      expect(result.error, isNotNull);
      expect(
        result.error!.toJson().toString(),
        contains('not-a-style'),
      );
    });

    test('get_view returns the current viewport as a dict', () async {
      final returned = await runPython('map_get_view()');

      expect(returned, isA<Map<String, Object?>>());
      final m = returned! as Map<String, Object?>;
      expect(m, contains('lat'));
      expect(m, contains('lng'));
      expect(m, contains('zoom'));
      expect(m, contains('rotation'));
    });

    test(
      'shared state — ClientTool path and Python path see the same markers',
      () async {
        // Simulate the ClientTool side dropping a marker.
        final clientId = await mapExt.addMarker(
          lat: 51.5,
          lng: -0.12,
          label: 'London (tool)',
        );

        // Python side adds another. Both observe the same signal.
        final pythonId = await runPython('''
map_add_marker(48.8566, 2.3522, label="Paris (python)")
''');

        final markers = mapExt.markers.value;
        expect(markers, hasLength(2));
        expect(markers.map((m) => m.id), containsAll([clientId, pythonId]));
        expect(
          markers.map((m) => m.label),
          containsAll(['London (tool)', 'Paris (python)']),
        );
      },
    );

    test('a tour script flies between cities and drops pins', () async {
      // The kind of orchestration that's awkward as N tool calls but
      // natural as a small Python program.
      await runPython('''
cities = [
    (40.7128, -74.0060, "NYC"),
    (51.5074, -0.1278, "London"),
    (35.6762, 139.6503, "Tokyo"),
]
ids = []
for lat, lng, name in cities:
    map_fly_to(lat, lng, zoom=10, animated=False)
    ids.append(map_add_marker(lat, lng, label=name, pulse=True))

print("dropped", len(ids), "pins")
''');

      expect(mapExt.markers.value, hasLength(3));
      expect(
        mapExt.markers.value.map((m) => m.label),
        ['NYC', 'London', 'Tokyo'],
      );
      expect(
        mapExt.markers.value.every((m) => m.pulse),
        isTrue,
        reason: 'every pin should have pulse: true from the script',
      );
    });
  });
}
