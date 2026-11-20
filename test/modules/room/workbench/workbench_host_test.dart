import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_client/src/application/thread_history_replay.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_scope.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_view.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/message_timeline.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/chart_placeholder_catalog.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/layout_tree.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/panel_chrome.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/surface_mount_registry.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/workbench_host.dart';

import '../../../fixtures/workbench/workbench_fixtures.g.dart';
import '../../../fixtures/workbench_activity_events.dart';

void main() {
  testWidgets(
      'tool activities render basic form once, then replay on a fresh store',
      (tester) async {
    _desktop(tester);
    final events = _events();
    var fold = _fold();
    final liveStore = ChatSurfaceStore(catalogs: [chartPlaceholderCatalog()]);
    addTearDown(liveStore.dispose);
    for (final event in events) {
      fold = fold.apply(DecodedEvent(event, event.toJson())).fold;
      liveStore.ingest(fold.conversation.messages.whereType<GenUiMessage>(),
          activeRunId: 'run');
    }
    await tester.pumpWidget(_app(_host(liveStore, fold.conversation.messages)));
    await tester.pumpAndSettle();
    _expectCanvas(tester);
    final formId = events.first.messageId;
    final controller = liveStore[formId]!;
    expect(controller.error, isNull);
    await tester.enterText(find.byType(TextField), 'Need help');
    await tester.tap(find.text('North'));
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(controller.surfaces.single.dataModel.get('/question'), 'Need help');
    expect(controller.surfaces.single.dataModel.get('/districts'), ['north']);
    expect(controller.surfaces.single.dataModel.get('/acknowledged'), true);

    final history = replayThreadHistory(
        [
          (
            runId: 'run',
            parentRunId: null,
            created: DateTime.utc(2026),
            fetchError: null,
            fetchStackTrace: null,
            payload: (
              events: <Map<String, dynamic>>[
                RunStartedEvent(threadId: 'thread', runId: 'run').toJson(),
                ...events.map((event) => event.toJson()),
                const RunFinishedEvent(threadId: 'thread', runId: 'run')
                    .toJson(),
              ],
              userMessage: null,
              toolResults: <ToolMessage>[],
              endsWithToolMessage: false
            )
          ),
        ],
        'thread',
        null,
        null,
        {},
        null,
        null,
        observer: null);
    final replayStore = ChatSurfaceStore(catalogs: [chartPlaceholderCatalog()]);
    addTearDown(replayStore.dispose);
    replayStore.ingest(history.messages.whereType<GenUiMessage>());
    expect(replayStore.layout!.layout, liveStore.layout!.layout);
    expect(replayStore[formId]!.live, isFalse);
    expect(history.transcript.messages, isEmpty);
    await tester.pumpWidget(_app(_host(replayStore, history.messages)));
    await tester.pumpAndSettle();
    _expectCanvas(tester);
    expect(replayStore[formId]!.surfaces.single.dataModel.get('/question'), '');
  });

  testWidgets('activity arrival and a layout-only move preserve form bindings',
      (tester) async {
    _desktop(tester);
    final events = _events();
    var fold = _fold();
    final store = ChatSurfaceStore(catalogs: [chartPlaceholderCatalog()]);
    addTearDown(store.dispose);
    await tester.pumpWidget(_app(_host(store, const [])));
    for (final event in events.take(2)) {
      fold = fold.apply(DecodedEvent(event, event.toJson())).fold;
      store.ingest(fold.conversation.messages.whereType<GenUiMessage>(),
          activeRunId: 'run');
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final controller = store[events.first.messageId];
    await tester.enterText(find.byType(TextField), 'Keep this');
    final before = tester.getRect(find.byType(TextField));
    for (final event in events.skip(2)) {
      fold = fold.apply(DecodedEvent(event, event.toJson())).fold;
      store.ingest(fold.conversation.messages.whereType<GenUiMessage>(),
          activeRunId: 'run');
      await tester.pump();
    }
    final moved = _moveToRight(events.last);
    fold = fold.apply(DecodedEvent(moved, moved.toJson())).fold;
    store.ingest(fold.conversation.messages.whereType<GenUiMessage>());
    await tester.pumpAndSettle();
    expect(store[events.first.messageId], same(controller));
    expect(find.text('Keep this'), findsOneWidget);
    expect(
        tester.getRect(find.byType(TextField)).left, greaterThan(before.left));
    expect(tester.takeException(), isNull);
  });

  test('incomplete layout retains the usable tree and recovers from activities',
      () {
    final events = _events();
    var fold = _fold();
    final store = ChatSurfaceStore(catalogs: [chartPlaceholderCatalog()]);
    addTearDown(store.dispose);
    for (final event in events.take(2)) {
      fold = fold.apply(DecodedEvent(event, event.toJson())).fold;
    }
    store.ingest(fold.conversation.messages.whereType<GenUiMessage>());
    final accepted = store.layout;
    fold = fold.apply(DecodedEvent(events.last, events.last.toJson())).fold;
    store.ingest(fold.conversation.messages.whereType<GenUiMessage>());
    expect(store.layout, same(accepted));
    expect(store.layoutError, isNotNull);
    fold = fold.apply(DecodedEvent(events[2], events[2].toJson())).fold;
    store.ingest(fold.conversation.messages.whereType<GenUiMessage>());
    expect(store.layout!.layout['layoutRevision'], 2);
    expect(store.layoutError, isNull);
  });

  test(
      'a name, data-model key or journal wrapper cannot grant layout authority',
      () {
    final event = _events().last;
    final store = ChatSurfaceStore();
    addTearDown(store.dispose);
    final unregistered = ActivitySnapshotEvent(
        messageId: 'layout',
        activityType: 'a2ui-surface',
        replace: true,
        content: {
          'a2ui_operations': (event.content! as Map)['a2ui_operations'],
          'workbenchCommit': {'role': 'layout'}
        });
    final fold =
        _fold().apply(DecodedEvent(unregistered, unregistered.toJson())).fold;
    store.ingest(fold.conversation.messages.whereType<GenUiMessage>());
    expect(store.layout, isNull);
    expect(store.layoutActivityId, isNull);
  });

  test('a foreign surface operation cannot acquire a server publication role',
      () {
    final event = _events().first;
    final raw = jsonDecode(jsonEncode(event.toJson())) as Map<String, dynamic>;
    raw['content']['a2ui_operations'][0]['createSurface']['surfaceId'] =
        'foreign';
    final invalid = ActivitySnapshotEvent.fromJson(raw);
    final fold = _fold().apply(DecodedEvent(invalid, invalid.toJson())).fold;
    expect((fold.conversation.messages.single as GenUiMessage).data,
        isNot(contains('workbenchRegistration')));
  });

  testWidgets('a host leaf renders only its registered surface',
      (tester) async {
    final store = ChatSurfaceStore();
    addTearDown(store.dispose);
    final content = _events().first.content! as Map;
    final operations = (content['a2ui_operations'] as List)
        .map((op) => Map<String, Object?>.from(op as Map))
        .toList();
    final other = (jsonDecode(jsonEncode(operations)) as List)
        .map((op) => Map<String, Object?>.from(op as Map))
        .toList();
    for (final operation in other) {
      for (final body in operation.values.whereType<Map>()) {
        body['surfaceId'] = 'other';
      }
    }
    final controller = store.obtain('multi', [...operations, ...other]);
    final registration = content['workbenchPublication'] as Map;
    await tester.pumpWidget(_app(ChatSurfaceView(
      controller: controller,
      surfaceId: registration['surfaceId'] as String,
    )));
    await tester.pumpAndSettle();
    expect(controller.surfaces, hasLength(2));
    expect(find.text('Question'), findsOneWidget);
    expect(controller.error, isNull);
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
    expect(tester.takeException(), isNull);
  });

  testWidgets('host exports a semantics container for every region',
      (tester) async {
    _desktop(tester);
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_app(_regionHost()));
    await tester.pumpAndSettle();
    for (final role in ['chat', 'left', 'right', 'canvas', 'tray']) {
      expect(find.bySemanticsLabel('Workbench region $role'), findsOneWidget);
    }
    handle.dispose();
  });

  testWidgets(
      'sidebar form grows beyond the former panel height and Submit is hittable',
      (tester) async {
    _desktop(tester);
    final store = ChatSurfaceStore(catalogs: [chartPlaceholderCatalog()]);
    addTearDown(store.dispose);
    var fold = _fold();
    for (final event in _events()) {
      fold = fold.apply(DecodedEvent(event, event.toJson())).fold;
    }
    store.ingest(fold.conversation.messages.whereType<GenUiMessage>());
    await tester.pumpWidget(_app(_host(store, fold.conversation.messages)));
    await tester.pumpAndSettle();
    final panel = find.ancestor(
        of: find.text('Submit'), matching: find.byType(PanelChrome));
    expect(tester.getSize(panel).height, greaterThan(240));
    expect(find.text('Submit').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Submit'));
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
}

void _expectCanvas(WidgetTester tester) {
  for (final label in [
    'Question',
    'North',
    'South',
    'Acknowledged',
    'Submit'
  ]) {
    expect(
        find.descendant(
            of: find.byType(PanelChrome), matching: find.text(label)),
        findsOneWidget);
  }
  expect(find.byType(TextField), findsOneWidget);
  expect(
      find.descendant(
          of: find.byType(MessageTimeline),
          matching: find.byType(ChatSurfaceView)),
      findsNothing);
  expect(
      find.descendant(
          of: find.byType(MessageTimeline),
          matching: find.text('Surface in workspace')),
      findsNWidgets(2));
  expect(find.text('Workspace layout updated'), findsOneWidget);
  expect(find.text('bar chart preview'), findsOneWidget);
  expect(find.text('North: 80.0'), findsOneWidget);
  expect(find.textContaining('Cannot render surface'), findsNothing);
  expect(tester.takeException(), isNull);
}

List<ActivitySnapshotEvent> _events() => (jsonDecode(publishedEventsJson)
        as List)
    .map((event) =>
        ActivitySnapshotEvent.fromJson(Map<String, dynamic>.from(event as Map)))
    .toList();

RunFold _fold() => RunFold.start(Conversation.empty(threadId: 'thread'),
    runId: 'run',
    userMessageId: null,
    turnCitations: const TurnCitations.empty(),
    runCreated: DateTime.utc(2026));

Widget _host(ChatSurfaceStore store, List<ChatMessage> messages) =>
    ChatSurfaceScope(
      store: store,
      child: const ClientWorkbenchPresentation().buildHost(
        roomId: 'room',
        threadId: 'thread',
        chat: MessageTimeline(
            roomId: 'room', messages: messages, messageStates: const {}),
        surfaceBuilder: (activity, surface) =>
            ChatSurfaceView(controller: store[activity]!, surfaceId: surface),
      ),
    );

ActivitySnapshotEvent _moveToRight(ActivitySnapshotEvent event) {
  final raw = jsonDecode(jsonEncode(event.toJson())) as Map<String, dynamic>;
  final tree = raw['content']['a2ui_operations'][1]['updateDataModel']['value']
      ['workbench'];
  tree['layoutRevision'] = 3;
  final nodes = (tree['nodes'] as List).cast<Map<String, dynamic>>();
  final left = nodes.singleWhere((node) => node['id'] == 'r_left');
  final right = nodes.singleWhere((node) => node['id'] == 'r_right');
  final panel = (left['children'] as List).removeAt(0);
  (right['children'] as List).add(panel);
  nodes.singleWhere((node) => node['id'] == panel)['parentId'] = 'r_right';
  return ActivitySnapshotEvent.fromJson(raw);
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
