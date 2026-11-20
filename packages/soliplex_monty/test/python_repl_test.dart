import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

import 'support/lab_surface.dart';
import 'support/monty.dart';

List<Map<String, Object?>> withRepl(Map<String, Object?> props) => [
  {
    'version': '1.0',
    'createSurface': {'surfaceId': 'bad', 'catalogId': labCatalogId},
  },
  {
    'version': '1.0',
    'updateComponents': {
      'surfaceId': 'bad',
      'components': [
        {'id': 'root', 'component': 'PythonRepl', ...props},
      ],
    },
  },
];

final Finder runButton = find.byKey(const ValueKey('python-repl-run'));
final Finder editor = find.byKey(const ValueKey('python-repl-editor'));

Future<void> waitFor(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) {
      final texts = [
        for (final e in find.byType(SelectableText).evaluate())
          (e.widget as SelectableText).data,
        for (final e in find.byType(Text).evaluate()) (e.widget as Text).data,
      ].whereType<String>().where((t) => t.length > 2).take(25).join(' | ');
      fail('Timed out waiting for the REPL: $texts ${tester.takeException()}');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pump();
}

/// Taps in the real zone so Monty futures and the deadline timer run.
Future<void> tapRun(WidgetTester tester) =>
    tester.runAsync(() => tester.tap(runButton));

bool idle(WidgetTester tester) =>
    tester.widget<SoliplexButton>(runButton).onPressed != null;

Future<void> typeSource(WidgetTester tester, String text) async {
  await tester.enterText(editor, text);
  await tester.pump();
}

