import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

import 'python_repl_test.dart' as repl;
import 'support/monty.dart';

const source = '''
import ui
DATA = {"text": ui.workbench.read_file("notes.md")}
def draw():
    ui.show(ui.Column([
        ui.TextField("Notes", ui.bind("/text"), variant="longText"),
        ui.Button(ui.Text("Save"), action=ui.Event("save", {})),
    ]), data=DATA)
def handle_event(name, context):
    if name == "save":
        ui.workbench.write_file("notes.md", DATA["text"])
    draw()
draw()
''';

void main() {
  testWidgets(
    'notes load on Run, save edits and expose current bound app state',
    (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final disk = {'notes.md': 'Saved earlier'};
      var reads = 0;
      final apps = ProgramApps()
        ..readFile = (name) async {
          reads++;
          return disk[name] ?? '';
        }
        ..writeFile = (name, text) async {
          disk[name] = text;
        };
      final starter = MontyStarter();
      await tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(),
          home: Scaffold(
            body: ProgramAppScope(
              apps: apps,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: PythonReplView(
                        source: source,
                        surfaceId: 'notes',
                        limits: const ReplLimits(),
                        startRuntime: starter.call,
                        onWorkbench: () async {},
                      ),
                    ),
                  ),
                  Expanded(
                    child: ProgramAppView(program: 'notes', apps: apps),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(reads, 0);
      expect(starter.starts, 0);
      await repl.tapRun(tester);
      await repl.waitFor(
        tester,
        () => repl.idle(tester) && apps.view('notes') != null,
      );
      expect(apps.snapshot()['notes'], {'text': 'Saved earlier'});
      final input = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller?.text == 'Saved earlier',
      );
      await tester.enterText(input, 'Keep this edit');
      await tester.pump();
      expect(apps.snapshot()['notes'], {'text': 'Keep this edit'});
      await tester.runAsync(() => tester.tap(find.text('Save')));
      await repl.waitFor(
        tester,
        () => repl.idle(tester) && disk['notes.md'] == 'Keep this edit',
      );
      await repl.tapRun(tester);
      await repl.waitFor(tester, () => repl.idle(tester) && reads == 2);
      expect(apps.snapshot()['notes'], {'text': 'Keep this edit'});
      await tester.pumpWidget(const SizedBox());
      expect(apps.snapshot(), isEmpty);
      apps.dispose();
      await tester.runAsync(starter.close);
    },
    skip: skipWithoutMonty != false,
  );
}
