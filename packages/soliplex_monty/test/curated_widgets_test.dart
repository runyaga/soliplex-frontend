@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

import 'python_repl_test.dart' as repl;
import 'support/monty.dart';
import 'support/showcase_checks.dart';

void main() {
  testWidgets(
    'notes status follows multiline edits and saves',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final disk = <String, String>{};
      final apps = ProgramApps()
        ..readFile = ((name) async => disk[name] ?? '')
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
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: PythonReplView(
                        source: demoSource('notes'),
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
      await repl.tapRun(tester);
      await repl.waitFor(
        tester,
        () => repl.idle(tester) && apps.view('notes') != null,
      );
      expect(find.text('Unsaved changes: false'), findsOneWidget);
      final input = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Notes',
      );
      await tester.enterText(input, 'Keep [these] notes\nsecond line');
      await tester.pump();
      expect(find.text('Unsaved changes: true'), findsOneWidget);
      await tester.runAsync(() => tester.tap(find.text('Save')));
      await repl.waitFor(tester, () => repl.idle(tester) && disk.isNotEmpty);
      expect(find.text('Unsaved changes: false'), findsOneWidget);
      await tester.enterText(input, 'Keep [these] notes\nsecond line\n');
      await tester.pump();
      expect(find.text('Unsaved changes: true'), findsOneWidget);
      await repl.tapRun(tester);
      await tester.pump();
      await repl.waitFor(
        tester,
        () =>
            repl.idle(tester) &&
            (apps.snapshot()['notes']! as Map)['text'] ==
                'Keep [these] notes\nsecond line',
      );
      expect(
        apps.snapshot()['notes'],
        containsPair('text', 'Keep [these] notes\nsecond line'),
      );
      expect(find.text('Unsaved changes: false'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      apps.dispose();
      await tester.runAsync(starter.close);
    },
    skip: skipWithoutMonty != false,
  );
}
