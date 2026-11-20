import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_scope.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_view.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/gen_ui_tile.dart';
import 'package:soliplex_frontend/src/modules/room/ui/message_timeline.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/chart_placeholder_catalog.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/layout_tree.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/panel_chrome.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/surface_mount_registry.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/workbench_host.dart';

import '../../../fixtures/workbench/workbench_fixtures.g.dart';
import '../../../fixtures/workbench_published_snapshot.dart';

void main() {
  for (final replay in [false, true]) {
    testWidgets(
        'published form and chart render in host on ${replay ? 'reload' : 'live delivery'}',
        (tester) async {
      _desktop(tester);
      final snapshot = _snapshot();
      final store = ChatSurfaceStore(catalogs: [chartPlaceholderCatalog()]);
      addTearDown(store.dispose);
      final messages = _project(snapshot);
      if (!replay) {
        for (final message in messages) {
          store.obtain(message.id, _operations(message.data['messages']));
        }
      }
      final client = _SnapshotClient(snapshot);
      await tester.pumpWidget(_app(ChatSurfaceScope(
        store: store,
        child: _host(client, store,
            chat: MessageTimeline(
              roomId: 'room',
              messages: messages,
              messageStates: const {},
            )),
      )));
      await tester.pumpAndSettle();

      final panels = find.byType(PanelChrome);
      for (final label in [
        'Question',
        'North',
        'South',
        'Acknowledged',
        'Submit'
      ]) {
        expect(find.descendant(of: panels, matching: find.text(label)),
            findsOneWidget);
      }
      expect(find.byType(GenUiTile), findsNothing);
      expect(
          find.descendant(
              of: find.byType(MessageTimeline),
              matching: find.byType(ChatSurfaceView)),
          findsNothing);
      expect(find.text('bar chart preview'), findsOneWidget);
      expect(find.text('North: 80'), findsOneWidget);
      expect(find.textContaining('Cannot render surface'), findsNothing);
      expect(tester.takeException(), isNull);
      final controller =
          store[snapshot.records.first.content['activityMessageId'] as String]!;
      expect(controller.error, isNull);
      // Scroll the panel to Submit, then exercise the actual basic controls.
      await tester.enterText(find.byType(TextField), 'Need help');
      await tester.tap(find.text('North'));
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      final model = controller.surfaces.single.dataModel;
      expect(model.get('/question'), 'Need help');
      expect(model.get('/districts'), ['north']);
      expect(model.get('/acknowledged'), true);
    });
  }

  testWidgets('a host leaf selects just its registered surface',
      (tester) async {
    final snapshot = _snapshot();
    final store = ChatSurfaceStore(catalogs: [chartPlaceholderCatalog()]);
    addTearDown(store.dispose);
    final first = snapshot.records.first.content;
    final ops = _operations(first['a2ui_operations']);
    final other = _operations(jsonDecode(jsonEncode(ops)));
    for (final op in other) {
      for (final body in op.values.whereType<Map>()) {
        body['surfaceId'] = 'other';
      }
    }
    final controller = store.obtain('multi', [...ops, ...other]);
    await tester.pumpWidget(_app(ChatSurfaceView(
      controller: controller,
      surfaceId: first['surfaceId'] as String,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Question'), findsOneWidget);
    expect(controller.surfaces, hasLength(2));
  });

  testWidgets('desktop places left, chat, canvas, right with tray below',
      (tester) async {
    _desktop(tester);
    await tester.pumpWidget(_app(_regionHost()));
    await tester.pumpAndSettle();
    final left = tester.getRect(find.text('left content'));
    final chat = tester.getRect(find.text('protected chat'));
    final canvas = tester.getRect(find.text('canvas content'));
    final right = tester.getRect(find.text('right content'));
    final tray = tester.getRect(find.text('tray content'));
    expect(left.right, lessThanOrEqualTo(chat.left));
    expect(chat.right, lessThanOrEqualTo(canvas.left));
    expect(canvas.right, lessThanOrEqualTo(right.left));
    expect(tray.top, greaterThan(right.bottom));
    expect(find.byType(TabBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow width keeps Chat and Workspace tabs', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(_regionHost()));
    await tester.pumpAndSettle();
    expect(find.text('protected chat').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Workspace'));
    await tester.pumpAndSettle();
    final left = tester.getRect(find.text('left content'));
    final canvas = tester.getRect(find.text('canvas content'));
    final right = tester.getRect(find.text('right content'));
    final tray = tester.getRect(find.text('tray content'));
    expect(left.top, lessThan(canvas.top));
    expect(canvas.top, lessThan(right.top));
    expect(right.top, lessThan(tray.top));
    expect(find.text('protected chat').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finished run rehydrates once and retains mounted form state',
      (tester) async {
    _desktop(tester);
    final store = ChatSurfaceStore(catalogs: [chartPlaceholderCatalog()]);
    addTearDown(store.dispose);
    final run = signal<String?>(null);
    addTearDown(run.dispose);
    final client = _SnapshotClient(_snapshot());
    Widget app() => _app(Watch((context) => ChatSurfaceScope(
          store: store,
          activeRunId: run.value,
          child: _host(client, store),
        )));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(client.calls, 1);
    await tester.enterText(find.byType(TextField), 'Keep this');
    final field = tester.element(find.byType(TextField));
    final controller =
        store[_snapshot().records.first.content['activityMessageId'] as String];
    run.value = 'run-1';
    await tester.pumpAndSettle();
    expect(client.calls, 1);
    client.snapshot = _withNewPanel();
    expect(find.text('Finished run panel'), findsNothing);
    run.value = null;
    await tester.pumpAndSettle();
    expect(find.text('Finished run panel'), findsOneWidget);
    expect(client.calls, 2);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(client.calls, 2);
    expect(tester.element(find.byType(TextField)), same(field));
    expect(
        store[_snapshot().records.first.content['activityMessageId'] as String],
        same(controller));
    expect(find.text('Keep this'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _desktop(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(Widget child) => ProviderScope(
      overrides: [
        messageExpansionsProvider.overrideWithValue(MessageExpansions())
      ],
      child:
          MaterialApp(theme: soliplexLightTheme(), home: Scaffold(body: child)),
    );

WorkbenchSnapshot _snapshot() => WorkbenchSnapshot.fromJson(
    jsonDecode(publishedSnapshotJson) as Map<String, dynamic>);

List<Map<String, Object?>> _operations(Object? raw) =>
    (raw as List).map((m) => Map<String, Object?>.from(m as Map)).toList();

List<GenUiMessage> _project(WorkbenchSnapshot snapshot) {
  var conversation = Conversation.empty(threadId: 'thread');
  for (final part in snapshot.records) {
    conversation = processEvent(
            conversation,
            const AwaitingText(),
            ActivitySnapshotEvent(
              messageId: part.content['activityMessageId'] as String,
              activityType: 'a2ui-surface',
              replace: true,
              content: {
                'a2ui_operations': part.content['a2ui_operations'],
                'workbenchCommit': part.content['workbenchCommit'],
              },
            ),
            createdAt: null)
        .conversation;
  }
  final layoutActivity =
      snapshot.registrations.singleWhere((r) => r.role == WorkbenchRole.layout);
  conversation = processEvent(
          conversation,
          const AwaitingText(),
          ActivitySnapshotEvent(
            messageId: layoutActivity.activityMessageId,
            activityType: 'a2ui-surface',
            replace: true,
            content: {
              'a2ui_operations': _textOperations(
                  layoutActivity.surfaceId, 'Workbench control'),
              'workbenchCommit': {
                'recordId': 'publication',
                'sequence': 1,
                'index': 2,
                'count': 3
              }
            },
          ),
          createdAt: null)
      .conversation;
  return conversation.messages.cast<GenUiMessage>();
}

Widget _host(_SnapshotClient client, ChatSurfaceStore store,
        {Widget chat = const Text('protected chat')}) =>
    const ClientWorkbenchPresentation().buildHost(
      roomId: 'room',
      threadId: 'thread',
      client: client,
      chat: chat,
      surfaceBuilder: (activity, surface) => store[activity] == null
          ? const SizedBox.shrink()
          : ChatSurfaceView(controller: store[activity]!, surfaceId: surface),
    );

class _SnapshotClient implements WorkbenchClient {
  _SnapshotClient(this.snapshot);
  WorkbenchSnapshot snapshot;
  int calls = 0;
  @override
  Future<WorkbenchSnapshot> getSnapshot(
      {required String roomId,
      required String threadId,
      CancelToken? cancelToken}) async {
    calls++;
    return snapshot;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _regionHost() {
  final layout = jsonDecode(workbenchFixtures['layout_tree_v1.json']!)
      as Map<String, dynamic>;
  final nodes = (layout['nodes'] as List).cast<Map<String, dynamic>>();
  final registrations = <WorkbenchRegistration>[];
  for (final role in ['left', 'canvas', 'right', 'tray']) {
    final region = nodes.singleWhere((n) => n['id'] == 'r_$role');
    (region['children'] as List).add('panel_$role');
    nodes.addAll([
      _node('panel_$role', 'r_$role', ['leaf_$role'], 'panel', {}),
      _node(
          'leaf_$role',
          'panel_$role',
          [],
          'surface',
          {
            'activityMessageId': 'activity_$role',
            'surfaceId': 'surface_$role'
          }),
    ]);
    registrations.add(WorkbenchRegistration(
        role: WorkbenchRole.content,
        activityMessageId: 'activity_$role',
        surfaceId: 'surface_$role'));
  }
  return WorkbenchHost(
      tree: LayoutTree.fromLayout(layout, registrations),
      chat: const Text('protected chat'),
      surfaceBuilder: (activity, surface) =>
          Text('${surface.substring(8)} content'),
      mounts: SurfaceMountRegistry());
}

Map<String, dynamic> _node(String id, String parent, List<String> children,
        String kind, Map<String, dynamic> payload) =>
    {
      'id': id,
      'parentId': parent,
      'children': children,
      'kind': kind,
      'title': id,
      'size': 'medium',
      'visibility': 'open',
      'payload': payload,
    };

List<Map<String, Object?>> _textOperations(String surface, String text) => [
      {
        'version': '1.0',
        'createSurface': {
          'surfaceId': surface,
          'catalogId':
              'https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json'
        }
      },
      {
        'version': '1.0',
        'updateComponents': {
          'surfaceId': surface,
          'components': [
            {'id': 'root', 'component': 'Text', 'text': text}
          ]
        }
      },
    ];

WorkbenchSnapshot _withNewPanel() {
  final json = jsonDecode(publishedSnapshotJson) as Map<String, dynamic>;
  final nodes = (json['layout']['nodes'] as List).cast<Map<String, dynamic>>();
  (nodes.singleWhere((n) => n['id'] == 'r_right')['children'] as List)
      .add('finished_panel');
  nodes.addAll([
    _node('finished_panel', 'r_right', ['finished_surface'], 'panel', {}),
    _node(
        'finished_surface',
        'finished_panel',
        [],
        'surface',
        {
          'activityMessageId': 'activity_finished',
          'surfaceId': 'surface_finished'
        }),
  ]);
  (json['registrations'] as List).add({
    'role': 'content',
    'activityMessageId': 'activity_finished',
    'surfaceId': 'surface_finished'
  });
  (json['records'] as List).add({
    'recordId': 'finished_publication',
    'sequence': 3,
    'partIndex': 0,
    'partCount': 1,
    'content': {
      'activityMessageId': 'activity_finished',
      'surfaceId': 'surface_finished',
      'a2ui_operations':
          _textOperations('surface_finished', 'Finished run panel')
    }
  });
  json['revision'] = 3;
  json['layout']['layoutRevision'] = 3;
  return WorkbenchSnapshot.fromJson(json);
}
