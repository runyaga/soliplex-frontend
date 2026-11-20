import 'dart:convert';
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_controller.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_view.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/workbench_host.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/layout_tree.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/surface_mount_registry.dart';

import '../../../fixtures/custom_form_events.dart';

void main() {
  testWidgets(
      'custom form renders each kind with isolated semantics and submits current values',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    final actions = <Map<String, Object?>>[];
    final controller = _controller(actions.add);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(
            body: SingleChildScrollView(
                child: ChatSurfaceView(controller: controller)))));
    await tester.pumpAndSettle();
    expect(controller.error, isNull);
    expect(actions, isEmpty);
    expect(find.text('Form created by the assistant'), findsOneWidget);
    for (final label in ['Name', 'Notes', 'Age']) {
      final field = find.widgetWithText(TextField, label);
      expect(tester.getSemantics(field).label, label);
      expect(tester.getSize(field).isFinite, isTrue);
    }
    expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Notes'))
            .maxLines,
        isNull);
    expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Age'))
            .keyboardType,
        const TextInputType.numberWithOptions(signed: true, decimal: true));
    // This is the role used by the model harness. Multiple choice remains a
    // checkbox list. Each option must have its own, unmerged accessible name.
    final blue = find.widgetWithText(RadioListTile<String>, 'Blue');
    expect(tester.getSemantics(blue).label, 'Blue');
    expect(
        tester
            .getSemantics(blue)
            .getSemanticsData()
            .flagsCollection
            .isInMutuallyExclusiveGroup,
        isTrue);
    expect(
        tester.getSemantics(blue).getSemanticsData().flagsCollection.isChecked,
        CheckedState.isFalse);
    expect(
        tester
            .getSemantics(find.widgetWithText(CheckboxListTile, 'North'))
            .label,
        'North');
    expect(tester.getSemantics(find.text('Day')).label, 'Day');
    expect(
        tester
            .getSemantics(find
                .ancestor(
                    of: find.text('Subscribe'),
                    matching: find.byType(MergeSemantics))
                .first)
            .getSemanticsData()
            .label,
        'Subscribe');
    await tester.enterText(
        find.widgetWithText(TextField, 'Name'), 'Scenario walrus');
    await tester.enterText(
        find.widgetWithText(TextField, 'Notes'), 'Current notes');
    await tester.enterText(find.widgetWithText(TextField, 'Age'), '42');
    await tester.tap(blue);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'North'));
    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();
    // Use the actual date picker so its model write is covered too.
    await tester.tap(find
        .ancestor(of: find.text('Day'), matching: find.byType(InkWell))
        .first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(actions, isEmpty);
    await tester.ensureVisible(find.text('Submit'));
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(actions, hasLength(1));
    expect(actions.single['name'], 'submit_form');
    expect(actions.single['sourceComponentId'], 'submit');
    final values = (actions.single['context']! as Map)['values']! as Map;
    expect(values, containsPair('name', 'Scenario walrus'));
    expect(values, containsPair('notes', 'Current notes'));
    expect(values, containsPair('age', '42'));
    expect(values, containsPair('color', ['Blue']));
    expect(values, containsPair('districts', ['North']));
    expect(values, containsPair('subscribe', true));
    expect(values['day'], matches(r'^\d{4}-\d{2}-\d{2}$'));
    expect(tester.takeException(), isNull);
    semantics.dispose();
    // Reconstructing from a stored activity is inert and starts with the
    // published defaults, rather than replaying any submission gesture.
    final replay = _controller(actions.add);
    addTearDown(replay.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: ChatSurfaceView(controller: replay)))));
    await tester.pumpAndSettle();
    expect(actions, hasLength(1));
    expect(replay.surfaces.single.dataModel.get('/values/name'), '');
  });

  for (final parent in ['region', 'window', 'split', 'tabs']) {
    testWidgets('custom form has finite bounds inside $parent', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 1600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _controller((_) => fail('Mounting must not submit'));
      addTearDown(controller.dispose);
      final layoutEvent =
          (jsonDecode(customFormEventsJson) as List).last as Map;
      final operations = layoutEvent['content']['a2ui_operations'] as List;
      final layout = Map<String, dynamic>.from(
          operations[1]['updateDataModel']['value']['workbench'] as Map);
      final nodes = (layout['nodes'] as List).cast<Map<String, dynamic>>();
      if (parent != 'region') {
        final region = nodes.singleWhere((n) => n['id'] == 'r_left');
        final panelId = (region['children'] as List).removeAt(0);
        final panel = nodes.singleWhere((n) => n['id'] == panelId);
        if (parent == 'window') {
          panel['kind'] = 'window';
          panel['parentId'] = 'r_canvas';
          (nodes.singleWhere((n) => n['id'] == 'r_canvas')['children'] as List)
              .add(panelId);
        } else {
          (region['children'] as List).add('container');
          panel['parentId'] = 'container';
          nodes.add({
            'id': 'container',
            'kind': parent,
            'parentId': 'r_left',
            'children': [panelId],
            'title': 'Survey container',
            'size': 'large',
            'visibility': 'open',
            'payload':
                parent == 'split' ? {'axis': 'horizontal'} : <String, dynamic>{}
          });
        }
      }
      final tree = LayoutTree.fromLayout(layout, [
        WorkbenchRegistration(
            role: WorkbenchRole.content,
            activityMessageId: 'activity_1',
            surfaceId: 'surface_2')
      ]);
      await tester.pumpWidget(MaterialApp(
          theme: soliplexLightTheme(),
          home: Scaffold(
              body: WorkbenchHost(
                  tree: tree,
                  chat: const Text('Chat'),
                  surfaceBuilder: (_, __) =>
                      ChatSurfaceView(controller: controller),
                  mounts: SurfaceMountRegistry()))));
      await tester.pumpAndSettle();
      expect(controller.error, isNull);
      expect(find.text('Form created by the assistant'), findsOneWidget);
      await tester.ensureVisible(find.text('Submit'));
      expect(find.text('Submit').hitTestable(), findsOneWidget);
      for (final field in find.byType(TextField).evaluate()) {
        expect(tester.getSize(find.byWidget(field.widget)).isFinite, isTrue);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

ChatSurfaceController _controller(
    void Function(Map<String, Object?>) onAction) {
  final event = (jsonDecode(customFormEventsJson) as List).first as Map;
  final operations = (event['content']['a2ui_operations'] as List)
      .map((op) => Map<String, Object?>.from(op as Map))
      .toList();
  return ChatSurfaceController(onActionPayload: onAction)..apply(operations);
}
