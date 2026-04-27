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

  group('StateBus distinct-until-changed (write coalescing)', () {
    test('setAgentState with structurally-equal map does not fire observer',
        () {
      final events = <BusWriteEvent>[];
      final bus = StateBus(observer: events.add)
        ..setAgentState(<String, dynamic>{
          'ui': <String, dynamic>{
            'narrations': <Object>[
              <String, dynamic>{'text': 'hello'},
            ],
          },
        });
      expect(events, hasLength(1));

      // Re-submit a freshly-built but structurally-equal map. With
      // distinct-until-changed at the bus boundary the observer must
      // NOT fire and the underlying signal identity must NOT change.
      final identityBefore = bus.agentState.value;
      bus.setAgentState(<String, dynamic>{
        'ui': <String, dynamic>{
          'narrations': <Object>[
            <String, dynamic>{'text': 'hello'},
          ],
        },
      });
      expect(events, hasLength(1), reason: 'observer must not fire on no-op');
      expect(
        identical(bus.agentState.value, identityBefore),
        isTrue,
        reason: 'signal value identity must be preserved on no-op writes',
      );
      bus.dispose();
    });

    test('update() returning structurally-equal map is dropped', () {
      final events = <BusWriteEvent>[];
      final bus = StateBus(observer: events.add)
        ..setAgentState(<String, dynamic>{'count': 1});
      expect(events, hasLength(1));

      // Transform builds a new Map.from(current) — fresh identity,
      // identical content. Must be coalesced.
      bus.update(Map<String, dynamic>.from);
      expect(events, hasLength(1));

      // A real change still fires.
      bus.update(
        (current) => {...current, 'count': 2},
        tag: 'increment',
      );
      expect(events, hasLength(2));
      expect(events.last.tag, 'increment');
      bus.dispose();
    });

    test('applyDelta whose result equals current state is coalesced', () {
      final events = <BusWriteEvent>[];
      final bus = StateBus(observer: events.add)
        ..setAgentState(<String, dynamic>{'a': 1});
      expect(events, hasLength(1));

      // Replace `/a` with the same value — JSON Patch op runs but the
      // resulting state is structurally equal to the current state.
      bus.applyDelta([
        {'op': 'replace', 'path': '/a', 'value': 1},
      ]);
      expect(
        events,
        hasLength(1),
        reason: 'no-op delta must not produce a bus event',
      );

      // Add of a new key fires normally.
      bus.applyDelta([
        {'op': 'add', 'path': '/b', 'value': 2},
      ]);
      expect(events, hasLength(2));
      bus.dispose();
    });

    test('projection signal does not recompute on coalesced writes', () {
      final bus = StateBus()
        ..setAgentState(<String, dynamic>{
          'ui': <String, dynamic>{
            'narrations': <Object>[
              <String, dynamic>{'text': 'one'},
            ],
          },
        });
      final narrations = bus.project(const _NarrationsProjection());
      // Read once to establish the computed's first value.
      final firstValue = narrations.value;
      expect(firstValue, ['one']);

      // No-op write — projection identity should hold steady because
      // the underlying signal didn't fire.
      bus.setAgentState(<String, dynamic>{
        'ui': <String, dynamic>{
          'narrations': <Object>[
            <String, dynamic>{'text': 'one'},
          ],
        },
      });
      expect(identical(narrations.value, firstValue), isTrue);

      // A real write replaces the value.
      bus.setAgentState(<String, dynamic>{
        'ui': <String, dynamic>{
          'narrations': <Object>[
            <String, dynamic>{'text': 'two'},
          ],
        },
      });
      expect(narrations.value, ['two']);
      bus.dispose();
    });
  });
}
