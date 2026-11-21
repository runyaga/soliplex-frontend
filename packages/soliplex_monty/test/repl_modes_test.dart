import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

import 'support/lab_surface.dart';
import 'support/monty.dart';

List<Map<String, Object?>> surface(
  String source, {
  Map<String, Object?> props = const {},
}) => [
  {
    'version': '1.0',
    'createSurface': {'surfaceId': 's', 'catalogId': labCatalogId},
  },
  {
    'version': '1.0',
    'updateDataModel': {
      'surfaceId': 's',
      'path': '/',
      'value': {
        'repl': {'source': source},
      },
    },
  },
  {
    'version': '1.0',
    'updateComponents': {
      'surfaceId': 's',
      'components': [
        {
          'id': 'root',
          'component': 'PythonRepl',
          'source': {'@path': '/repl/source'},
          ...props,
        },
      ],
    },
  },
];

const counter = '''
try:
    n += 1
except NameError:
    n = 1
print("count", n)
''';

final Finder runButton = find.byKey(const ValueKey('python-repl-run'));
final Finder editor = find.byKey(const ValueKey('python-repl-editor'));
final Finder showCode = find.byKey(const ValueKey('python-repl-show-code'));

void main() {
  late MontyStarter starter;
  late LabSurfaceController controller;

  Future<void> mount(WidgetTester tester, List<Map<String, Object?>> s) async {
    tester.view
      ..physicalSize = const Size(1200, 3000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    starter = MontyStarter();
    controller = LabSurfaceController(startRuntime: starter.call)..apply(s);
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
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.runAsync(starter.close);
  }

  bool idle(WidgetTester tester) =>
      tester.widget<SoliplexButton>(runButton).onPressed != null;

  Future<void> run(WidgetTester tester) async {
    await tester.runAsync(() => tester.tap(runButton));
    await tester.pump();
    await pumpUntil(tester, () => idle(tester));
  }

  testWidgets('the transcript hides the code until Show code', (tester) async {
    await mount(tester, surface('print("hello")'));
    await run(tester);
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('Run 1 · ok'), findsOneWidget);
    expect(find.text('>>> print("hello")'), findsNothing);

    await tester.tap(showCode);
    await tester.pump();
    expect(find.text('>>> print("hello")'), findsOneWidget);
    await finish(tester);
  }, skip: skipWithoutMonty != false);

  testWidgets('showSource shows the code that ran', (tester) async {
    await mount(tester, surface('print("hello")', props: {'showSource': true}));
    await run(tester);
    expect(find.text('>>> print("hello")'), findsOneWidget);
    expect(showCode, findsNothing);
    await finish(tester);
  }, skip: skipWithoutMonty != false);

  testWidgets('repl mode keeps globals and expands earlier runs on request', (
    tester,
  ) async {
    await mount(tester, surface(counter));
    expect(editor, findsOneWidget);
    await run(tester);
    await run(tester);
    expect(find.text('count 1'), findsNothing);
    expect(find.text('count 2'), findsOneWidget);
    expect(find.text('Latest run'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('python-repl-history')));
    await tester.pumpAndSettle();
    expect(find.text('count 1'), findsOneWidget);
    expect(find.text('count 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('python-repl-history')));
    await tester.pumpAndSettle();
    expect(find.text('count 1'), findsNothing);
    await finish(tester);
  }, skip: skipWithoutMonty != false);

  testWidgets('repl collapses successful code and allows editing again', (
    tester,
  ) async {
    await mount(tester, surface('print("hello")'));
    expect(editor, findsOneWidget);
    await run(tester);
    expect(editor, findsNothing);
    await tester.tap(find.text('Edit code'));
    await tester.pump();
    expect(editor, findsOneWidget);
    await run(tester);
    expect(editor, findsOneWidget);
    await tester.enterText(editor, 'raise ValueError("broken")');
    await run(tester);
    expect(editor, findsOneWidget);
    expect(find.text('Hide code'), findsOneWidget);
    await tester.tap(find.text('Hide code'));
    await tester.pump();
    expect(editor, findsNothing);
    await finish(tester);
  }, skip: skipWithoutMonty != false);

  testWidgets('run mode hides the editor until Edit code', (tester) async {
    await mount(tester, surface(counter, props: {'mode': 'run'}));
    expect(editor, findsNothing);
    await tester.tap(find.byKey(const ValueKey('python-repl-edit')));
    await tester.pump();
    expect(editor, findsOneWidget);
    await finish(tester);
  }, skip: skipWithoutMonty != false);

  testWidgets(
    'run mode starts each run fresh and shows only the latest result',
    (tester) async {
      await mount(tester, surface(counter, props: {'mode': 'run'}));
      await run(tester);
      expect(find.text('count 1'), findsOneWidget);
      await run(tester);
      expect(find.text('count 1'), findsOneWidget);
      expect(find.text('Run 2 · ok'), findsOneWidget);
      expect(find.text('Run 1 · ok'), findsNothing);
      expect(starter.starts, 1);
      await finish(tester);
    },
    skip: skipWithoutMonty != false,
  );
}
