import 'dart:async';
import 'dart:convert';

import 'package:dart_monty/dart_monty.dart' hide CancelToken;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_scope.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_view.dart';
import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/file_downloads_registry.dart';
import 'package:soliplex_frontend/src/modules/room/file_sort_preference.dart';
import 'package:soliplex_frontend/src/modules/room/ui/chat_input.dart';
import 'package:soliplex_frontend/src/modules/room/ui/room_screen.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker_registry.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/workbench_host.dart';
import 'package:soliplex_frontend/src/stores/document_selections.dart';
import 'package:soliplex_frontend/src/stores/run_registry.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

import '../../../../test/fixtures/workbench_activity_events.dart';
import '../../../../test/helpers/fakes.dart';
import '../../../../test/helpers/test_server_entry.dart';
import '../../test/support/monty.dart';

void main() {
  for (final liveDelivery in [true, false]) {
    for (final program in [true, false]) {
      final delivery = liveDelivery ? 'live' : 'history';
      final control = program ? 'canvas window Run' : 'sidebar Submit';
      testWidgets(
        '$delivery $control forwards current values to the room action sink',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1600, 1600);
          addTearDown(tester.view.reset);
          final starter = MontyStarter();
          var starts = 0;
          Future<MontyRuntime> startRuntime(
            ResourceLimits limits,
            Map<String, Object?> modules,
          ) async {
            starts++;
            // Browser seam tests use a bridge result fixture; native tests
            // also execute the actual Python source in the Monty worker.
            if (kIsWeb) return _OutputRuntime();
            return starter.call(limits, modules);
          }

          final messages = <String, GenUiMessage>{};
          final publications =
              (jsonDecode(publishedEventsJson) as List) +
              (jsonDecode(publishedProgramEventsJson) as List);
          for (final raw in publications) {
            final event = raw as Map<String, dynamic>;
            final content = event['content'] as Map<String, dynamic>;
            if (program && event['messageId'] == 'activity_10') {
              final operations = content['a2ui_operations'] as List;
              final data = (operations[1] as Map)['updateDataModel'] as Map;
              final value = data['value'] as Map;
              value['source'] = 'print(pow(7, 12345, 1000003))';
            }
            messages[event['messageId'] as String] = GenUiMessage.create(
              id: event['messageId'] as String,
              widgetName: 'a2ui',
              data: {
                'messages': content['a2ui_operations'],
                'workbenchRegistration': content['workbenchPublication'],
              },
            );
          }
          final stream = _PublicationStream();
          addTearDown(stream.publication.close);
          final api = FakeSoliplexApi()
            ..nextRooms = [const Room(id: 'room', name: 'Workbench')]
            ..nextRoom = const Room(id: 'room', name: 'Workbench')
            ..nextThreads = [
              ThreadInfo(
                id: 'thread',
                roomId: 'room',
                createdAt: DateTime.utc(2026),
              ),
            ]
            ..nextThreadHistory = ThreadHistory(
              messages: liveDelivery ? [] : messages.values.toList(),
            )
            ..nextCreateRun = RunInfo(
              id: 'publication-run',
              threadId: 'thread',
              createdAt: DateTime.utc(2026),
            );
          final entry = createTestServerEntry(
            api: api,
            agUiStreamClient: stream,
          );
          final servers = Signal({entry.serverId: entry});
          AgentRuntimeManager newRuntimeManager() => AgentRuntimeManager(
            platform: TestPlatformConstraints(),
            toolRegistryResolver: (_) async => const ToolRegistry(),
            logger: testLogger(),
            forwardedPropsFor: (_) =>
                () => const {},
            servers: servers,
          );
          var runtimeManager = newRuntimeManager();
          var registry = RunRegistry(servers: servers);
          final uploads = UploadTrackerRegistry(servers: servers);
          final downloads = FileDownloadsRegistry(servers: servers);
          addTearDown(() async {
            await runtimeManager.dispose();
            registry.dispose();
            uploads.dispose();
            downloads.dispose();
            servers.dispose();
          });
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            await tester.runAsync(starter.close);
          });
          Widget app() => MaterialApp(
            theme: soliplexLightTheme(),
            home: RoomScreen(
              appName: 'Test',
              serverEntry: entry,
              roomId: 'room',
              threadId: 'thread',
              runtimeManager: runtimeManager,
              registry: registry,
              uploadRegistry: uploads,
              downloadRegistry: downloads,
              fileSort: FileSortPreference(),
              documentSelections: DocumentSelections(),
              surfaceCatalogs: [labCatalog(startRuntime: startRuntime)],
              workbenchPresentation: const ClientWorkbenchPresentation(),
            ),
          );
          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
          if (liveDelivery) {
            await tester.enterText(
              find.descendant(
                of: find.byType(ChatInput),
                matching: find.byType(TextField),
              ),
              'Publish',
            );
            await tester.pump();
            await tester.tap(find.byIcon(Icons.send));
            await pumpUntil(tester, () => stream.inputs.isNotEmpty);
            expect(stream.inputs, hasLength(1));
            stream.publish([
              RunStartedEvent(threadId: 'thread', runId: 'publication-run'),
              for (final raw in publications)
                ActivitySnapshotEvent.fromJson(raw as Map<String, dynamic>),
              const RunFinishedEvent(
                threadId: 'thread',
                runId: 'publication-run',
              ),
            ]);
            await tester.runAsync(stream.publication.close);
            await tester.pumpAndSettle();
          }
          api.nextCreateRun = RunInfo(
            id: 'submission-run',
            threadId: 'thread',
            createdAt: DateTime.utc(2026),
          );
          final initialRuns = stream.inputs.length;
          final store = ChatSurfaceScope.maybeOf(
            tester.element(find.byType(WorkbenchHost)),
          )!;
          expect(store.layoutError, isNull);
          expect(starts, 0);
          expect(stream.inputs, hasLength(initialRuns));
          if (program) {
            final run = find.byKey(const ValueKey('python-repl-run'));
            await tester.ensureVisible(run);
            await tester.pumpAndSettle();
            await tester.runAsync(() => tester.tap(run));
            await pumpUntil(
              tester,
              () =>
                  store['activity_10']!.surfaces.single.dataModel.get(
                        '/output/output',
                      )
                      is String,
            );
            await tester.pumpAndSettle();
            expect(starts, 1);
            await pumpUntil(
              tester,
              () => stream.inputs.length == initialRuns + 1,
            );
            expect(stream.inputs, hasLength(initialRuns + 1));
            final envelope =
                (stream.inputs.last.forwardedProps as Map)['a2uiAction'] as Map;
            expect(envelope['activityMessageId'], 'activity_10');
            final action = envelope['userAction'] as Map;
            expect(action['name'], 'workbench.program.run_result');
            final context = action['context'] as Map;
            expect(context['output'], '766228');
            expect(context['side'], 'client');
            expect(context['outcome'], 'success');
            expect(action['sourceComponentId'], 'root');
            // Persist the local result, then prove reload remains passive.
            final saved = store['activity_10']!.snapshot();
            messages['activity_10'] = GenUiMessage.create(
              id: 'activity_10',
              widgetName: 'a2ui',
              data: {
                ...messages['activity_10']!.data,
                'messages': saved['messages'],
              },
            );
          } else {
            await tester.enterText(
              find
                  .descendant(
                    of: find.byType(ChatSurfaceView),
                    matching: find.byType(TextField),
                  )
                  .first,
              'Scenario zebra',
            );
            await tester.tap(find.text('North').first);
            await tester.tap(
              find.descendant(
                of: find.widgetWithText(ChatSurfaceView, 'Acknowledged'),
                matching: find.byType(Checkbox),
              ),
            );
            await tester.pump();
            await tester.ensureVisible(find.text('Submit'));
            await tester.tap(find.text('Submit'));
            await tester.pumpAndSettle();
            await pumpUntil(
              tester,
              () => stream.inputs.length == initialRuns + 1,
            );
            expect(stream.inputs, hasLength(initialRuns + 1));
            final envelope =
                (stream.inputs.last.forwardedProps as Map)['a2uiAction'] as Map;
            expect(envelope['activityMessageId'], 'activity_1');
            final action = envelope['userAction'] as Map;
            expect(action['name'], 'submit_intake');
            expect(action['context'], {
              'question': 'Scenario zebra',
              'districts': ['north'],
              'acknowledged': true,
            });
          }
          expect(
            stream.inputs.last.messages!.whereType<UserMessage>(),
            hasLength(liveDelivery ? 1 : 0),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          await tester.runAsync(runtimeManager.dispose);
          registry.dispose();
          runtimeManager = newRuntimeManager();
          registry = RunRegistry(servers: servers);
          api.nextThreadHistory = ThreadHistory(
            messages: messages.values.toList(),
          );
          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
          await settleFor(tester);
          expect(starts, program ? 1 : 0);
          expect(stream.inputs, hasLength(initialRuns + 1));
          expect(tester.takeException(), isNull);
        },
        skip: program && !kIsWeb && skipWithoutMonty != false,
      );
    }
  }
}