void main() {
  late MontyStarter starter;
  late List<Map<String, Object?>> actions;
  late LabSurfaceController controller;

  LabSurfaceController create({ReplLimits limits = const ReplLimits()}) {
    starter = MontyStarter();
    actions = [];
    return controller = LabSurfaceController(
      startRuntime: starter.call,
      limits: limits,
      onActionPayload: actions.add,
    );
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1200, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller.apply(pythonReplSurfaceMessages());
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
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.runAsync(starter.close);
  }

  Object? model(String path) => controller.surfaces.single.dataModel.get(path);

  group('schema', () {
    test('accepts the gallery sample', () {
      final controller = create();
      addTearDown(controller.dispose);
      controller.apply(pythonReplSurfaceMessages());
      expect(controller.error, isNull);
      expect(controller.surfaces.single.id, 'repl');
      expect(model('/repl/source'), 'x = sum(range(10))\nprint(x)\nx * 2');
    });

    for (final (name, props) in [
      ('missing source', <String, Object?>{}),
      ('numeric source', <String, Object?>{'source': 5}),
      ('numeric outputPath', <String, Object?>{'source': '1', 'outputPath': 3}),
      (
        'relative outputPath',
        <String, Object?>{'source': '1', 'outputPath': 'result'},
      ),
      (
        'action that is not an action',
        <String, Object?>{'source': '1', 'onRun': 'run'},
      ),
    ]) {
      test('rejects $name', () {
        final controller = create();
        addTearDown(controller.dispose);
        Object? thrown;
        try {
          controller.apply(withRepl(props));
        } on Object catch (error) {
          thrown = error;
        }
        expect(thrown ?? controller.error, isNotNull);
        final components = controller.surfaces
            .expand((s) => s.componentsModel.all)
            .where((c) => c.type == 'PythonRepl');
        expect(components, isEmpty);
      });
    }
  });

  testWidgets('a payload sets source but never runs it', (tester) async {
    create();
    await mount(tester);
    controller.apply([
      {
        'version': '1.0',
        'updateDataModel': {
          'surfaceId': 'repl',
          'path': '/repl/source',
          'value': 'print("from the agent")',
        },
      },
    ]);
    await tester.pump();
    expect(find.text('print("from the agent")'), findsOneWidget);
    expect(find.text('Press Run to execute the code.'), findsOneWidget);
    expect(starter.starts, 0);
    expect(model('/repl/result'), isNull);
    expect(actions, isEmpty);
    await unmount(tester);
  });

  testWidgets('editing writes back through the binding', (tester) async {
    create();
    await mount(tester);
    await typeSource(tester, 'y = 3');
    expect(model('/repl/source'), 'y = 3');
    expect(starter.starts, 0);
    await unmount(tester);
  });

  testWidgets('source semantics stay separate from surrounding text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    create();
    await mount(tester);

    void expectLabels() {
      final field = tester.getSemantics(editor);
      expect(field.label, 'Python source');
      expect(field.getSemanticsData().flagsCollection.isTextField, isTrue);
      for (final label in [
        'Try Python locally',
        'Python (Monty sandbox)',
        '0 runs shown',
        'Press Run to execute the code.',
      ]) {
        expect(tester.getSemantics(find.text(label)).label, label);
      }
    }

    expectLabels();
    await typeSource(tester, 'print("edited")');
    expectLabels();
    expect(tester.getSemantics(editor).value, 'print("edited")');
    semantics.dispose();
    await unmount(tester);
  });

  testWidgets('run results have semantics separate from the source field', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    create();
    await mount(tester);
    await tapRun(tester);
    await waitFor(
      tester,
      () => idle(tester) && model('/repl/result') != null,
    );

    expect(tester.getSemantics(editor).label, 'Python source');
    final nodes = [
      for (final label in [
        'Python (Monty sandbox)',
        '1 run shown',
        'Run 1 · ok',
      ])
        tester.getSemantics(find.text(label)),
      tester.getSemantics(find.text('45\n90')),
    ];
    expect(nodes.take(3).map((node) => node.label), [
      'Python (Monty sandbox)',
      '1 run shown',
      'Run 1 · ok',
    ]);
    expect(nodes.last.value, '45\n90');
    expect(nodes.last.label, isEmpty);
    expect(nodes.map((node) => node.id).toSet(), hasLength(nodes.length));
    semantics.dispose();
    await unmount(tester);
  }, skip: skipWithoutMonty != false);

  testWidgets(
    'Run shows printed output and the value, keeps state, and reports',
    (tester) async {
      create();
      await mount(tester);
      await tapRun(tester);
      await waitFor(
        tester,
        () => idle(tester) && model('/repl/result') != null,
      );
      expect(find.text('45\n90'), findsOneWidget);
      expect(model('/repl/result'), {
        'run': 1,
        'source': 'x = sum(range(10))\nprint(x)\nx * 2',
        'output': '45\n90',
        'ok': true,
      });
      await waitFor(tester, () => actions.isNotEmpty);
      final event = actions.single;
      expect(event['name'], 'python_ran');
      expect(
        (event['context']! as Map)['result'],
        containsPair('output', '45\n90'),
      );

      await typeSource(tester, 'x + 1');
      await tapRun(tester);
      await waitFor(tester, () => idle(tester) && actions.length == 2);
      expect(find.text('46'), findsOneWidget);
      expect(starter.starts, 1);
      await unmount(tester);
    },
    skip: skipWithoutMonty != false,
  );

  testWidgets('an example loads into the editor without running', (
    tester,
  ) async {
    create();
    await mount(tester);
    await tester.tap(
      find.byKey(const ValueKey('python-repl-example:Sales report')),
    );
    await tester.pump();
    expect(model('/repl/source'), startsWith('sales = ['));
    expect(starter.starts, 0);
    expect(model('/repl/result'), isNull);
    await unmount(tester);
  });

  testWidgets('every shipped example runs successfully in Monty', (
    tester,
  ) async {
    create();
    await mount(tester);
    var run = 0;
    final outputs = <String, String>{};
    for (final example in replExamples) {
      await tester.tap(
        find.byKey(ValueKey('python-repl-example:${example['label']}')),
      );
      await tester.pump();
      await tapRun(tester);
      run++;
      await waitFor(
        tester,
        () => idle(tester) && (model('/repl/result') as Map?)?['run'] == run,
      );
      final result = model('/repl/result')! as Map;
      outputs[example['label']!] = result['output']! as String;
      expect(
        result['ok'],
        true,
        reason: '${example['label']}: ${result['output']}',
      );
    }
    expect(outputs['Sales report'], contains('best: North Q3 (1610)'));
    expect(outputs['Matrices'], endsWith('(6, 42)'));
    expect(outputs['Errors'], endsWith('49'));
    await unmount(tester);
  }, skip: skipWithoutMonty != false);

  Future<void> runExample(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(ValueKey('python-repl-example:$label')));
    await tester.pump();
    await tapRun(tester);
    await waitFor(tester, () => idle(tester) && model('/repl/result') != null);
  }

  testWidgets('Python builds a surface and handles clicks on it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    create();
    await mount(tester);
    await runExample(tester, 'Counter');
    expect(find.text('Surface built by Python'), findsOneWidget);
    expect(find.text('Count: 0'), findsOneWidget);
    void expectSurfaceText(int count, String history) {
      expect(tester.getSemantics(editor).label, 'Python source');
      final labels = [
        'Surface built by Python',
        'Count: $count',
        if (count == 0) '(empty)',
        'history: $history',
      ];
      for (final label in labels) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      final nodes = [
        for (final label in labels) tester.getSemantics(find.text(label)),
      ];
      expect(nodes.map((node) => node.label), labels);
      expect(nodes.map((node) => node.id).toSet(), hasLength(nodes.length));
      final button = tester.getSemantics(find.text('+1'));
      expect(button.label, '+1');
      expect(button.getSemanticsData().flagsCollection.isButton, isTrue);
    }

    expectSurfaceText(0, '');
    for (var i = 1; i <= 2; i++) {
      await tester.runAsync(() => tester.tap(find.text('+1')));
      await waitFor(tester, () => find.text('Count: $i').evaluate().isNotEmpty);
      expectSurfaceText(i, List.filled(i, 'inc').join(', '));
    }
    await tester.runAsync(() => tester.tap(find.text('x2')));
    await waitFor(tester, () => find.text('Count: 4').evaluate().isNotEmpty);
    expectSurfaceText(4, 'inc, inc, double');
    expect(starter.starts, 1);
    semantics.dispose();
    await unmount(tester);
  }, skip: skipWithoutMonty != false);

  testWidgets('the catalog surface sends bound values back to Python', (
    tester,
  ) async {
    create();
    await mount(tester);
    await runExample(tester, 'Widget catalog');
    expect((model('/repl/result')! as Map)['ok'], true);
    for (final tab in ['Display', 'Inputs', 'Layout', 'Media']) {
      expect(find.text(tab), findsOneWidget);
    }
    await tester.tap(find.text('Inputs'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('Submit to Python')));
    await waitFor(
      tester,
      () => find.textContaining("received 'Ada'").evaluate().isNotEmpty,
    );
    expect(find.textContaining('size 40 (small)'), findsOneWidget);
    await unmount(tester);
  }, skip: skipWithoutMonty != false);

  testWidgets('an invalid surface is rejected and the old one stays', (
    tester,
  ) async {
    create();
    await mount(tester);
    await runExample(tester, 'Counter');
    await typeSource(tester, 'ui.show(ui.Text("x", "shouting"))');
    await tapRun(tester);
    await waitFor(
      tester,
      () => idle(tester) && (model('/repl/result')! as Map)['run'] == 2,
    );
    final result = model('/repl/result')! as Map;
    expect(result['ok'], false);
    expect(result['output'], contains('Surface rejected'));
    expect(find.text('Count: 0'), findsOneWidget);
    await unmount(tester);
  }, skip: skipWithoutMonty != false);

  testWidgets('a Python error is shown as output', (tester) async {
    create();
    await mount(tester);
    await typeSource(tester, 'print("before")\n1 / 0');
    await tapRun(tester);
    await waitFor(tester, () => idle(tester) && model('/repl/result') != null);
    final result = model('/repl/result')! as Map;
    expect(result['ok'], false);
    expect(result['output'], startsWith('before\n'));
    expect(result['output'], contains('ZeroDivisionError'));
    expect(find.textContaining('ZeroDivisionError'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  }, skip: skipWithoutMonty != false);

  testWidgets('a runaway loop is stopped by the feed limit', (tester) async {
    create();
    await mount(tester);
    await typeSource(tester, 'while True:\n    pass');
    final clock = Stopwatch()..start();
    await tapRun(tester);
    await waitFor(tester, () => idle(tester) && model('/repl/result') != null);
    final result = model('/repl/result')! as Map;
    expect(result['ok'], false);
    expect(result['output'], contains('TimeoutError'));
    expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
    await unmount(tester);
  }, skip: skipWithoutMonty != false);

  testWidgets('the wall-clock deadline cancels a run and resets state', (
    tester,
  ) async {
    create(
      limits: const ReplLimits(
        maxFeedDuration: Duration(seconds: 30),
        deadline: Duration(milliseconds: 500),
      ),
    );
    await mount(tester);
    await typeSource(tester, 'x = 1');
    await tapRun(tester);
    await waitFor(tester, () => idle(tester) && actions.length == 1);

    await typeSource(tester, 'while True:\n    pass');
    final clock = Stopwatch()..start();
    await tapRun(tester);
    await waitFor(tester, () => idle(tester) && actions.length == 2);
    expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
    final result = model('/repl/result')! as Map;
    expect(result['ok'], false);
    expect(
      result['output'],
      'Stopped: exceeded the 500 ms deadline. Interpreter state was reset.',
    );

    await typeSource(tester, 'x');
    await tapRun(tester);
    await waitFor(tester, () => idle(tester) && actions.length == 3);
    expect((model('/repl/result')! as Map)['output'], contains('NameError'));
    await unmount(tester);
  }, skip: skipWithoutMonty != false);

  testWidgets('disposal mid-run cancels the run and applies no result', (
    tester,
  ) async {
    create(
      limits: const ReplLimits(
        maxFeedDuration: Duration(seconds: 30),
        deadline: Duration(seconds: 30),
      ),
    );
    await mount(tester);
    await typeSource(tester, 'while True:\n    pass');
    await tapRun(tester);
    await waitFor(tester, () => starter.runtimes.isNotEmpty);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    expect(idle(tester), isFalse);
    final clock = Stopwatch()..start();
    await tester.pumpWidget(const SizedBox());
    final runtime = starter.runtimes.single;
    bool disposed() {
      try {
        runtime.execute('1').result.ignore();
        return false;
        // A disposed runtime refuses work with StateError.
        // ignore: avoid_catching_errors
      } on StateError {
        return true;
      }
    }

    // Disposal runs in the fake zone, so pump while real time passes.
    await waitFor(tester, disposed, timeout: const Duration(seconds: 5));
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
    expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
    expect(model('/repl/result'), isNull);
    expect(actions, isEmpty);
    controller.dispose();
    var closed = false;
    await tester.runAsync(() async {
      unawaited(starter.close().whenComplete(() => closed = true));
    });
    await waitFor(tester, () => closed);
  }, skip: skipWithoutMonty != false);
}
