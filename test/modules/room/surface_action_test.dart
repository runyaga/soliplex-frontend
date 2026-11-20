import 'dart:async';
import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart' show BasicCatalog;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_scope.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_view.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/workbench_host.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/thread_view_state.dart';
import 'package:soliplex_frontend/src/modules/room/ui/message_timeline.dart';
import 'package:soliplex_frontend/src/stores/run_registry.dart';

import '../../helpers/fakes.dart';
import '../../fixtures/workbench_activity_events.dart';

/// Records each run's input and ends it when the test says so.
class _Provider implements AgentLlmProvider {
  final inputs = <SimpleRunAgentInput>[];
  final runs = <StreamController<DecodeOutcome>>[];

  void finish(int run) {
    final runId = 'run-$run';
    for (final event in <BaseEvent>[
      const TextMessageStartEvent(messageId: 'm'),
      const TextMessageContentEvent(messageId: 'm', delta: 'ok'),
      const TextMessageEndEvent(messageId: 'm'),
      RunFinishedEvent(threadId: 'thread-1', runId: runId),
    ]) {
      runs[run].add(DecodedEvent(event, const {}));
    }
    unawaited(runs[run].close());
  }

  @override
  Future<LlmRunHandle> startRun({
    required ThreadKey key,
    required SimpleRunAgentInput input,
    String? existingRunId,
    String? parentRunId,
    CancelToken? cancelToken,
    void Function(ReconnectStatus)? onReconnectStatus,
  }) async {
    final runId = 'run-${inputs.length}';
    inputs.add(input);
    final events = StreamController<DecodeOutcome>()
      ..add(
        DecodedEvent(
          RunStartedEvent(threadId: key.threadId, runId: runId),
          const {},
        ),
      );
    runs.add(events);
    return LlmRunHandle(runId: runId, events: events.stream);
  }

  @override
  LlmRunHandle followRun({
    required ThreadKey key,
    required String runId,
    CancelToken? cancelToken,
    void Function(ReconnectStatus)? onReconnectStatus,
  }) =>
      throw UnsupportedError('No follow fixture');
}

const _userAction = <String, Object?>{
  'name': 'python_failed',
  'surfaceId': 'dojo-python',
  'sourceComponentId': 'repl',
  'timestamp': '2026-11-19T00:00:00Z',
  'context': {
    'result': {'ok': false, 'attempt': 1, 'chainId': 'c1'},
  },
};

/// A basic-catalog button whose click dispatches `python_failed`.
List<Map<String, Object?>> _buttonSurface() => [
      {
        'version': '1.0',
        'createSurface': {
          'surfaceId': 'dojo-python',
          'catalogId': BasicCatalog.v1_0Id,
        },
      },
      {
        'version': '1.0',
        'updateComponents': {
          'surfaceId': 'dojo-python',
          'components': [
            {
              'id': 'root',
              'component': 'Button',
              'child': 'label',
              'action': {
                'event': {
                  'name': 'python_failed',
                  'context': {'attempt': 1},
                },
              }
            },
            {'id': 'label', 'component': 'Text', 'text': 'Report'},
          ],
        },
      },
    ];

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue);
}

