import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

import 'python_repl_test.dart' as repl;
import 'support/lab_surface.dart';
import 'support/monty.dart';

const _source = '''
import ui
assert CLIENT["width"] > 0
window = ""
def draw():
    ui.show(ui.Column([
        ui.Button(ui.Text("Open result"), action=ui.Event("open", {})),
        ui.Button(ui.Text("Close result"), action=ui.Event("close", {})),
    ]))
def handle_event(name, context):
    global window
    assert CLIENT["height"] > 0
    if name == "open":
        window = ui.workbench.open_window("Result", "text", "10")
    if name == "close":
        ui.workbench.close_window(window)
draw()
''';

void main() {
  for (final count in [7, 8]) {
    testWidgets(
      'automatic app opening counts with $count Python layout actions',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final starter = MontyStarter();
        final apps = ProgramApps();
        var result = <String, Object?>{};
        var publishes = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: soliplexLightTheme(),
            home: Scaffold(
              body: ProgramAppScope(
                apps: apps,
                child: SingleChildScrollView(
                  child: PythonReplView(
                    source:
                        'import ui\nui.show(ui.Text("App"))\n'
                        'for i in range($count):\n'
                        '    ui.workbench.open_window("Result", "text", "10")',
                    surfaceId: 'program',
                    limits: const ReplLimits(),
                    startRuntime: starter.call,
                    writeResult: (value) => result = value,
                    onWorkbench: () async {
                      publishes++;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await repl.tapRun(tester);
        await repl.waitFor(
          tester,
          () => repl.idle(tester) && result.isNotEmpty,
        );
        expect(publishes, count == 7 ? 1 : 0);
        if (count == 7) {
          expect(result['actions'], hasLength(8));
          expect((result['actions']! as List).first, {'op': 'show_app'});
          expect(apps.view('program'), isNotNull);
        } else {
          expect(result['ok'], false);
          expect(apps.view('program'), isNull);
          expect(find.textContaining('including app window'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        apps.dispose();
        await tester.runAsync(starter.close);
      },
      skip: skipWithoutMonty != false,
    );
  }

  testWidgets(
    'Run and a user-started handle_event stage open and close requests',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final starter = MontyStarter();
      var result = <String, Object?>{};
      final batches = <List<Object?>>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: PythonReplView(
                source: _source,
                limits: const ReplLimits(),
                startRuntime: starter.call,
                writeResult: (value) => result = value,
                onWorkbench: () async {
                  batches.add(List<Object?>.from(result['actions']! as List));
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(starter.starts, 0);
      expect(batches, isEmpty);
      await repl.tapRun(tester);
      await repl.waitFor(
        tester,
        () =>
            repl.idle(tester) &&
            find.textContaining('Run 1 ·').evaluate().isNotEmpty,
      );
      expect(batches, isEmpty);
      await tester.runAsync(() => tester.tap(find.text('Open result')));
      await repl.waitFor(tester, () => batches.length == 1);
      expect((batches[0].single! as Map)['op'], 'open');
      await tester.runAsync(() => tester.tap(find.text('Close result')));
      await repl.waitFor(tester, () => batches.length == 2);
      expect((batches[1].single! as Map)['op'], 'close');
      expect(
        (batches[1].single! as Map)['window_id'],
        (batches[0].single! as Map)['window_id'],
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(starter.close);
    },
    skip: skipWithoutMonty != false,
  );

  testWidgets(
    'reload is passive and an over-limit Run publishes no layout actions',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final starter = MontyStarter();
      var calls = 0;
      Widget app(String source, Key key) => MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PythonReplView(
              key: key,
              source: source,
              limits: const ReplLimits(),
              startRuntime: starter.call,
              onWorkbench: () async {
                calls++;
              },
            ),
          ),
        ),
      );
      const source =
          'import ui\nfor i in range(9):\n'
          '    ui.workbench.open_window("Result", "text", "10")';
      await tester.pumpWidget(app(source, const ValueKey('first')));
      await tester.pumpAndSettle();
      expect(starter.starts, 0);
      await repl.tapRun(tester);
      await repl.waitFor(
        tester,
        () =>
            repl.idle(tester) &&
            find.textContaining('Run 1 ·').evaluate().isNotEmpty,
      );
      expect(calls, 0);
      expect(find.textContaining('layout action limit'), findsWidgets);
      await tester.pumpWidget(app(source, const ValueKey('reload')));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(starter.starts, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(starter.close);
    },
    skip: skipWithoutMonty != false,
  );
  testWidgets(
    'catalog dispatches layout requests only after Run',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final starter = MontyStarter();
      final actions = <Map<String, Object?>>[];
      final controller =
          LabSurfaceController(
            startRuntime: starter.call,
            onActionPayload: actions.add,
          )..apply(
            repl.withRepl({
              'source':
                  'import ui\nui.workbench.open_window("Result", "text", "10")',
              'outputPath': '/output',
              'onWorkbench': {
                'event': {
                  'name': 'workbench.program.layout',
                  'context': {
                    'invocationId': {'@path': '/output/invocationId'},
                    'actions': {'@path': '/output/actions'},
                  },
                },
              },
            }),
          );
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
      await tester.pumpAndSettle();
      expect(starter.starts, 0);
      expect(actions, isEmpty);
      await repl.tapRun(tester);
      await repl.waitFor(tester, () => actions.isNotEmpty);
      expect(actions.single['name'], 'workbench.program.layout');
      final context = actions.single['context']! as Map;
      expect(context['invocationId'], startsWith('gesture-'));
      expect(((context['actions'] as List).single as Map)['op'], 'open');
      expect(controller.surfaces, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.runAsync(starter.close);
    },
    skip: skipWithoutMonty != false,
  );
}
