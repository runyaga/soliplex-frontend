import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/send_error.dart';
import 'package:soliplex_frontend/src/modules/room/session_spawner.dart';

class _FakeSession implements AgentSession {
  bool cancelCalled = false;
  bool disposeCalled = false;

  @override
  void cancel() => cancelCalled = true;

  @override
  void dispose() => disposeCalled = true;

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  group('SessionSpawner', () {
    late SessionSpawner spawner;
    late Signal<SendError?> errorSignal;
    late List<AgentSessionState?> transitions;

    setUp(() {
      spawner = SessionSpawner();
      errorSignal = Signal(null);
      transitions = [];
    });

    tearDown(() {
      errorSignal.dispose();
    });

    void Function(AgentSessionState?) recordTransition() => transitions.add;

    test('isSpawning starts false', () {
      expect(spawner.isSpawning, isFalse);
    });

    test('spawn emits spawning transition immediately', () async {
      final completer = Completer<AgentSession>();

      unawaited(
        spawner.spawn(
          spawnFn: () => completer.future,
          errorSignal: errorSignal,
          prompt: 'test',
          isDisposed: () => false,
          onSpawned: (_) {},
          onStateTransition: recordTransition(),
        ),
      );

      expect(transitions, [AgentSessionState.spawning]);
      expect(spawner.isSpawning, isTrue);
      completer.complete(_FakeSession());
      await Future<void>.delayed(Duration.zero);
    });

    test('spawn calls onSpawned with the session', () async {
      final session = _FakeSession();
      AgentSession? received;

      await spawner.spawn(
        spawnFn: () async => session,
        errorSignal: errorSignal,
        prompt: 'test',
        isDisposed: () => false,
        onSpawned: (s) => received = s,
        onStateTransition: recordTransition(),
      );

      expect(received, same(session));
    });

    test('spawn does NOT emit null transition after success', () async {
      // On success the caller's onSpawned updates lifecycle state via the
      // session it received; the spawner must not overwrite that.
      await spawner.spawn(
        spawnFn: () async => _FakeSession(),
        errorSignal: errorSignal,
        prompt: 'test',
        isDisposed: () => false,
        onSpawned: (_) {},
        onStateTransition: recordTransition(),
      );

      expect(transitions, [AgentSessionState.spawning]);
    });

    test('spawn clears error signal before starting', () async {
      errorSignal.value = SendError(Exception('old'));

      await spawner.spawn(
        spawnFn: () async => _FakeSession(),
        errorSignal: errorSignal,
        prompt: 'test',
        isDisposed: () => false,
        onSpawned: (_) {},
        onStateTransition: recordTransition(),
      );

      expect(errorSignal.value, isNull);
    });

    test('concurrent spawn is a no-op while another is in flight', () async {
      final firstCompleter = Completer<AgentSession>();
      var spawnCount = 0;

      unawaited(
        spawner.spawn(
          spawnFn: () {
            spawnCount++;
            return firstCompleter.future;
          },
          errorSignal: errorSignal,
          prompt: 'first',
          isDisposed: () => false,
          onSpawned: (_) {},
          onStateTransition: recordTransition(),
        ),
      );

      // Second spawn while first is pending — should be ignored.
      await spawner.spawn(
        spawnFn: () {
          spawnCount++;
          return Future.value(_FakeSession());
        },
        errorSignal: errorSignal,
        prompt: 'second',
        isDisposed: () => false,
        onSpawned: (_) {},
        onStateTransition: recordTransition(),
      );

      expect(spawnCount, 1);
      firstCompleter.complete(_FakeSession());
      await Future<void>.delayed(Duration.zero);
    });

    test('spawn on error sets errorSignal when not disposed', () async {
      final error = Exception('spawn failed');

      await spawner.spawn(
        spawnFn: () async => throw error,
        errorSignal: errorSignal,
        prompt: 'my prompt',
        isDisposed: () => false,
        onSpawned: (_) {},
        onStateTransition: recordTransition(),
      );

      expect(errorSignal.value, isNotNull);
      expect(errorSignal.value!.unsentText, 'my prompt');
    });

    test('spawn on error suppressed when isDisposed returns true', () async {
      await spawner.spawn(
        spawnFn: () async => throw Exception('boom'),
        errorSignal: errorSignal,
        prompt: 'test',
        isDisposed: () => true,
        onSpawned: (_) {},
        onStateTransition: recordTransition(),
      );

      expect(errorSignal.value, isNull);
    });

    test('spawn emits null transition on error', () async {
      await spawner.spawn(
        spawnFn: () async => throw Exception('boom'),
        errorSignal: errorSignal,
        prompt: 'test',
        isDisposed: () => false,
        onSpawned: (_) {},
        onStateTransition: recordTransition(),
      );

      expect(transitions, [AgentSessionState.spawning, null]);
    });

    group('cancel', () {
      test('returns false when nothing is pending', () {
        expect(spawner.cancel(), isFalse);
      });

      test('returns true when a spawn is pending', () async {
        final completer = Completer<AgentSession>();

        unawaited(
          spawner.spawn(
            spawnFn: () => completer.future,
            errorSignal: errorSignal,
            prompt: 'test',
            isDisposed: () => false,
            onSpawned: (_) {},
            onStateTransition: recordTransition(),
          ),
        );

        expect(spawner.cancel(), isTrue);
        completer.complete(_FakeSession());
        await Future<void>.delayed(Duration.zero);
      });

      test('cancel does not emit a null transition — caller clears state',
          () async {
        final completer = Completer<AgentSession>();

        unawaited(
          spawner.spawn(
            spawnFn: () => completer.future,
            errorSignal: errorSignal,
            prompt: 'test',
            isDisposed: () => false,
            onSpawned: (_) {},
            onStateTransition: recordTransition(),
          ),
        );

        spawner.cancel();
        completer.complete(_FakeSession());
        await Future<void>.delayed(Duration.zero);

        expect(transitions, [AgentSessionState.spawning]);
        expect(spawner.isSpawning, isFalse);
      });

      test('cancelled spawn does not call onSpawned', () async {
        final completer = Completer<AgentSession>();
        var spawnedCalled = false;

        unawaited(
          spawner.spawn(
            spawnFn: () => completer.future,
            errorSignal: errorSignal,
            prompt: 'test',
            isDisposed: () => false,
            onSpawned: (_) => spawnedCalled = true,
            onStateTransition: recordTransition(),
          ),
        );

        spawner.cancel();
        completer.complete(_FakeSession());
        await Future<void>.delayed(Duration.zero);

        expect(spawnedCalled, isFalse);
      });

      test('cancel then spawnFn throws suppresses the error', () async {
        final completer = Completer<AgentSession>();

        final future = spawner.spawn(
          spawnFn: () => completer.future,
          errorSignal: errorSignal,
          prompt: 'test',
          isDisposed: () => false,
          onSpawned: (_) {},
          onStateTransition: recordTransition(),
        );

        spawner.cancel();
        completer.completeError(Exception('after-cancel'));
        await future;

        expect(errorSignal.value, isNull);
      });
    });
  });
}
