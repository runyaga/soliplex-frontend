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
import '../../test/support/monty.dart';
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

  for (final execute in [false, true]) {
    testWidgets(
      execute
          ? '40-line canvas program has reachable drawn buttons after Run'
          : '40-line window mounts source and hittable Run without scrolling',
      (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1600, 1000);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final lines = _tallySource.trim().split('\n');
        final source = [
          ...lines,
          ...List.filled(40 - lines.length, '# padding'),
        ].join('\n');
        expect(source.split('\n'), hasLength(40));
        final starter = MontyStarter();
        var starts = 0;
        final store = ChatSurfaceStore(
          catalogs: [
            labCatalog(
              startRuntime: execute
                  ? starter.call
                  : (limits, modules) async {
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
              'value': {'source': source},
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
        (nodes.singleWhere((n) => n['id'] == 'r_canvas')['children'] as List)
            .add(
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
        expect(
          find.byKey(const ValueKey('python-repl-editor')),
          findsOneWidget,
        );
        expect(find.text(source), findsOneWidget);
        expect(find.text('Run').hitTestable(), findsOneWidget);
        expect(starts, 0);
        expect(starter.starts, 0);
        final editorScroll = tester.state<ScrollableState>(
          find.descendant(
            of: find.byKey(const ValueKey('python-repl-editor')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(editorScroll.position.maxScrollExtent, greaterThan(0));
        final windowScroll = find
            .ancestor(
              of: find.byType(PythonReplView),
              matching: find.byType(SingleChildScrollView),
            )
            .first;
        ScrollPosition windowPosition() => tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: windowScroll,
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        expect(windowPosition().pixels, 0);
        if (execute) {
          await tester.runAsync(() => tester.tap(find.text('Run')));
          await pumpUntil(tester, () => find.text('+1').evaluate().isNotEmpty);
          expect(starter.starts, 1);
          expect(find.text('+1').hitTestable(), findsNothing);
          for (final (label, count) in [
            ('+1', 1),
            ('-1', 0),
            ('+1', 1),
            ('Reset', 0),
          ]) {
            final button = find.text(label);
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            expect(button.hitTestable(), findsOneWidget);
            expect(windowPosition().pixels, greaterThan(0));
            await tester.runAsync(() => tester.tap(button));
            await tester.pump();
            await pumpUntil(
              tester,
              () =>
                  find.text('Count: $count').evaluate().isNotEmpty &&
                  tester
                          .widget<SoliplexButton>(
                            find.byKey(const ValueKey('python-repl-run')),
                          )
                          .onPressed !=
                      null,
            );
          }
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(starter.close);
        }
        expect(tester.takeException(), isNull);
      },
      skip: execute && skipWithoutMonty != false,
    );
  }
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

const _tallySource = '''
import ui
count = 0
def draw():
    details = [ui.Text("Detail " + str(i)) for i in range(24)]
    ui.show(ui.Column(details + [
        ui.Text("Count: " + str(count)),
        ui.Button(ui.Text("+1"), action=ui.Event("plus", {})),
        ui.Button(ui.Text("-1"), action=ui.Event("minus", {})),
        ui.Button(ui.Text("Reset"), action=ui.Event("reset", {})),
    ]))
def handle_event(name, context):
    global count
    if name == "plus":
        count += 1
    if name == "minus":
        count -= 1
    if name == "reset":
        count = 0
    draw()
draw()
''';
