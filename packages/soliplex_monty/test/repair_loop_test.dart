import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

import 'support/lab_surface.dart';
import 'support/monty.dart';

const failing = 'raise ValueError("deliberate failure")';
const fixed = 'print(pow(7, 12345, 1000003))';

List<Map<String, Object?>> replSurface(
  String source, {
  Map<String, Object?> retry = const {},
  bool workbench = false,
  String surfaceId = 'program',
}) => [
  {
    'version': '1.0',
    'createSurface': {'surfaceId': surfaceId, 'catalogId': labCatalogId},
  },
  {
    'version': '1.0',
    'updateDataModel': {
      'surfaceId': surfaceId,
      'path': '/',
      'value': {'source': source},
    },
  },
  {
    'version': '1.0',
    'updateComponents': {
      'surfaceId': surfaceId,
      'components': [
        {
          'id': 'root',
          'component': 'PythonRepl',
          'source': {'@path': '/source'},
          'outputPath': '/output',
          'retry': retry,
          if (workbench) ...{
            'onWorkbench': {
              'event': {'name': 'workbench.program.layout'},
            },
            'onRun': {
              'event': {
                'name': 'workbench.program.run_result',
                'context': {
                  'result': {'@path': '/output'},
                },
              },
            },
          },
          'onFailure': {
            'event': {
              'name': workbench ? 'workbench.program.repair' : 'python_failed',
              'context': {
                'result': {'@path': '/output'},
              },
            },
          },
        },
      ],
    },
  },
];

Map<String, Object?> resultOf(Map<String, Object?> action) =>
    ((action['context']! as Map)['result']! as Map).cast<String, Object?>();