class _PublicationStream extends RecordingAgUiStreamClient {
  final publication = StreamController<DecodeOutcome>.broadcast();

  void publish(List<BaseEvent> events) {
    for (final event in events) {
      publication.add(DecodedEvent(event, event.toJson()));
    }
  }

  @override
  Stream<DecodeOutcome> runAgent(
    String endpoint,
    SimpleRunAgentInput input, {
    CancelToken? cancelToken,
    ResumePolicy? resumePolicy,
    void Function(ReconnectStatus)? onReconnectStatus,
  }) {
    inputs.add(input);
    final props = input.forwardedProps as Map?;
    if (inputs.length == 1 && props?['a2uiAction'] == null) {
      return publication.stream;
    }
    return Stream.fromIterable([
      for (final event in <BaseEvent>[
        RunStartedEvent(threadId: 'thread', runId: 'submission-run'),
        const RunFinishedEvent(threadId: 'thread', runId: 'submission-run'),
      ])
        DecodedEvent(event, event.toJson()),
    ]);
  }
}

// A browser test needs no native process to exercise the real REPL callback,
// output binding, room sink and action-only turn.
class _OutputRuntime implements MontyRuntime {
  @override
  ExecutionHandle execute(
    String code, {
    OsHandler? os,
    Map<String, Object?>? inputs,
  }) {
    expect(code, 'print(pow(7, 12345, 1000003))');
    return ExecutionHandle(
      events: Stream.value(
        const BridgeRunFinished(
          threadId: 'thread',
          runId: 'execution',
          printOutput: '766228\n',
        ),
      ),
      result: Future.value(const MontyNone()),
      executionId: 'execution',
      cancel: () async {},
    );
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
