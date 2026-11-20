import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_scope.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_view.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/workbench_host.dart';
import 'package:soliplex_monty/soliplex_monty.dart';
import 'package:soliplex_monty/src/program_type_check.dart';

import '../../test/fixtures/repair_delivery.dart';
import '../../test/support/monty.dart';

class _DelayedPreferences extends InMemorySharedPreferencesStore {
  _DelayedPreferences(super.data) : super.withData();
  final ready = Completer<void>();

  @override
  Future<Map<String, Object>> getAll() async {
    await ready.future;
    return super.getAll();
  }
}

class _Canvas {
  _Canvas(this.tester, this.demo) {
    store = ChatSurfaceStore(
      onAction: (_, action) => actions.add(action),
      catalogs: [
        labCatalog(
          startRuntime: starter.call,
          checkTypes: (source, limits) => checkProgramTypes(
            source,
            limits,
            workerLocation: montyWorker,
          ),
          isLive: ChatSurfaceOrigin.isLive,
          activeRunId: ChatSurfaceScope.activeRunIdOf,
          chains: RepairChains(),
        ),
      ],
    );
  }
  final WidgetTester tester;
  final String demo;
  final starter = MontyStarter();
  final actions = <Map<String, Object?>>[];
  final messages = <String, GenUiMessage>{};
  final turn = ValueNotifier<String?>(null);
  late final ChatSurfaceStore store;
  final scheduled = <VoidCallback>[];
  final Finder checkbox = find.byKey(const ValueKey('python-repl-auto-fix'));
  final Finder typeCheck = find.byKey(const ValueKey('python-repl-type-check'));
  final Finder run = find.byKey(const ValueKey('python-repl-run'));

  void publish(String stage, {bool live = true, bool completed = false}) {
    final fixtures = jsonDecode(repairDeliveryJson) as Map;
    for (final raw in (fixtures[demo] as Map)[stage] as List) {
      final event = raw as Map;
      final content = event['content'] as Map;
      final id = event['messageId'] as String;
      messages[id] = GenUiMessage.create(
        id: id,
        runId: 'initial', // Real projection retains the first run's identity.
        widgetName: 'a2ui',
        data: {
          'messages': content['a2ui_operations'],
          'updatedByRunIds': ['initial', if (stage == 'repair') 'repair'],
          'workbenchRegistration': content['workbenchPublication'],
        },
      );
    }
    store.ingest(
      messages.values,
      activeRunId: live && !completed ? stage : null,
    );
  }