void main() {
  late MontyStarter starter;
  late RepairChains chains;
  late LabSurfaceController controller;
  late List<Map<String, Object?>> actions;
  final autoRuns = <VoidCallback>[];
  final run = find.byKey(const ValueKey('python-repl-run'));
  final checkbox = find.byKey(const ValueKey('python-repl-auto-fix'));
  final manual = find.byKey(const ValueKey('python-repl-ai-fix'));

  Iterable<Map<String, Object?>> getRepairs() => actions.where(
    (a) =>
        a['name'] == 'python_failed' || a['name'] == 'workbench.program.repair',
  );

  LabSurfaceController host({bool live = true}) => LabSurfaceController(
    startRuntime: starter.call,
    live: live,
    chains: chains,
    onActionPayload: actions.add,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    starter = MontyStarter();
    chains = RepairChains();
    actions = [];
    autoRuns.clear();
    PythonReplView.debugScheduleAutoRun = autoRuns.add;
    controller = host();
  });

  tearDown(() => PythonReplView.debugScheduleAutoRun = null);

  Future<void> mount(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1200, 1800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: LabSurfaceView(controller: controller),
          ),
        ),
      ),
    );
    await settleFor(tester, const Duration(milliseconds: 100));
  }

  Future<void> click(WidgetTester tester, Finder target) async {
    await tester.runAsync(() => tester.tap(target));
    await tester.pump();
  }

  Future<void> runAndWait(WidgetTester tester) async {
    await click(tester, run);
    await pumpUntil(
      tester,
      () => tester.widget<SoliplexButton>(run).onPressed != null,
    );
    await settleFor(tester, const Duration(milliseconds: 100));
  }

  Future<void> startAutoRuns(WidgetTester tester) async {
    final starts = [...autoRuns];
    autoRuns.clear();
    await tester.runAsync(() async {
      for (final start in starts) {
        start();
      }
    });
    await tester.pump();
  }

  Future<void> replace(
    WidgetTester tester,
    String source, {
    bool remount = false,
    bool live = true,
    bool tagged = false,
  }) async {
    final retry = tagged
        ? {
            'chainId': resultOf(getRepairs().last)['chainId'],
            'attempt': 1,
          }
        : <String, Object?>{};
    if (remount) {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      controller = host(live: live)..apply(replSurface(source, retry: retry));
      await mount(tester);
    } else {
      controller.apply(
        replSurface(source, retry: retry, workbench: true).skip(1).toList(),
      );
      await tester.pump();
      await tester.pump();
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settleFor(tester, const Duration(milliseconds: 100));
    controller.dispose();
    await tester.runAsync(starter.close);
  }

  testWidgets('default off: failure shows error, no request or scheduled run', (
    tester,
  ) async {
    controller.apply(replSurface(failing, workbench: true));
    await mount(tester);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('AI Fix'), findsOneWidget);
    expect(tester.widget<Checkbox>(checkbox).value, false);
    semantics.dispose();
    await runAndWait(tester);
    expect(find.textContaining('deliberate failure'), findsWidgets);
    expect(getRepairs(), isEmpty);
    expect(autoRuns, isEmpty);
    expect(actions, isEmpty);
    expect(find.text('Do you want to try again?'), findsNothing);
    await finish(tester);
  }, skip: skipWithoutMonty != false);

  for (final tagged in [false, true]) {
    testWidgets(
      'on: one repair request and one automatic run, tagged=$tagged',
      (tester) async {
        controller.apply(replSurface(failing, workbench: !tagged));
        await mount(tester);
        await click(tester, checkbox);
        await runAndWait(tester);
        expect(getRepairs(), hasLength(1));
        expect(resultOf(getRepairs().single)['aiFix'], true);
        expect(
          resultOf(getRepairs().single)['instruction'],
          contains('will run now'),
        );
        await replace(tester, fixed, remount: tagged, tagged: tagged);
        expect(tester.widget<Checkbox>(checkbox).value, true);
        expect(autoRuns, hasLength(1));
        await startAutoRuns(tester);
        await pumpUntil(
          tester,
          () => find.text('Fixed after 1 attempt').evaluate().isNotEmpty,
        );
        expect(find.text('766228'), findsOneWidget);
        expect(getRepairs(), hasLength(1));
        expect(autoRuns, isEmpty);
        if (!tagged) {
          final runs = actions
              .where((a) => a['name'] == 'workbench.program.run_result')
              .map(resultOf)
              .toList();
          expect(runs, hasLength(1));
          expect(resultOf(getRepairs().single)['run'], 1);
          expect(runs.single['run'], 2);
          expect(runs.single['outcome'], 'success');
          expect(runs.single['output'], contains('766228'));
        }
        await finish(tester);
      },
      skip: skipWithoutMonty != false,
    );
  }

  testWidgets(
    'remounting the failed live program cannot claim its own repair',
    (tester) async {
      controller.apply(replSurface(failing, workbench: true));
      await mount(tester);
      await click(tester, checkbox);
      await runAndWait(tester);
      await replace(tester, failing, remount: true);
      expect(autoRuns, isEmpty);
      expect(getRepairs(), hasLength(1));
      await replace(tester, fixed);
      expect(autoRuns, hasLength(1));
      await startAutoRuns(tester);
      await pumpUntil(tester, () => find.text('766228').evaluate().isNotEmpty);
      expect(getRepairs(), hasLength(1));
      await finish(tester);
    },
    skip: skipWithoutMonty != false,
  );

  testWidgets(
    'a repaired GUI publishes layout then reports successful run output',
    (tester) async {
      controller.apply(replSurface(failing, workbench: true));
      await mount(tester);
      await click(tester, checkbox);
      await runAndWait(tester);
      await replace(
        tester,
        'import ui\nui.show(ui.Text("Recovered"))\n'
        'ui.workbench.open_window("Result", "text", "artifact saved")\n'
        'print("artifact saved")',
      );
      await startAutoRuns(tester);
      await pumpUntil(
        tester,
        () => actions.any((a) => a['name'] == 'workbench.program.run_result'),
      );
      expect(actions.map((a) => a['name']), [
        'workbench.program.repair',
        'workbench.program.layout',
        'workbench.program.run_result',
      ]);
      expect(resultOf(actions.last)['output'], contains('artifact saved'));
      expect(resultOf(actions.last)['outcome'], 'success');
      await finish(tester);
    },
    skip: skipWithoutMonty != false,
  );

  testWidgets('unchecking pending repair ends chain and blocks arrival', (
    tester,
  ) async {
    controller.apply(replSurface(failing, workbench: true));
    await mount(tester);
    await click(tester, checkbox);
    await runAndWait(tester);
    final id = resultOf(getRepairs().single)['chainId']! as String;
    await click(tester, checkbox);
    expect(chains[id]!.status, RepairStatus.ended);
    await replace(tester, fixed);
    await settleFor(tester);
    expect(autoRuns, isEmpty);
    expect(find.text('766228'), findsNothing);
    expect(tester.widget<Checkbox>(checkbox).value, false);
    expect(getRepairs(), hasLength(1));
    await finish(tester);
  }, skip: skipWithoutMonty != false);

  testWidgets('unchecking after arrival blocks an already scheduled run', (
    tester,
  ) async {
    controller.apply(replSurface(failing, workbench: true));
    await mount(tester);
    await click(tester, checkbox);
    await runAndWait(tester);
    await replace(tester, fixed);
    expect(autoRuns, hasLength(1));
    await click(tester, checkbox);
    await startAutoRuns(tester);
    await settleFor(tester);
    expect(find.text('766228'), findsNothing);
    await finish(tester);
  }, skip: skipWithoutMonty != false);

  testWidgets(
    'reload preserves on but fresh chains and replay execute nothing',
    (tester) async {
      controller.apply(replSurface(failing));
      await mount(tester);
      await click(tester, checkbox);
      await runAndWait(tester);
      final starts = starter.starts;
      chains = RepairChains();
      await replace(tester, fixed, remount: true, live: false, tagged: true);
      expect(tester.widget<Checkbox>(checkbox).value, true);
      await settleFor(tester);
      expect(starter.starts, starts);
      expect(autoRuns, isEmpty);
      expect(getRepairs(), hasLength(1));
      await finish(tester);
    },
    skip: skipWithoutMonty != false,
  );

  testWidgets(
    'live replacement with no in-memory chain also executes nothing',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'soliplex.python.aiFix.program': true,
      });
      controller.apply(
        replSurface(fixed, retry: {'chainId': 'missing', 'attempt': 1}),
      );
      await mount(tester);
      expect(tester.widget<Checkbox>(checkbox).value, true);
      expect(autoRuns, isEmpty);
      expect(starter.starts, 0);
      await finish(tester);
    },
    skip: skipWithoutMonty != false,
  );

  testWidgets(
    'off: manual AI Fix requests once and replacement waits for Run',
    (tester) async {
      controller.apply(replSurface(failing));
      await mount(tester);
      await runAndWait(tester);
      await click(tester, manual);
      expect(getRepairs(), hasLength(1));
      expect(resultOf(getRepairs().single)['aiFix'], false);
      expect(resultOf(getRepairs().single)['autoRun'], false);
      expect(
        resultOf(getRepairs().single)['instruction'],
        contains('press Run'),
      );
      expect(tester.widget<SoliplexButton>(manual).onPressed, isNull);
      await replace(tester, fixed, remount: true, tagged: true);
      expect(autoRuns, isEmpty);
      expect(tester.widget<Checkbox>(checkbox).value, false);
      await runAndWait(tester);
      expect(find.text('766228'), findsOneWidget);
      expect(getRepairs(), hasLength(1));
      await finish(tester);
    },
    skip: skipWithoutMonty != false,
  );

  testWidgets('enabling during a manual off request never authorizes its run', (
    tester,
  ) async {
    controller.apply(replSurface(failing));
    await mount(tester);
    await runAndWait(tester);
    await click(tester, manual);
    await click(tester, checkbox);
    await replace(tester, fixed, remount: true, tagged: true);
    expect(tester.widget<Checkbox>(checkbox).value, true);
    expect(autoRuns, isEmpty);
    expect(find.text('766228'), findsNothing);
    expect(getRepairs(), hasLength(1));
    await finish(tester);
  }, skip: skipWithoutMonty != false);

  testWidgets(
    'retry budget stops automatic requests; manual AI Fix stays usable',
    (tester) async {
      controller.apply(
        replSurface(failing, retry: {'max': 1}, workbench: true),
      );
      await mount(tester);
      await click(tester, checkbox);
      await runAndWait(tester);
      await replace(tester, 'raise ValueError("still fails")');
      await startAutoRuns(tester);
      await pumpUntil(
        tester,
        () => tester.widget<SoliplexButton>(run).onPressed != null,
      );
      expect(getRepairs(), hasLength(1));
      expect(tester.widget<SoliplexButton>(manual).onPressed, isNotNull);
      expect(find.text('Do you want to try again?'), findsNothing);
      await click(tester, manual);
      expect(getRepairs(), hasLength(2));
      expect(resultOf(getRepairs().last)['attempt'], 2);
      await finish(tester);
    },
    skip: skipWithoutMonty != false,
  );

  testWidgets('preferences belong to the program surface', (tester) async {
    SharedPreferences.setMockInitialValues({
      'soliplex.python.aiFix.other': true,
    });
    controller.apply(replSurface(fixed));
    await mount(tester);
    expect(tester.widget<Checkbox>(checkbox).value, false);
    expect(starter.starts, 0);
    await finish(tester);
  }, skip: skipWithoutMonty != false);
}
