// ignore_for_file: lines_longer_than_80_chars, require_trailing_commas

import 'package:ag_ui/ag_ui.dart';
import 'package:soliplex_client/src/application/a2ui_activity.dart';
import 'package:soliplex_client/src/application/agui_event_processor.dart';
import 'package:soliplex_client/src/application/citation_extractor.dart';
import 'package:soliplex_client/src/application/decode_outcome.dart';
import 'package:soliplex_client/src/application/run_fold.dart';
import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:soliplex_client/src/application/thread_history_replay.dart';
import 'package:soliplex_client/src/domain/activity_record.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:soliplex_client/src/domain/workbench_snapshot.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:test/test.dart';

final _started = DateTime.utc(2026, 11, 11, 12);
final _painted = _started.add(const Duration(seconds: 1));
const _id = 'a2ui-surface-chart-call';

List<Map<String, dynamic>> _operations([String surfaceId = 'chart']) => [
      {
        'version': '1.0',
        'createSurface': {
          'surfaceId': surfaceId,
          'catalogId': 'urn:test:catalog:1',
        },
      },
      {
        'version': '1.0',
        'updateComponents': {
          'surfaceId': surfaceId,
          'components': [
            {'id': 'root', 'component': 'Text', 'text': 'Count'},
          ],
        },
      },
      {
        'version': '1.0',
        'updateDataModel': {
          'surfaceId': surfaceId,
          'path': '/',
          'value': {'count': 3},
        },
      },
    ];

ActivitySnapshotEvent _snapshot({
  Object? content,
  String messageId = _id,
  bool replace = true,
}) =>
    ActivitySnapshotEvent(
      messageId: messageId,
      activityType: a2uiActivityType,
      content: content ?? {'a2ui_operations': _operations()},
      replace: replace,
      timestamp: _painted.millisecondsSinceEpoch,
    );

EventProcessingResult _process(
  Conversation conversation,
  BaseEvent event, {
  DateTime? at,
}) =>
    processEvent(
      conversation,
      const AwaitingText(),
      event,
      createdAt: at ?? _painted,
    );

Conversation _conversation() => Conversation.empty(threadId: 'thread')
    .withStatus(const Running(runId: 'run'));

RunFold _fold({
  List<WorkbenchRegistration> registrations = const [],
}) =>
    RunFold.start(
      Conversation.empty(threadId: 'thread'),
      runId: 'run',
      userMessageId: null,
      turnCitations: const TurnCitations.empty(),
      runCreated: _started,
      registeredWorkbenchActivities: registrations,
    );

