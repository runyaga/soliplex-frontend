import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_scope.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_view.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/workbench_host.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

import '../../../../test/fixtures/workbench_activity_events.dart';
import '../../test/support/monty.dart';

void main() {
  for (final enabled in [false, true]) {
    testWidgets('published canvas AI Fix=$enabled uses the real action sink', (
      tester,
    ) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final starter = MontyStarter();
      final actions = <Map<String, Object?>>[];
      final scheduled = <VoidCallback>[];
      PythonReplView.debugScheduleAutoRun = scheduled.add;
      addTearDown(() => PythonReplView.debugScheduleAutoRun = null);
      final store = ChatSurfaceStore(
        onAction: (_, action) => actions.add(action),
        catalogs: [
          labCatalog(
            startRuntime: starter.call,
            isLive: ChatSurfaceOrigin.isLive,
            chains: RepairChains(),
          ),
        ],
      );
      final messages = <String, GenUiMessage>{};
      void publish(String source, String runId) {
        final events =
            (jsonDecode(publishedEventsJson) as List) +
            (jsonDecode(publishedProgramEventsJson) as List);
        for (final raw in events) {
          final event = raw as Map<String, dynamic>;
          final content = event['content'] as Map<String, dynamic>;
          final registration = content['workbenchPublication'] as Map;
          if (registration['role'] == 'program') {
            final ops = content['a2ui_operations'] as List;
            final update = (ops[1] as Map)['updateDataModel'] as Map;
            (update['value'] as Map)['source'] = source;
          }
          messages[event['messageId'] as String] = GenUiMessage.create(
            id: event['messageId'] as String,
            // Activity projection retains its original run id on replacement.
            runId: 'initial',
            widgetName: 'a2ui',
            data: {
              'messages': content['a2ui_operations'],
              'updatedByRunIds': ['initial', runId],
              'workbenchRegistration': registration,
            },
          );
        }
        store.ingest(messages.values, activeRunId: runId);
      }

      publish('raise ValueError("scenario deliberate failure")', 'initial');
      await tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(),
          home: Scaffold(
            body: ChatSurfaceScope(
              store: store,
              child: const ClientWorkbenchPresentation().buildHost(
                roomId: 'room',
                threadId: 'thread',
                chat: const Text('Chat'),
                surfaceBuilder: (activity, surface) => ChatSurfaceView(
                  controller: store[activity]!,
                  surfaceId: surface,
                ),
              ),
            ),
          ),
        ),
      );
      await settleFor(tester, const Duration(milliseconds: 100));
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('AI Fix'), findsOneWidget);
      semantics.dispose();
      final checkbox = find.byKey(const ValueKey('python-repl-auto-fix'));
      final run = find.byKey(const ValueKey('python-repl-run'));
      if (enabled) {
        await tester.runAsync(() => tester.tap(checkbox));
        await tester.pump();
      }
      await tester.runAsync(() => tester.tap(run));
      await pumpUntil(
        tester,
        () => find.textContaining('· failed').evaluate().isNotEmpty,
      );
      expect(actions.length, enabled ? 1 : 0);
      expect(scheduled, isEmpty);
      if (enabled) {
        expect(actions.single['name'], 'workbench.program.repair');
        expect(actions.single['surfaceId'], 'surface_11');
        publish('print(pow(7, 12345, 1000003))', 'repair');
        await settleFor(tester, const Duration(milliseconds: 150));
        expect(tester.widget<Checkbox>(checkbox).value, true);
        expect(scheduled, hasLength(1));
        await tester.runAsync(() async => scheduled.single());
        await pumpUntil(
          tester,
          () => actions.any((a) => a['name'] == 'workbench.program.run_result'),
        );
        final result = actions.last['context']! as Map;
        expect(result['outcome'], 'success');
        expect(result['output'], contains('766228'));
        expect(find.text('766228'), findsOneWidget);
        expect(actions, hasLength(2));
        expect(actions.last['surfaceId'], actions.first['surfaceId']);
        expect(find.byType(PythonReplView), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settleFor(tester, const Duration(milliseconds: 100));
      store.dispose();
      await tester.runAsync(starter.close);
    }, skip: skipWithoutMonty != false);
  }
}
