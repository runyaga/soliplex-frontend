import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show WorkbenchRegistration, WorkbenchRole;
import 'package:soliplex_frontend/src/modules/room/workbench/layout_tree.dart';

import '../../../fixtures/workbench/workbench_fixtures.g.dart';

void main() {
  test('indexes a validated nested layout by stable node id', () {
    final tree = LayoutTree.fromLayout(_layout(), _registrations);
    expect(tree.node('form_panel')?.children.single, 'form_surface');
    expect(tree.node('form_surface')?.parentId, 'form_panel');
  });

  test('rejects invalid candidates without replacing accepted tree', () {
    final tree = LayoutTree.fromLayout(_layout(), _registrations);
    expect(
      () => LayoutTree.fromLayout({
        ..._layout(),
        'rootId': 'missing',
      }, _registrations),
      throwsFormatException,
    );
    expect(tree.node('form_panel'), isNotNull);
  });
}

Map<String, dynamic> _layout() =>
    jsonDecode(workbenchFixtures['nested_tree_v1.json']!)
        as Map<String, dynamic>;

List<WorkbenchRegistration> get _registrations {
  final layout = _layout();
  final nodes = layout['nodes']! as List;
  return [
    for (final raw in nodes.cast<Map<String, dynamic>>())
      if (raw['kind'] == 'surface')
        WorkbenchRegistration(
          role: (raw['payload']! as Map<String, dynamic>)['surfaceId'] ==
                  'surface_python'
              ? WorkbenchRole.program
              : WorkbenchRole.content,
          activityMessageId: (raw['payload']!
              as Map<String, dynamic>)['activityMessageId']! as String,
          surfaceId:
              (raw['payload']! as Map<String, dynamic>)['surfaceId']! as String,
        ),
  ];
}