void main() {
  group('canonical A2UI activity', () {
    test('retains authenticated workbench metadata in the projection', () {
      final registrations = [
        const WorkbenchRegistration(
          role: WorkbenchRole.content,
          activityMessageId: _id,
          surfaceId: 'chart',
        ),
      ];
      final metadata = {
        'role': 'content',
        'registration': {'activityMessageId': _id, 'surfaceId': 'chart'},
        'sequence': 2,
        'revision': 1,
        'publicationId': 'publication_1',
        'partIndex': 0,
        'partCount': 1,
      };
      final result = projectA2uiActivity(
        _conversation(),
        ActivityRecord(
          messageId: _id,
          activityType: a2uiActivityType,
          content: {'a2ui_operations': _operations(), 'workbench': metadata},
          timestamp: _painted.millisecondsSinceEpoch,
        ),
        createdAt: _painted,
        registeredWorkbenchActivities: registrations,
      );
      expect(
        (result.messages.single as GenUiMessage).data['workbench'],
        metadata,
      );
      final unregistered = projectA2uiActivity(
        _conversation(),
        ActivityRecord(
          messageId: _id,
          activityType: a2uiActivityType,
          content: {'a2ui_operations': _operations(), 'workbench': metadata},
          timestamp: _painted.millisecondsSinceEpoch,
        ),
        createdAt: _painted,
      );
      expect(
        (unregistered.messages.single as GenUiMessage).data,
        isNot(contains('workbench')),
      );
    });

    test('foreign operation surfaces fail when registration is injected', () {
      final metadata = {
        'role': 'content',
        'registration': {'activityMessageId': _id, 'surfaceId': 'chart'},
        'sequence': 2,
        'revision': 1,
        'publicationId': 'publication_1',
        'partIndex': 0,
        'partCount': 1,
      };
      final operations = [
        ..._operations(),
        {
          'version': '1.0',
          'createSurface': {'surfaceId': 'foreign', 'catalogId': 'test'},
        },
      ];
      expect(
        () => projectA2uiActivity(
          _conversation(),
          ActivityRecord(
            messageId: _id,
            activityType: a2uiActivityType,
            content: {'a2ui_operations': operations, 'workbench': metadata},
            timestamp: _painted.millisecondsSinceEpoch,
          ),
          createdAt: _painted,
          registeredWorkbenchActivities: [
            const WorkbenchRegistration(
              role: WorkbenchRole.content,
              activityMessageId: _id,
              surfaceId: 'chart',
            ),
          ],
        ),
        throwsA(isA<MalformedResponseException>()),
      );
    });

    test('unregistered metadata stays on the standard projection path', () {
      final metadata = {
        'role': 'content',
        'registration': {'activityMessageId': _id, 'surfaceId': 'chart'},
        'sequence': 2,
        'revision': 1,
        'publicationId': 'publication_1',
        'partIndex': 0,
        'partCount': 1,
      };
      final result = processEvent(
        _conversation(),
        const AwaitingText(),
        _snapshot(content: {
          'a2ui_operations': _operations(),
          'workbench': metadata,
        }),
        createdAt: _painted,
      );
      expect(result.conversation.messages, hasLength(1));
      expect(
        (result.conversation.messages.single as GenUiMessage).data,
        containsPair('messages', _operations()),
      );
      expect(
        (result.conversation.messages.single as GenUiMessage).data,
        isNot(contains('workbench')),
      );
    });

    test('scalar unregistered metadata stays on the standard path', () {
      final result = processEvent(
        _conversation(),
        const AwaitingText(),
        _snapshot(content: {
          'a2ui_operations': _operations(),
          'status': 'building',
          'workbench': 'unregistered',
        }),
        createdAt: _painted,
      );
      expect(result.conversation.messages, hasLength(1));
      expect(
        (result.conversation.messages.single as GenUiMessage).data,
        containsPair('messages', _operations()),
      );
    });

    test('creates one generated message without adding model history', () {
      final result = _process(_conversation(), _snapshot());
      final message = result.conversation.messages.single as GenUiMessage;
      expect(message.id, _id);
      expect(message.widgetName, 'a2ui');
      expect(message.createdAt, _painted);
      expect(message.runId, 'run');
      expect(message.data, {
        'messages': _operations(),
        'updatedByRunIds': ['run'],
      });
      expect(result.conversation.activities.single.messageId, _id);
      expect(result.conversation.transcript.messages, isEmpty);
    });

    test('duplicate snapshots update one message and retain its position', () {
      final first = _process(_conversation(), _snapshot()).conversation;
      final duplicate = _process(first, _snapshot()).conversation;
      expect(duplicate.messages, hasLength(1));
      expect(
        identical(duplicate.messages.single, first.messages.single),
        isTrue,
      );

      final nextOperations = _operations();
      (nextOperations[2]['updateDataModel'] as Map)['value'] = {'count': 9};
      final next = _process(
        duplicate,
        _snapshot(content: {'a2ui_operations': nextOperations}),
        at: _painted.add(const Duration(seconds: 1)),
      ).conversation;
      final updated = next.messages.single as GenUiMessage;
      expect(updated.data['messages'], nextOperations);
      expect(updated.createdAt, _painted);
      expect(updated.runId, 'run');
      expect(next.transcript.messages, isEmpty);
    });

    test(
        'replace false keeps the prior payload even when replacement '
        'is malformed', () {
      final first = _process(_conversation(), _snapshot()).conversation;
      final next = _process(
        first,
        _snapshot(content: {'a2ui_operations': 'invalid'}, replace: false),
      ).conversation;
      expect(next.messages.single, same(first.messages.single));
      expect(next.activities, first.activities);
    });

    test('lifecycle snapshots are replaced by paint in the same slot', () {
      var conversation = _conversation();
      for (final status in ['building', 'retrying', 'failed']) {
        conversation = _process(
          conversation,
          _snapshot(content: {'status': status, 'attempt': 1}),
        ).conversation;
        final message = conversation.messages.single as GenUiMessage;
        expect(message.data, {'messages': <Object?>[], 'status': status});
      }
      conversation = _process(conversation, _snapshot()).conversation;
      expect(conversation.messages, hasLength(1));
      expect((conversation.messages.single as GenUiMessage).data, {
        'messages': _operations(),
        'updatedByRunIds': ['run'],
      });
      expect(conversation.transcript.messages, isEmpty);
    });

    test(
      'paint acknowledgments preserve original ownership and unique runs',
      () {
        final original = _process(_conversation(), _snapshot()).conversation;
        final firstMessage = original.messages.single as GenUiMessage;
        expect(firstMessage.data['updatedByRunIds'], ['run']);
        final action = _process(
          original.withStatus(const Running(runId: 'action-run')),
          _snapshot(),
        ).conversation;
        final refreshed = action.messages.single as GenUiMessage;
        expect(refreshed.runId, firstMessage.runId);
        expect(refreshed.createdAt, firstMessage.createdAt);
        expect(refreshed.data['updatedByRunIds'], ['run', 'action-run']);
        expect(refreshed.data['messages'], _operations());
        expect(action.transcript.messages, isEmpty);

        final duplicate = _process(action, _snapshot()).conversation;
        expect(duplicate.messages.single, same(refreshed));
        final replacement = _process(
          duplicate.withStatus(const Running(runId: 'third-run')),
          _snapshot(content: {'a2ui_operations': _operations('second')}),
        ).conversation;
        expect(
          (replacement.messages.single as GenUiMessage).data['updatedByRunIds'],
          ['run', 'action-run', 'third-run'],
        );
        expect(replacement.messages.single.runId, 'run');
      },
    );

    test('lifecycle and out-of-run snapshots add no paint acknowledgment', () {
      var conversation = _process(_conversation(), _snapshot()).conversation;
      conversation = conversation.withStatus(const Running(runId: 'unpainted'));
      for (final status in ['building', 'retrying', 'failed']) {
        conversation = _process(
          conversation,
          _snapshot(content: {'status': status}),
        ).conversation;
        expect((conversation.messages.single as GenUiMessage).data, {
          'messages': <Object?>[],
          'status': status,
          'updatedByRunIds': ['run'],
        });
      }
      conversation = _process(
        conversation.withStatus(const Completed()),
        _snapshot(),
      ).conversation;
      expect(
        (conversation.messages.single as GenUiMessage).data['updatedByRunIds'],
        ['run'],
      );

      final outsideRun = _process(
        Conversation.empty(threadId: 'thread'),
        _snapshot(),
      ).conversation;
      expect((outsideRun.messages.single as GenUiMessage).data, {
        'messages': _operations(),
      });
    });

    test('wire content cannot claim acknowledgment for a different run', () {
      final conversation = _process(
        _conversation(),
        _snapshot(
          content: {
            'a2ui_operations': _operations(),
            'updatedByRunIds': ['injected-run'],
          },
        ),
      ).conversation;
      expect(
        (conversation.messages.single as GenUiMessage).data['updatedByRunIds'],
        ['run'],
      );
      final operations = (conversation.messages.single as GenUiMessage)
          .data['messages'] as List<Object?>;
      expect(operations, _operations());
      expect(conversation.transcript.messages, isEmpty);
    });

    test('activity deltas reproject the accepted snapshot', () {
      final first = _process(_conversation(), _snapshot()).conversation;
      final next = _process(
        first,
        const ActivityDeltaEvent(
          messageId: _id,
          activityType: a2uiActivityType,
          patch: [
            {
              'op': 'replace',
              'path': '/a2ui_operations/2/updateDataModel/value/count',
              'value': 8,
            },
          ],
        ),
      ).conversation;
      final messages = (next.messages.single as GenUiMessage).data['messages']
          as List<Object?>;
      final envelope = messages[2]! as Map<String, Object?>;
      final update = envelope['updateDataModel']! as Map<String, Object?>;
      final value = update['value']! as Map<String, Object?>;
      expect(value['count'], 8);
      expect(next.transcript.messages, isEmpty);
    });

    test('deletion removes only the generated tile and allows recreation', () {
      final first = _process(_conversation(), _snapshot()).conversation;
      final deleted = _process(
        first,
        _snapshot(
          content: {
            'a2ui_operations': [
              {
                'version': '1.0',
                'deleteSurface': {'surfaceId': 'chart'},
              },
            ],
          },
        ),
      ).conversation;
      expect(deleted.messages, isEmpty);
      expect(deleted.activities, hasLength(1));
      final duplicateDelete = _process(
        deleted,
        _snapshot(content: {'a2ui_operations': <Object?>[]}),
      ).conversation;
      expect(duplicateDelete.messages, isEmpty);
      expect(
        _process(duplicateDelete, _snapshot()).conversation.messages,
        hasLength(1),
      );
    });

    test('deleting one of several surfaces retains the other', () {
      final result = _process(
        _conversation(),
        _snapshot(
          content: {
            'a2ui_operations': [
              ..._operations(),
              ..._operations('second'),
              {
                'version': '1.0',
                'deleteSurface': {'surfaceId': 'chart'},
              },
            ],
          },
        ),
      ).conversation;
      expect(result.messages, hasLength(1));
    });

    test(
      'message data does not retain aliases to mutable source operations',
      () {
        final operations = _operations();
        final result = _process(
          _conversation(),
          _snapshot(content: {'a2ui_operations': operations}),
        ).conversation;
        (operations[2]['updateDataModel'] as Map)['value'] = {'count': 99};
        expect((result.messages.single as GenUiMessage).data, {
          'messages': _operations(),
          'updatedByRunIds': ['run'],
        });
        expect(result.activities.single.content, {
          'a2ui_operations': _operations(),
        });
      },
    );

    test(
      'other activities and custom events retain their existing behavior',
      () {
        final original = _conversation();
        const custom = CustomEvent(
          name: 'a2ui',
          value: {'messages': <Object?>[]},
        );
        expect(_process(original, custom).conversation.messages, isEmpty);
        final other = _process(
          original,
          const ActivitySnapshotEvent(
            messageId: 'other',
            activityType: 'other-widget',
            content: {'count': 1},
          ),
        ).conversation;
        expect(other.messages, isEmpty);
        expect(other.transcript.messages, hasLength(1));
      },
    );

    test(
      'malformed envelopes become drop tiles without losing valid state',
      () {
        final malformed = <Object?>[
          {'a2ui_operations': null},
          {'a2ui_operations': 'not a list'},
          {
            'a2ui_operations': [null],
          },
          {
            'a2ui_operations': [
              {
                'createSurface': {'surfaceId': 'chart'},
              },
            ],
          },
          {
            'a2ui_operations': [
              {'version': '1.0', 'createSurface': null},
            ],
          },
          {
            'a2ui_operations': [
              {
                'version': '1.0',
                'createSurface': {'surfaceId': ''},
              },
            ],
          },
          {
            'a2ui_operations': [
              {
                'version': '1.0',
                'createSurface': {'surfaceId': 'a'},
                'deleteSurface': {'surfaceId': 'a'},
              },
            ],
          },
          {'status': 'unknown'},
        ];
        for (final content in malformed) {
          var fold = _fold();
          final valid = _snapshot();
          fold = fold.apply(DecodedEvent(valid, valid.toJson())).fold;
          final event = _snapshot(content: content);
          final dropped = fold.apply(DecodedEvent(event, event.toJson()));
          expect(dropped.processed, isNull, reason: '$content');
          expect(
            dropped.fold.conversation.messages.whereType<DroppedEventMessage>(),
            hasLength(1),
          );
          expect(
            dropped.fold.conversation.messages
                .whereType<GenUiMessage>()
                .single
                .data,
            {
              'messages': _operations(),
              'updatedByRunIds': ['run'],
            },
          );
          expect(dropped.fold.conversation.activities.single.content, {
            'a2ui_operations': _operations(),
          });
        }
      },
    );

    test('deltas without a matching canonical snapshot fail visibly', () {
      const event = ActivityDeltaEvent(
        messageId: _id,
        activityType: a2uiActivityType,
        patch: [],
      );
      final result = _fold().apply(DecodedEvent(event, event.toJson()));
      expect(result.processed, isNull);
      expect(
        result.fold.conversation.messages.single,
        isA<DroppedEventMessage>(),
      );
    });

    test(
      'incomplete deltas keep the prior surface and produce a drop tile',
      () {
        final snapshot = _snapshot();
        final fold =
            _fold().apply(DecodedEvent(snapshot, snapshot.toJson())).fold;
        const event = ActivityDeltaEvent(
          messageId: _id,
          activityType: a2uiActivityType,
          patch: [
            {
              'op': 'replace',
              'path': '/a2ui_operations/2/updateDataModel/value/count',
              'value': 99,
            },
            {'op': 'not-an-operation', 'path': '/a2ui_operations'},
          ],
        );
        final result = fold.apply(DecodedEvent(event, event.toJson()));
        expect(result.processed, isNull);
        expect(
          result.fold.conversation.messages.whereType<DroppedEventMessage>(),
          hasLength(1),
        );
        expect(
          result.fold.conversation.messages
              .whereType<GenUiMessage>()
              .single
              .data,
          {
            'messages': _operations(),
            'updatedByRunIds': ['run'],
          },
        );
        expect(result.fold.conversation.activities.single.content, {
          'a2ui_operations': _operations(),
        });
      },
    );

    test(
      'a colliding text message is preserved and the activity is rejected',
      () {
        final text = TextMessage.create(
          id: _id,
          user: ChatUser.assistant,
          text: 'Kept',
        );
        final conversation = _conversation().withAppendedMessage(text);
        expect(
          () => _process(conversation, _snapshot()),
          throwsA(isA<MalformedResponseException>()),
        );
        expect(conversation.messages.single, same(text));
        expect(conversation.activities, isEmpty);
      },
    );

    test(
      'live and stored history use identical generated messages and dates',
      () {
        const registrations = [
          WorkbenchRegistration(
            role: WorkbenchRole.content,
            activityMessageId: _id,
            surfaceId: 'chart',
          ),
        ];
        final metadata = {
          'role': 'content',
          'registration': {'activityMessageId': _id, 'surfaceId': 'chart'},
          'sequence': 1,
          'revision': 1,
          'publicationId': 'publication_1',
          'partIndex': 0,
          'partCount': 1,
        };
        final events = <BaseEvent>[
          RunStartedEvent(
            threadId: 'thread',
            runId: 'run',
            timestamp: _started.millisecondsSinceEpoch,
          ),
          _snapshot(content: {'status': 'building'}),
          _snapshot(content: {
            'a2ui_operations': _operations(),
            'workbench': metadata,
          }),
          _snapshot(content: {
            'a2ui_operations': _operations(),
            'workbench': metadata,
          }),
          const RunFinishedEvent(threadId: 'thread', runId: 'run'),
        ];
        final live = events.fold(
          _fold(registrations: registrations),
          (fold, event) => fold.apply(DecodedEvent(event, event.toJson())).fold,
        );
        final history = replayThreadHistory(
          [
            (
              runId: 'run',
              parentRunId: null,
              created: _started,
              fetchError: null,
              fetchStackTrace: null,
              payload: (
                events: [for (final event in events) event.toJson()],
                userMessage: null,
                toolResults: <ToolMessage>[],
                endsWithToolMessage: false,
              ),
            ),
          ],
          'thread',
          null,
          null,
          {},
          null,
          null,
          observer: null,
          registeredWorkbenchActivities: registrations,
        );
        final streamed =
            live.conversation.messages.whereType<GenUiMessage>().single;
        final replayed = history.messages.whereType<GenUiMessage>().single;
        expect(replayed.id, streamed.id);
        expect(replayed.runId, streamed.runId);
        expect(replayed.createdAt, streamed.createdAt);
        expect(replayed.data, streamed.data);
        expect(streamed.data['workbench'], metadata);
        expect(history.transcript.messages, isEmpty);
      },
    );

    test(
        'history treats metadata without injected registrations as ordinary A2UI',
        () {
      final event = _snapshot(content: {
        'a2ui_operations': _operations(),
        'workbench': {
          'role': 'content',
          'registration': {'activityMessageId': _id, 'surfaceId': 'chart'},
          'sequence': 1,
          'revision': 1,
          'publicationId': 'publication_1',
          'partIndex': 0,
          'partCount': 1,
        },
      });
      final history = replayThreadHistory(
        [
          (
            runId: 'run',
            parentRunId: null,
            created: _started,
            fetchError: null,
            fetchStackTrace: null,
            payload: (
              events: [event.toJson()],
              userMessage: null,
              toolResults: <ToolMessage>[],
              endsWithToolMessage: false,
            ),
          ),
        ],
        'thread',
        null,
        null,
        {},
        null,
        null,
        observer: null,
      );
      final message = history.messages.single as GenUiMessage;
      expect(message.data['messages'], _operations());
      expect(message.data, isNot(contains('workbench')));
    });
  });

  group('A2UI action history', () {
    final priorMessages = [
      {'id': 'question', 'role': 'user', 'content': 'Show counts'},
      {'id': 'reply', 'role': 'assistant', 'content': 'Here are the counts'},
    ];
    final action = {
      'userAction': {
        'name': 'recalculate',
        'surfaceId': 'chart',
        'sourceComponentId': 'button',
        'timestamp': '2026-11-11T12:00:01Z',
        'context': <String, Object?>{},
      },
    };

    test(
      'action replay retains the original question and its run attribution',
      () {
        final questionEvents = <BaseEvent>[
          RunStartedEvent(threadId: 'thread', runId: 'question-run'),
          const TextMessageStartEvent(messageId: 'reply'),
          const TextMessageContentEvent(messageId: 'reply', delta: 'Counts'),
          const TextMessageEndEvent(messageId: 'reply'),
          const RunFinishedEvent(threadId: 'thread', runId: 'question-run'),
        ];
        final actionEvents = <BaseEvent>[
          RunStartedEvent(threadId: 'thread', runId: 'action-run'),
          _snapshot(),
          const RunFinishedEvent(threadId: 'thread', runId: 'action-run'),
        ];
        final history = replayThreadHistory(
          [
            for (final entry in [
              (id: 'question-run', events: questionEvents, isAction: false),
              (id: 'action-run', events: actionEvents, isAction: true),
            ])
              (
                runId: entry.id,
                parentRunId: null,
                created: _started,
                fetchError: null,
                fetchStackTrace: null,
                payload: runPayloadFromJson(
                  {
                    'run_input': {
                      'messages': priorMessages,
                      if (entry.isAction)
                        'forwardedProps': {'a2uiAction': action},
                    },
                    'events': [
                      for (final event in entry.events) event.toJson(),
                    ],
                  },
                  'thread',
                  entry.id,
                ),
              ),
          ],
          'thread',
          null,
          null,
          {},
          null,
          null,
          observer: null,
        );
        final users = history.messages.where(
          (message) => message.user == ChatUser.user,
        );
        expect(users, hasLength(1));
        expect(users.single.id, 'question');
        expect(users.single.runId, 'question-run');
        expect(
          history.messages.whereType<GenUiMessage>().single.runId,
          'action-run',
        );
        expect(history.transcript.messages.map((message) => message.id), [
          'question',
          'reply',
        ]);
      },
    );
  });
}
