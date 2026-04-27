import 'package:soliplex_client/src/application/rag_snapshot.dart';
import 'package:soliplex_client/src/application/state_bus.dart';
import 'package:soliplex_client/src/domain/surface.dart';
import 'package:test/test.dart';

class _NarrationsProjection extends StateProjection<List<String>> {
  const _NarrationsProjection();

  @override
  List<String> project(Map<String, dynamic> agentState) {
    final ui = agentState['ui'];
    if (ui is! Map<String, dynamic>) return const [];
    final raw = ui['narrations'];
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry is Map && entry['text'] is String) entry['text'] as String,
    ];
  }
}

void main() {
  group('StateBus', () {
    test('starts with frozen empty agent state', () {
      final bus = StateBus();
      expect(bus.agentState.value, isEmpty);
      // Frozen — direct mutation must throw.
      expect(
        () => bus.agentState.value['x'] = 1,
        throwsA(isA<UnsupportedError>()),
      );
      bus.dispose();
    });

    test('setAgentState replaces and exposes a frozen view', () {
      final bus = StateBus()
        ..setAgentState(<String, dynamic>{
          'ui': <String, dynamic>{
            'narrations': <Object>[],
            'hud': <String, dynamic>{},
          },
        });
      expect(bus.agentState.value['ui'], isA<Map<String, dynamic>>());
      // The top-level map is unmodifiable.
      expect(
        () => bus.agentState.value['ui'] = <String, dynamic>{},
        throwsA(isA<UnsupportedError>()),
      );
      bus.dispose();
    });

    test('projection signal updates on each setAgentState', () {
      final bus = StateBus();
      final narrations =
          bus.project<List<String>>(const _NarrationsProjection());
      expect(narrations.value, isEmpty);

      bus.setAgentState({
        'ui': {
          'narrations': [
            {'actor': 'coordinator', 'text': 'first line'},
          ],
        },
      });
      expect(narrations.value, ['first line']);

      bus.setAgentState({
        'ui': {
          'narrations': [
            {'actor': 'coordinator', 'text': 'first line'},
            {'actor': 'primary', 'text': 'second line'},
          ],
        },
      });
      expect(narrations.value, ['first line', 'second line']);

      bus.dispose();
    });

    test('update() runs a transform over the current map', () {
      final bus = StateBus(initialAgentState: {'count': 1})
        ..update((current) => {'count': (current['count'] as int) + 1});
      expect(bus.agentState.value['count'], 2);
      bus.dispose();
    });

    test('dispose is idempotent and stops further updates', () {
      final bus = StateBus()
        ..setAgentState({'a': 1})
        ..dispose();
      expect(bus.isDisposed, isTrue);
      // A second dispose is a no-op (no throw).
      bus.dispose();
    });

    test(
      'RagSnapshotProjection conforms to StateProjection and produces '
      'a typed snapshot from the rag namespace',
      () {
        final bus = StateBus();
        final ragSignal =
            bus.project<RagSnapshot?>(const RagSnapshotProjection());
        expect(ragSignal.value, isNull);

        bus.setAgentState({
          'rag': {
            'citation_index': <String, dynamic>{},
            'citations': <String>[],
          },
        });
        expect(ragSignal.value, isA<RagV042Snapshot>());
        bus.dispose();
      },
    );
  });

  group('StateBus observer', () {
    test('fires on setAgentState with snapshot kind and tag', () {
      final events = <BusWriteEvent>[];
      final bus = StateBus(observer: events.add)
        ..setAgentState(const {'a': 1}, tag: 'snap-1')
        ..setAgentState(const {'a': 2});

      expect(events, hasLength(2));
      expect(events[0].kind, BusWriteKind.snapshot);
      expect(events[0].before, isEmpty);
      expect(events[0].after, equals(<String, dynamic>{'a': 1}));
      expect(events[0].tag, 'snap-1');
      expect(events[1].before, equals(<String, dynamic>{'a': 1}));
      expect(events[1].after, equals(<String, dynamic>{'a': 2}));
      expect(events[1].tag, isNull);
      bus.dispose();
    });

    test('fires on update with update kind', () {
      final events = <BusWriteEvent>[];
      final bus = StateBus(observer: events.add)
        ..setAgentState(const {'count': 1})
        ..update(
          (current) => {...current, 'count': (current['count'] as int) + 1},
          tag: 'increment',
        );

      expect(events, hasLength(2));
      expect(events[1].kind, BusWriteKind.update);
      expect(events[1].before, equals(<String, dynamic>{'count': 1}));
      expect(events[1].after, equals(<String, dynamic>{'count': 2}));
      expect(events[1].tag, 'increment');
      bus.dispose();
    });

    test('event payloads are frozen', () {
      final events = <BusWriteEvent>[];
      final bus = StateBus(observer: events.add)..setAgentState(const {'a': 1});
      expect(
        () => events.single.after['a'] = 99,
        throwsA(isA<UnsupportedError>()),
      );
      bus.dispose();
    });

    test('does not fire after dispose', () {
      final events = <BusWriteEvent>[];
      StateBus(observer: events.add)
        ..setAgentState(const {'a': 1})
        ..dispose()
        ..setAgentState(const {'a': 2});
      expect(events, hasLength(1));
    });

    test('absent observer is a no-op (no throw)', () {
      final bus = StateBus()
        ..setAgentState(const {'a': 1})
        ..update((current) => {...current, 'b': 2});
      expect(bus.agentState.value, equals(<String, dynamic>{'a': 1, 'b': 2}));
      bus.dispose();
    });
  });

  group('StateBus applyDelta', () {
    test('add op extends the state', () {
      final bus = StateBus()
        ..applyDelta([
          {'op': 'add', 'path': '/name', 'value': 'alice'},
        ]);
      expect(bus.agentState.value, equals({'name': 'alice'}));
      bus.dispose();
    });

    test('replace op overwrites an existing value', () {
      final bus = StateBus(initialAgentState: const {'count': 0})
        ..applyDelta([
          {'op': 'replace', 'path': '/count', 'value': 1},
        ]);
      expect(bus.agentState.value, equals({'count': 1}));
      bus.dispose();
    });

    test('remove op deletes a key', () {
      final bus = StateBus(initialAgentState: const {'a': 1, 'b': 2})
        ..applyDelta([
          {'op': 'remove', 'path': '/a'},
        ]);
      expect(bus.agentState.value, equals({'b': 2}));
      bus.dispose();
    });

    test('append-to-array via /-/ path appends', () {
      final bus = StateBus(
        initialAgentState: const {
          'ui': {'narrations': <dynamic>[]},
        },
      )..applyDelta([
          {
            'op': 'add',
            'path': '/ui/narrations/-',
            'value': {'actor': 'primary', 'text': 'hi'},
          },
        ]);
      final entries =
          (bus.agentState.value['ui']! as Map)['narrations']! as List;
      expect(entries.single, equals({'actor': 'primary', 'text': 'hi'}));
      bus.dispose();
    });

    test('multiple ops apply in sequence', () {
      final bus = StateBus()
        ..applyDelta([
          {'op': 'add', 'path': '/a', 'value': 1},
          {'op': 'add', 'path': '/b', 'value': 2},
          {'op': 'replace', 'path': '/a', 'value': 99},
        ]);
      expect(bus.agentState.value, equals({'a': 99, 'b': 2}));
      bus.dispose();
    });

    test('empty operations list is a no-op (no observer fire)', () {
      final events = <BusWriteEvent>[];
      final bus = StateBus(observer: events.add)..applyDelta(const []);
      expect(events, isEmpty);
      expect(bus.agentState.value, isEmpty);
      bus.dispose();
    });

    test('observer fires once per applyDelta call with kind update', () {
      final events = <BusWriteEvent>[];
      final bus = StateBus(observer: events.add)
        ..applyDelta(
          [
            {'op': 'add', 'path': '/a', 'value': 1},
          ],
          tag: 'ag-ui-delta',
        );

      expect(events, hasLength(1));
      expect(events.single.kind, BusWriteKind.update);
      expect(events.single.tag, 'ag-ui-delta');
      expect(events.single.before, isEmpty);
      expect(events.single.after, equals({'a': 1}));
      bus.dispose();
    });

    test('after applyDelta agentState is frozen', () {
      final bus = StateBus()
        ..applyDelta([
          {'op': 'add', 'path': '/a', 'value': 1},
        ]);
      expect(
        () => bus.agentState.value['x'] = 1,
        throwsA(isA<UnsupportedError>()),
      );
      bus.dispose();
    });

    test('does not fire after dispose', () {
      final events = <BusWriteEvent>[];
      StateBus(observer: events.add)
        ..dispose()
        ..applyDelta([
          {'op': 'add', 'path': '/a', 'value': 1},
        ]);
      expect(events, isEmpty);
    });
  });
}
