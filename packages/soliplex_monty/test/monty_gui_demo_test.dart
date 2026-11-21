// Reads the curated demo source from the repository with dart:io.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'python_repl_test.dart' as repl;
import 'support/lab_surface.dart';
import 'support/monty.dart';

Directory get _root {
  var directory = Directory.current.absolute;
  while (!Directory('${directory.path}/workbench/backend').existsSync()) {
    final parent = directory.parent;
    if (parent.path == directory.path) throw StateError('Missing demo source');
    directory = parent;
  }
  return directory;
}

String get _source => File(
  '${_root.path}/workbench/backend/soliplex_a2ui_workbench/'
  'src/soliplex_a2ui_workbench/monty_gui_demo.py',
).readAsStringSync();

// The backend test compares this fixture with the actual open_demo ToolReturn.
// Read the source directly so there is only one copy of the curated program.
List<Map<String, Object?>> _publication() {
  final fixture = File(
    '${_root.path}/packages/soliplex_monty/test/fixtures/monty_demo.json',
  ).readAsStringSync();
  final operations = (jsonDecode(fixture) as List)
      .map((op) => Map<String, Object?>.from(op as Map))
      .toList();
  for (final op in operations) {
    final update = op['updateDataModel'];
    if (update is Map) (update['value'] as Map)['source'] = _source;
  }
  return operations;
}

Future<void> _mount(
  WidgetTester tester,
  LabSurfaceController controller,
) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final apps = ProgramApps();
  addTearDown(apps.dispose);
  controller.apply(_publication());
  await tester.pumpWidget(
    MaterialApp(
      theme: soliplexLightTheme(),
      home: Scaffold(
        body: ProgramAppScope(
          apps: apps,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: LabSurfaceView(controller: controller),
                ),
              ),
              Expanded(
                child: ProgramAppView(
                  program: controller.surfaces.single.id,
                  apps: apps,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('published demo shows its source and Run without execution', (
    tester,
  ) async {
    var starts = 0;
    final actions = <Map<String, Object?>>[];
    final controller = LabSurfaceController(
      startRuntime: (_, _) {
        starts++;
        throw StateError('Publication must stay inert');
      },
      onActionPayload: actions.add,
    );
    addTearDown(controller.dispose);
    await _mount(tester, controller);
    expect(controller.error, isNull);
    expect(controller.surfaces.single.dataModel.get('/source'), _source);
    expect(tester.widget<TextField>(repl.editor).controller!.text, _source);
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('Count: 3'), findsNothing);
    expect(starts, 0);
    expect(actions, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'real curated source and every event drive counter, chart and windows',
    (tester) async {
      final starter = MontyStarter();
      final actions = <Map<String, Object?>>[];
      final controller = LabSurfaceController(
        startRuntime: starter.call,
        onActionPayload: actions.add,
      );
      final semantics = tester.ensureSemantics();
      await _mount(tester, controller);
      expect(starter.starts, 0);
      await repl.tapRun(tester);
      await repl.waitFor(tester, () => actions.isNotEmpty && repl.idle(tester));
      expect(
        actions.single['name'],
        'workbench.program.layout',
        reason: '${controller.surfaces.single.dataModel.get('/output')}',
      );
      expect(find.text('Python drives the GUI'), findsOneWidget);
      expect(find.text('Count: 3'), findsOneWidget);
      expect(find.text('last event: run, count 3'), findsOneWidget);
      for (final label in [
        '+1',
        '-1',
        'Reset',
        'Add point',
        'Open log window',
        'Close log window',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        find.bySemanticsLabel(RegExp('Bar Start: 3')),
        findsOneWidget,
      );

      List<Map<String, Object?>> batch(int index) =>
          (((actions[index]['context']! as Map)['actions']) as List)
              .map((value) => Map<String, Object?>.from(value as Map))
              .toList();
      expect(batch(0).map((a) => a['op']), ['show_app']);

      Future<void> click(String label, String event, int count) async {
        await tester.runAsync(() => tester.tap(find.text(label)));
        await tester.pump();
        await repl.waitFor(
          tester,
          () =>
              repl.idle(tester) &&
              find
                  .text('last event: $event, count $count')
                  .evaluate()
                  .isNotEmpty,
        );
        expect(find.text('Count: $count'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      await click('+1', 'plus', 4);
      await click('Add point', 'add_point', 4);
      expect(find.bySemanticsLabel(RegExp('Bar Sample 1: 4')), findsOneWidget);
      await click('-1', 'minus', 3);
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('chart-bar:Sample 1'))),
      );
      await tester.pump();
      await repl.waitFor(
        tester,
        () => repl.idle(tester) && find.text('Count: 4').evaluate().isNotEmpty,
      );
      expect(find.text('Restored stock from Sample 1: 4.'), findsOneWidget);
      await click('Reset', 'reset', 3);
      expect(find.byKey(const ValueKey('chart-bar:Sample 1')), findsNothing);
      for (var n = 2; n >= 0; n--) {
        await click('-1', 'minus', n);
      }
      await click('-1', 'minus', 0);
      expect(
        find.text('Stock is empty; add an item with +1 before removing one.'),
        findsOneWidget,
      );
      await click('Open log window', 'open_log', 0);
      expect(batch(1).map((a) => a['op']), ['open', 'move']);
      final firstWindow = batch(1).first['window_id'];
      final log = batch(1).first['content']! as String;
      expect(log, contains('snapshot; reopen to refresh'));
      expect(log.split('\n').skip(1), hasLength(8));
      expect(log, contains('last event: open_log, count 0'));
      await click('Close log window', 'close_log', 0);
      expect(batch(2).single['op'], 'close');
      expect(batch(2).single['window_id'], firstWindow);
      await click('Close log window', 'close_log', 0);
      expect(actions, hasLength(3));
      await repl.tapRun(tester);
      await repl.waitFor(
        tester,
        () => actions.length == 4 && repl.idle(tester),
      );
      expect(batch(3).map((a) => a['op']), ['show_app']);
      expect(find.text('Count: 3'), findsOneWidget);
      expect(starter.starts, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(starter.close);
      semantics.dispose();
    },
    skip: skipWithoutMonty != false,
  );

  testWidgets('a long interactive session outlasts the host-call budget', (
    tester,
  ) async {
    final starter = MontyStarter();
    final controller = LabSurfaceController(
      startRuntime: starter.call,
      onActionPayload: (_) {},
    );
    final semantics = tester.ensureSemantics();
    await _mount(tester, controller);
    await repl.tapRun(tester);
    await repl.waitFor(
      tester,
      () => repl.idle(tester) && find.text('Count: 3').evaluate().isNotEmpty,
    );
    // Each redraw makes about twenty ui calls, so sixty clicks pass the
    // 1000-suspension session default.
    for (var count = 4; count <= 63; count++) {
      await tester.runAsync(() => tester.tap(find.text('+1')));
      await tester.pump();
      await repl.waitFor(
        tester,
        () =>
            repl.idle(tester) &&
            (find.text('Count: $count').evaluate().isNotEmpty ||
                find.textContaining('suspension limit').evaluate().isNotEmpty),
      );
      expect(
        find.textContaining('suspension limit'),
        findsNothing,
        reason: 'click $count',
      );
    }
    expect(find.text('Count: 63'), findsOneWidget);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