void main() {
  testWidgets('a click in a timeline surface reaches onSurfaceAction', (
    tester,
  ) async {
    final received = <(String, Map<String, Object?>)>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          messageExpansionsProvider.overrideWithValue(MessageExpansions()),
        ],
        child: MaterialApp(
          theme: soliplexLightTheme(),
          home: Scaffold(
            body: MessageTimeline(
              roomId: 'r',
              messages: [
                GenUiMessage.create(
                  id: 'surface-message',
                  widgetName: 'a2ui',
                  data: {'messages': _buttonSurface()},
                ),
              ],
              messageStates: const {},
              onSurfaceAction: (id, action) => received.add((id, action)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(received, hasLength(1));
    expect(received.single.$1, 'surface-message');
    expect(received.single.$2['name'], 'python_failed');
    expect(received.single.$2['context'], {'attempt': 1});
  });

  group('ThreadViewState.sendAction', () {
    late _Provider provider;
    late AgentRuntime runtime;
    late ThreadViewState view;
    late RunRegistry registry;

    setUp(() async {
      provider = _Provider();
      final connection = ServerConnection(
        serverId: 'test-server',
        api: FakeSoliplexApi(),
        agUiStreamClient: FakeAgUiStreamClient(),
      );
      runtime = AgentRuntime(
        connection: connection,
        llmProvider: provider,
        toolRegistryResolver: (_) async => const ToolRegistry(),
        platform: TestPlatformConstraints(),
        logger: testLogger(),
        forwardedProps: () => {'bandwidth': 'low'},
      );
      registry = RunRegistry(servers: emptyServers());
      view = ThreadViewState(
        connection: connection,
        auth: AuthSession(refreshService: FakeTokenRefreshService()),
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);
    });

    tearDown(() async {
      view.dispose();
      registry.dispose();
      await runtime.dispose();
    });

    test('starts an action-only run carrying forwardedProps.a2uiAction',
        () async {
      view.sendAction(_userAction, runtime);
      await _until(() => provider.inputs.isNotEmpty);

      final input = provider.inputs.single;
      expect(input.forwardedProps!['bandwidth'], 'low');
      expect(
        (input.forwardedProps!['a2uiAction'] as Map)['userAction'],
        _userAction,
      );
      expect(input.messages!.whereType<UserMessage>(), isEmpty);
      provider.finish(0);
      await _until(() => view.sessionState.value == null);
    });

    testWidgets('canvas Submit sends current values and activity identity',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = ChatSurfaceStore(onAction: (activity, action) {
        view.sendAction(action, runtime, activityMessageId: activity);
      });
      addTearDown(store.dispose);
      var fold = RunFold.start(Conversation.empty(threadId: 'thread-1'),
          runId: 'publication',
          userMessageId: null,
          turnCitations: const TurnCitations.empty(),
          runCreated: DateTime.utc(2026));
      final events = (jsonDecode(publishedEventsJson) as List).take(2).map(
          (event) => ActivitySnapshotEvent.fromJson(
              Map<String, dynamic>.from(event as Map)));
      for (final event in events) {
        fold = fold.apply(DecodedEvent(event, event.toJson())).fold;
      }
      store.ingest(fold.conversation.messages.whereType<GenUiMessage>());
      await tester.pumpWidget(MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(
          body: ChatSurfaceScope(
            store: store,
            child: const ClientWorkbenchPresentation().buildHost(
              roomId: 'room-1',
              threadId: 'thread-1',
              chat: const Text('Chat'),
              surfaceBuilder: (activity, surface) => ChatSurfaceView(
                  controller: store[activity]!, surfaceId: surface),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Current field value');
      await tester.tap(find.text('North'));
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.ensureVisible(find.text('Submit'));
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => _until(() => provider.inputs.isNotEmpty));
      final action =
          provider.inputs.single.forwardedProps!['a2uiAction'] as Map;
      expect(action.keys,
          unorderedEquals(['userAction', 'activityMessageId', 'submissionId']));
      expect(action['activityMessageId'], events.first.messageId);
      expect(action['submissionId'], isA<String>());
      final userAction = action['userAction'] as Map;
      expect(userAction['name'], 'submit_intake');
      expect(userAction['sourceComponentId'], 'submit');
      expect(userAction['surfaceId'], 'surface_2');
      expect(userAction['context'], {
        'question': 'Current field value',
        'districts': ['north'],
        'acknowledged': true,
      });
      expect(
          provider.inputs.single.messages!.whereType<UserMessage>(), isEmpty);
      provider.finish(0);
      await tester
          .runAsync(() => _until(() => view.sessionState.value == null));
    });

    test('PythonRepl result uses the same envelope without a reservation',
        () async {
      final result = <String, Object?>{
        'name': 'workbench.program.run_result',
        'surfaceId': 'program-surface',
        'sourceComponentId': 'root',
        'context': {
          'side': 'client',
          'engine': 'monty-1.3.0',
          'invocationId': 'invocation-1',
          'chainId': 'invocation-1',
          'outcome': 'success',
          'output': 'Hello from REPL',
        },
      };
      view.sendAction(result, runtime, activityMessageId: 'program-activity');
      await _until(() => provider.inputs.isNotEmpty);
      final envelope =
          provider.inputs.single.forwardedProps!['a2uiAction'] as Map;
      expect(envelope.keys,
          unorderedEquals(['userAction', 'activityMessageId', 'submissionId']));
      expect(envelope['activityMessageId'], 'program-activity');
      expect(envelope['submissionId'], isA<String>());
      expect(envelope['userAction'], result);
      expect(
          provider.inputs.single.messages!.whereType<UserMessage>(), isEmpty);
      provider.finish(0);
      await _until(() => view.sessionState.value == null);
    });

    test('distinct submissions queue in order and capture values at click time',
        () async {
      view.sendMessage([const TextPart('working')], runtime);
      await _until(() => provider.inputs.length == 1);
      final mutable = <String, Object?>{
        'name': 'submit_intake',
        'surfaceId': 'form',
        'context': {'question': 'first'},
      };
      view.sendAction(mutable, runtime, activityMessageId: 'form-activity');
      (mutable['context']! as Map)['question'] = 'second';
      view.sendAction(mutable, runtime, activityMessageId: 'form-activity');
      (mutable['context']! as Map)['question'] = 'changed after clicking';
      provider.finish(0);
      await _until(() => provider.inputs.length == 2);
      final first = provider.inputs[1].forwardedProps!['a2uiAction'] as Map;
      expect((first['userAction'] as Map)['context'], {'question': 'first'});
      provider.finish(1);
      await _until(() => provider.inputs.length == 3);
      final second = provider.inputs[2].forwardedProps!['a2uiAction'] as Map;
      expect((second['userAction'] as Map)['context'], {'question': 'second'});
      expect(first['submissionId'], isNot(second['submissionId']));
      provider.finish(2);
      await _until(() => view.sessionState.value == null);
    });

    test('an action during a run waits and is sent once when it ends',
        () async {
      view.sendMessage([const TextPart('make a game')], runtime);
      await _until(() => provider.inputs.length == 1);

      view.sendAction(_userAction, runtime);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(provider.inputs, hasLength(1));

      provider.finish(0);
      await _until(() => provider.inputs.length == 2);
      expect(
        provider.inputs.last.forwardedProps!.containsKey('a2uiAction'),
        isTrue,
      );
      provider.finish(1);
      await _until(() => view.sessionState.value == null);
      expect(provider.inputs, hasLength(2));
    });
  });
}
