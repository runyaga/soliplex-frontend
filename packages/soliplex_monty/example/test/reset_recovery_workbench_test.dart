import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/layout_tree.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/surface_mount_registry.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/workbench_host.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

import '../../../../test/fixtures/workbench/workbench_fixtures.g.dart';
import '../../test/python_repl_test.dart' as repl;
import '../../test/support/monty.dart';

const _source = '''
import ui
def handle_event(name, context):
    if name == "reset":
        raise TimeoutError("reset")
    print("handled")
ui.show(ui.Text("App controls"), data={"value": "kept"})
''';

void main() {
  testWidgets('the workbench app window survives reset and a failed rerun', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(2200, 1600);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    final starter = MontyStarter();
    final apps = ProgramApps();
    final layout =
        jsonDecode(workbenchFixtures['layout_tree_v1.json']!)
            as Map<String, dynamic>;
    layout['shared'] = {
      'programApps': {'app': 'program'},
    };
    final nodes = (layout['nodes'] as List).cast<Map<String, dynamic>>();
    nodes.singleWhere((n) => n['id'] == 'r_canvas')['children'] = [
      'source',
      'app',
    ];
    Map<String, dynamic> node(
      String id,
      String parent,
      String kind,
      List<String> children, {
      Map<String, String> payload = const {},
    }) => {
      'id': id,
      'parentId': parent,
      'children': children,
      'kind': kind,
      'title': id == 'app' ? 'Platform probe app' : id,
      'size': 'medium',
      'visibility': 'open',
      'payload': payload,
    };
    nodes.addAll([
      node('source', 'r_canvas', 'window', ['leaf']),
      node(
        'leaf',
        'source',
        'surface',
        [],
        payload: {
          'activityMessageId': 'activity',
          'surfaceId': 'program',
        },
      ),
      node('app', 'r_canvas', 'window', []),
    ]);
    final tree = LayoutTree.fromLayout(layout, [
      WorkbenchRegistration(
        role: WorkbenchRole.program,
        activityMessageId: 'activity',
        surfaceId: 'program',
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(
          body: ProgramAppScope(
            apps: apps,
            child: WorkbenchHost(
              tree: tree,
              chat: const Text('Chat'),
              mounts: SurfaceMountRegistry(),
              surfaceBuilder: (_, _) => PythonReplView(
                source: _source,
                surfaceId: 'program',
                mode: ReplMode.run,
                limits: const ReplLimits(),
                startRuntime: starter.call,
                onWorkbench: () async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final controls = apps.controls('program')!;
    Future<void> perform(Future<void> Function() action) async {
      await tester.runAsync(action);
      await tester.pumpAndSettle();
    }

    void expectWindow() {
      expect(
        find.bySemanticsLabel('Workbench window Platform probe app'),
        findsOneWidget,
      );
      expect(find.text('App controls'), findsOneWidget);
      expect(apps.snapshot()['program'], {'value': 'kept'});
    }

    await perform(controls.run);
    expectWindow();
    final view = apps.view('program');
    await perform(() => controls.event('reset'));
    expectWindow();
    expect(apps.view('program'), same(view));
    await perform(() => controls.event('ok'));
    expectWindow();
    expect(find.textContaining('handled'), findsOneWidget);
    await repl.typeSource(tester, '1 / 0');
    final recoveredView = apps.view('program');
    await perform(controls.run);
    expectWindow();
    expect(apps.view('program'), same(recoveredView));
    expect(find.textContaining('ZeroDivisionError'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
    apps.dispose();
    await tester.runAsync(starter.close);
  }, skip: skipWithoutMonty != false);
}
