import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/bus_inspector.dart';

void main() {
  group('BusInspector', () {
    const key = (
      serverId: 's',
      roomId: 'r',
      threadId: 't',
    );

    test('starts empty', () {
      final inspector = BusInspector();
      addTearDown(inspector.dispose);
      expect(inspector.events, isEmpty);
    });

    test('record appends events with timestamp, key, tag, snapshot', () {
      final inspector = BusInspector()
        ..record(key, 'agui.snapshot', {'a': 1})
        ..record(key, null, {'a': 2});
      addTearDown(inspector.dispose);

      expect(inspector.events, hasLength(2));
      expect(inspector.events[0].threadKey, key);
      expect(inspector.events[0].tag, 'agui.snapshot');
      expect(inspector.events[0].snapshot['a'], 1);
      expect(inspector.events[1].tag, isNull);
      expect(inspector.events[0].timestamp, isA<DateTime>());
    });

    test('record notifies listeners', () {
      final inspector = BusInspector();
      addTearDown(inspector.dispose);
      var calls = 0;
      inspector.addListener(() => calls++);

      inspector.record(key, null, {});
      expect(calls, 1);
    });

    test('overflow drops oldest events', () {
      final inspector = BusInspector(maxEvents: 3);
      addTearDown(inspector.dispose);
      for (var i = 0; i < 5; i++) {
        inspector.record(key, 't$i', {'i': i});
      }
      expect(inspector.events.map((e) => e.tag).toList(), ['t2', 't3', 't4']);
    });

    test('clear empties events and notifies', () {
      final inspector = BusInspector()..record(key, null, {});
      addTearDown(inspector.dispose);
      var clearedNotifications = 0;
      inspector.addListener(() => clearedNotifications++);
      inspector.clear();
      expect(inspector.events, isEmpty);
      expect(clearedNotifications, 1);
    });

    test('record after dispose is a no-op', () {
      final inspector = BusInspector()..dispose();
      // Must not throw or notify (notifyListeners after dispose throws).
      inspector.record(key, null, {});
      // No assertion needed beyond "did not throw".
    });

    test('rejects non-positive maxEvents', () {
      expect(() => BusInspector(maxEvents: 0), throwsArgumentError);
      expect(() => BusInspector(maxEvents: -1), throwsArgumentError);
    });
  });
}
