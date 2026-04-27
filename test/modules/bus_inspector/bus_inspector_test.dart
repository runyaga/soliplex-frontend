import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/bus_inspector/bus_inspector.dart';

BusWriteEvent _ev({
  BusWriteKind kind = BusWriteKind.update,
  Map<String, dynamic> before = const {},
  Map<String, dynamic> after = const {'a': 1},
  String? tag,
}) =>
    BusWriteEvent(
      kind: kind,
      before: before,
      after: after,
      timestamp: DateTime(2026, 4, 26, 12),
      tag: tag,
    );

void main() {
  group('BusInspector', () {
    test('starts empty with no latest state', () {
      final inspector = BusInspector();
      expect(inspector.events, isEmpty);
      expect(inspector.latestState, isNull);
      inspector.dispose();
    });

    test('record appends, fires listeners, exposes latestState', () {
      final inspector = BusInspector();
      var fires = 0;
      inspector.addListener(() => fires++);

      inspector.record(_ev(after: {'a': 1}, tag: 't1'));
      inspector.record(_ev(after: {'a': 2}));

      expect(inspector.events, hasLength(2));
      expect(inspector.events.first.tag, 't1');
      expect(inspector.latestState, equals({'a': 2}));
      expect(fires, 2);
      inspector.dispose();
    });

    test('respects maxEvents bound (drops oldest)', () {
      final inspector = BusInspector(maxEvents: 2);

      inspector.record(_ev(after: {'n': 1}, tag: 'one'));
      inspector.record(_ev(after: {'n': 2}, tag: 'two'));
      inspector.record(_ev(after: {'n': 3}, tag: 'three'));

      expect(inspector.events, hasLength(2));
      expect(inspector.events.first.tag, 'two');
      expect(inspector.events.last.tag, 'three');
      expect(inspector.latestState, equals({'n': 3}));
      inspector.dispose();
    });

    test('clear empties the log and fires listeners', () {
      final inspector = BusInspector()..record(_ev());
      var fires = 0;
      inspector.addListener(() => fires++);

      inspector.clear();

      expect(inspector.events, isEmpty);
      expect(inspector.latestState, isNull);
      expect(fires, 1);
      inspector.dispose();
    });

    test('clear when already empty is a no-op (no listener fire)', () {
      final inspector = BusInspector();
      var fires = 0;
      inspector.addListener(() => fires++);

      inspector.clear();

      expect(fires, 0);
      inspector.dispose();
    });

    test('record after dispose is silently ignored', () {
      final inspector = BusInspector()..dispose();

      inspector.record(_ev());

      expect(inspector.events, isEmpty);
    });

    test('rejects non-positive maxEvents at construction', () {
      expect(() => BusInspector(maxEvents: 0), throwsArgumentError);
      expect(() => BusInspector(maxEvents: -1), throwsArgumentError);
    });
  });
}
