import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_scope.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_view.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/chart_placeholder_catalog.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/layout_tree.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/surface_mount_registry.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/workbench_host.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

import '../../../../test/fixtures/workbench_activity_events.dart';
import '../tool/generate_workbench_teaching.dart' as teaching;

void main() {
  test('catalog teaching matches the registered implementations', () {
    final file = File(
      '../../../workbench/backend/soliplex_a2ui_workbench/src/'
      'soliplex_a2ui_workbench/catalog_teaching.json',
    );
    if (Platform.environment['WB_REGENERATE_TEACHING'] == '1') {
      const encoder = JsonEncoder.withIndent('  ');
      file.writeAsStringSync(
        '${encoder.convert(teaching.workbenchTeaching())}\n',
      );
    }
    final generated = jsonDecode(file.readAsStringSync());
    expect(generated, teaching.workbenchTeaching());
  });

  testWidgets('window mounts Python source and Run without execution', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var starts = 0;
    final store = ChatSurfaceStore(
      catalogs: [
        labCatalog(
          startRuntime: (limits, modules) async {
            starts++;
            throw StateError('must remain inert');
          },
        ),
      ],
    );
    addTearDown(store.dispose);
    final controller = store.obtain('program', [
      {
        'version': '1.0',
        'createSurface': {
          'surfaceId': 'program_surface',
          'catalogId':
              'https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json',
        },
      },
      {
        'version': '1.0',
        'updateDataModel': {
          'surfaceId': 'program_surface',
          'path': '/',
          'value': {'source': 'print("tally")'},
        },
      },
      {
        'version': '1.0',
        'updateComponents': {
          'surfaceId': 'program_surface',
          'components': [
            {
              'id': 'root',
              'component': 'PythonRepl',
              '@catalogId': labCatalogId,
              'source': {'@path': '/source'},
              'outputPath': '/output',
            },
          ],
        },
      },
    ]);
    expect(controller.error, isNull);
    final layout =
        jsonDecode(
              File(
                '../../../test/fixtures/workbench/layout_tree_v1.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final nodes = (layout['nodes'] as List).cast<Map<String, dynamic>>();
    (nodes.singleWhere((n) => n['id'] == 'r_canvas')['children'] as List).add(
      'window',
    );
    nodes.addAll([
      {
        'id': 'window',
        'parentId': 'r_canvas',
        'children': ['leaf'],
        'kind': 'window',
        'title': 'Tally Counter',
        'size': 'medium',
        'visibility': 'open',
        'payload': <String, dynamic>{},
      },
      {
        'id': 'leaf',
        'parentId': 'window',
        'children': <String>[],
        'kind': 'surface',
        'title': 'Program',
        'size': 'medium',
        'visibility': 'open',
        'payload': {
          'activityMessageId': 'program',
          'surfaceId': 'program_surface',
        },
      },
    ]);
    final tree = LayoutTree.fromLayout(layout, [
      WorkbenchRegistration(
        role: WorkbenchRole.program,
        activityMessageId: 'program',
        surfaceId: 'program_surface',
      ),
    ]);
    Widget host() => MaterialApp(
      theme: soliplexLightTheme(),
      home: Scaffold(
        body: WorkbenchHost(
          tree: tree,
          chat: const Text('Chat'),
          mounts: SurfaceMountRegistry(),
          surfaceBuilder: (activity, surface) =>
              ChatSurfaceView(controller: controller, surfaceId: surface),
        ),
      ),
    );
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('python-repl-editor')), findsOneWidget);
    expect(find.text('print("tally")'), findsOneWidget);
    expect(find.text('Run').hitTestable(), findsOneWidget);
    expect(starts, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('streamed program fills an already mounted empty window', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var starts = 0;
    final store = ChatSurfaceStore(
      catalogs: [
        chartPlaceholderCatalog(),
        labCatalog(
          startRuntime: (_, _) async {
            starts++;
            throw StateError('must remain inert');
          },
        ),
      ],
    );
    addTearDown(store.dispose);
    final messages = <String, GenUiMessage>{};
    final publications =
        (jsonDecode(publishedEventsJson) as List) +
        (jsonDecode(publishedProgramEventsJson) as List);
    await tester.pumpWidget(
      MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(
          body: ChatSurfaceScope(
            store: store,
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
    );
    for (final raw in publications) {
      final event = raw as Map<String, dynamic>;
      final content = event['content'] as Map<String, dynamic>;
      final registration =
          content['workbenchPublication'] as Map<String, dynamic>;
      messages[event['messageId'] as String] = GenUiMessage.create(
        id: event['messageId'] as String,
        widgetName: 'a2ui',
        data: {
          'messages': content['a2ui_operations'],
          'workbenchRegistration': registration,
        },
      );
      store.ingest(messages.values);
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('python-repl-editor')), findsOneWidget);
    expect(find.text('print(1)'), findsOneWidget);
    expect(find.text('Run').hitTestable(), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Workbench window Python'), findsOneWidget);
    semantics.dispose();
    // A formerly recommended repair sequence closed the source leaf, leaving
    // a title-only window. A repair now reopens that leaf in the accepted tree.
    final controlId = store.layoutActivityId!;
    void setProgramVisibility(String visibility) {
      final data =
          jsonDecode(jsonEncode(messages[controlId]!.data))
              as Map<String, dynamic>;
      final operations = (data['messages'] as List)
          .cast<Map<String, dynamic>>();
      final update = operations[1]['updateDataModel'] as Map<String, dynamic>;
      final value = update['value'] as Map<String, dynamic>;
      final tree = value['workbench'] as Map<String, dynamic>;
      tree['layoutRevision'] = (tree['layoutRevision'] as int) + 1;
      final nodes = (tree['nodes'] as List).cast<Map<String, dynamic>>();
      nodes.singleWhere(
        (node) =>
            node['kind'] == 'surface' &&
            (node['payload'] as Map<String, dynamic>)['surfaceId'] ==
                'surface_11',
      )['visibility'] = visibility;
      messages[controlId] = GenUiMessage.create(
        id: controlId,
        widgetName: 'a2ui',
        data: data,
      );
      store.ingest(messages.values);
    }

    setProgramVisibility('closed');
    await tester.pumpAndSettle();
    expect(find.text('print(1)'), findsNothing);
    expect(find.text('No open content.'), findsOneWidget);
    setProgramVisibility('open');
    await tester.pumpAndSettle();
    expect(find.text('print(1)'), findsOneWidget);
    expect(find.text('Run').hitTestable(), findsOneWidget);
    expect(starts, 0);
    expect(tester.takeException(), isNull);
  });
}