  Future<void> mount({bool live = true}) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1600, 1600);
    addTearDown(tester.view.reset);
    PythonReplView.debugScheduleAutoRun = scheduled.add;
    addTearDown(() => PythonReplView.debugScheduleAutoRun = null);
    publish('initial', live: live);
    await tester.pumpWidget(
      MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: turn,
            builder: (context, activeRunId, _) => ChatSurfaceScope(
              store: store,
              activeRunId: activeRunId,
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
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await settleFor(tester, const Duration(milliseconds: 80));
      store.dispose();
      turn.dispose();
      await tester.runAsync(starter.close);
    });
    await settleFor(tester, const Duration(milliseconds: 80));
  }

  Future<void> clickRun() async {
    await tester.runAsync(() => tester.tap(run));
    await pumpUntil(
      tester,
      () => find.textContaining('· failed').evaluate().isNotEmpty,
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final demo in ['syntax_error', 'name_error', 'type_check']) {
    testWidgets(
      'real canvas $demo repair waits for preferences and runs once',
      (tester) async {
        final canvas = _Canvas(tester, demo);
        await canvas.mount(
          live: false,
        ); // An existing program from thread history.
        expect(canvas.scheduled, isEmpty);
        expect(canvas.starter.starts, 0);
        expect(
          tester.widget<Checkbox>(canvas.typeCheck).value,
          demo == 'type_check',
        );
        await tester.runAsync(() => tester.tap(canvas.checkbox));
        await tester.pump();
        await canvas.clickRun();
        expect(canvas.actions, hasLength(1));
        final failure =
            (canvas.actions.single['context']! as Map)['result']! as Map;
        expect(failure['autoRun'], true);
        expect(
          failure['error'],
          contains(switch (demo) {
            'syntax_error' => 'SyntaxError',
            'name_error' => 'NameError',
            _ => 'unsupported-operator',
          }),
        );
        if (demo == 'type_check') {
          expect(failure['output'], isNot(contains('766228')));
        }
        final semantics = tester.ensureSemantics();
        expect(find.bySemanticsLabel('Fix now'), findsOneWidget);
        semantics.dispose();
        canvas.turn.value = 'repair';
        await tester.pump();
        // A replacement remounts the editor. Hold the actual preference read
        // across both that mount and completion of the model's streaming turn.
        SharedPreferences.resetStatic();
        final preferences = _DelayedPreferences({
          'flutter.soliplex.python.aiFix.surface_2': true,
        });
        SharedPreferencesStorePlatform.instance = preferences;
        if (demo == 'name_error') {
          // A fast final stream batch can contain replacement and RUN_FINISHED
          // before Flutter renders either one.
          canvas.store.ingest(canvas.messages.values, activeRunId: 'repair');
          canvas.turn.value = null;
          canvas.publish('repair', completed: true);
        } else {
          canvas.publish('repair');
        }
        await tester.pump();
        canvas.turn.value = null;
        await tester.pump();
        expect(canvas.scheduled, isEmpty);
        preferences.ready.complete();
        await settleFor(tester, const Duration(milliseconds: 150));
        expect(canvas.scheduled, hasLength(1));
        expect(tester.widget<Checkbox>(canvas.checkbox).value, true);
        await tester.runAsync(() async => canvas.scheduled.single());
        await pumpUntil(
          tester,
          () => canvas.actions.any(
            (a) => a['name'] == 'workbench.program.run_result',
          ),
        );
        expect(canvas.actions, hasLength(2));
        final result = canvas.actions.last['context']! as Map;
        expect(result['outcome'], 'success');
        expect(result['output'], contains('766228'));
        expect(find.text('766228'), findsOneWidget);
        expect(find.textContaining('Run 2'), findsOneWidget);
        expect(find.byType(PythonReplView), findsOneWidget);
        canvas.publish('repair');
        await settleFor(tester, const Duration(milliseconds: 100));
        expect(canvas.scheduled, hasLength(1));
        expect(canvas.actions, hasLength(2));
        expect(tester.takeException(), isNull);
      },
      skip: skipWithoutMonty != false,
    );
  }

  testWidgets('Run clicked during preference loading waits for Type check', (
    tester,
  ) async {
    SharedPreferences.resetStatic();
    final preferences = _DelayedPreferences({
      'flutter.soliplex.python.typeCheck.surface_2': true,
    });
    SharedPreferencesStorePlatform.instance = preferences;
    final canvas = _Canvas(tester, 'type_check');
    await canvas.mount(live: false);
    await tester.runAsync(() => tester.tap(canvas.run));
    expect(canvas.starter.starts, 0);
    expect(canvas.actions, isEmpty);
    preferences.ready.complete();
    await pumpUntil(
      tester,
      () => find.textContaining('unsupported-operator').evaluate().isNotEmpty,
    );
    expect(canvas.actions, isEmpty);
    expect(find.text('766228'), findsNothing);
  }, skip: skipWithoutMonty != false);

  testWidgets('declined repair ends when its model turn finishes', (
    tester,
  ) async {
    final canvas = _Canvas(tester, 'name_error');
    await canvas.mount();
    canvas.turn.value = 'earlier-chat';
    await tester.pump();
    await tester.runAsync(() => tester.tap(canvas.checkbox));
    await tester.pump();
    await canvas.clickRun();
    expect(find.textContaining('Asking the model'), findsOneWidget);
    // The repair action queues behind an earlier chat turn. Completing that
    // turn cannot settle the repair request before its own turn has started.
    canvas.turn.value = null;
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Asking the model'), findsOneWidget);
    canvas.turn.value = 'repair';
    await tester.pump();
    canvas.turn.value = null;
    await tester.pump();
    await tester.pump();
    expect(find.text('The model did not repair the program.'), findsOneWidget);
    expect(tester.widget<SoliplexButton>(canvas.run).onPressed, isNotNull);
    expect(canvas.scheduled, isEmpty);
  }, skip: skipWithoutMonty != false);

  testWidgets('type check off is persisted; reload and replay stay inert', (
    tester,
  ) async {
    final canvas = _Canvas(tester, 'type_check');
    await canvas.mount(live: false);
    await canvas.clickRun();
    expect(find.textContaining('unsupported-operator'), findsOneWidget);
    expect(canvas.actions, isEmpty);
    expect(find.text('766228'), findsNothing);
    await tester.runAsync(() => tester.tap(canvas.typeCheck));
    await tester.pump();
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getBool('soliplex.python.typeCheck.surface_2'), false);
    await tester.runAsync(() => tester.tap(canvas.run));
    await pumpUntil(tester, () => canvas.actions.isNotEmpty);
    expect(
      (canvas.actions.single['context']! as Map)['output'],
      contains('766228'),
    );
    canvas.publish('repair', live: false);
    await settleFor(tester);
    expect(tester.widget<Checkbox>(canvas.typeCheck).value, false);
    expect(canvas.scheduled, isEmpty);
    expect(canvas.actions, hasLength(1));
  }, skip: skipWithoutMonty != false);
}
