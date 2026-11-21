@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/walkthrough_programs.dart';
import '../../test/python_repl_test.dart' as repl;
import '../../test/support/lab_surface.dart';
import '../../test/support/monty.dart';

Directory get root {
  var directory = Directory.current.absolute;
  while (!Directory('${directory.path}/workbench/backend').existsSync()) {
    directory = directory.parent;
  }
  return directory;
}

String get source => File(
  '${root.path}/workbench/backend/soliplex_a2ui_workbench/src/soliplex_a2ui_workbench/monty_gui_demo.py',
).readAsStringSync();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('native curated Run and programmatic events drive the real GUI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final apps = ProgramApps();
    final starter = MontyStarter();
    final actions = <Map<String, Object?>>[];
    final controller = LabSurfaceController(
      startRuntime: starter.call,
      onActionPayload: actions.add,
    );
    final operations =
        (jsonDecode(
                  File(
                    '${root.path}/packages/soliplex_monty/test/fixtures/monty_demo.json',
                  ).readAsStringSync(),
                )
                as List)
            .map((op) => Map<String, Object?>.from(op as Map))
            .toList();
    for (final op in operations) {
      final update = op['updateDataModel'];
      if (update is Map) (update['value'] as Map)['source'] = source;
    }
    controller.apply(operations);
    final programId = controller.surfaces.single.id;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProgramAppScope(
            apps: apps,
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: LabSurfaceView(controller: controller),
                  ),
                ),
                Expanded(
                  child: ProgramAppView(program: programId, apps: apps),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(starter.starts, 0);
    final controls = apps.controls(programId)!;
    Future<void> perform(String name) async {
      await tester.runAsync(() => WalkthroughPrograms.perform(controls, name));
      await tester.pump();
      await repl.waitFor(tester, () => repl.idle(tester));
    }

    await perform('run');
    expect(find.text('Count: 3'), findsOneWidget);
    for (var n = 4; n <= 6; n++) {
      await perform('plus');
      expect(find.text('Count: $n'), findsOneWidget);
    }
    await perform('add_point');
    expect(find.text('last event: add_point, count 6'), findsOneWidget);
    await perform('open_log');
    expect(actions.last['name'], 'workbench.program.layout');
    final batch = ((actions.last['context']! as Map)['actions'] as List)
        .cast<Map<String, Object?>>();
    expect(
      batch.where((a) => a['op'] == 'open').single['content'],
      contains('last event: open_log, count 6'),
    );
    // An editor change revokes the allowlist before the next automatic action.
    await tester.enterText(repl.editor, 'print(123)');
    expect(
      () => WalkthroughPrograms.perform(controls, 'run'),
      throwsStateError,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.runAsync(starter.close);
    apps.dispose();
  });
}
