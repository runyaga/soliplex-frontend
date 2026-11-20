import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/layout_tree.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/surface_mount_registry.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/workbench_host.dart';

void main() {
  testWidgets('renders protected chat beside the accepted workspace tree',
      (tester) async {
    final tree = LayoutTree.fromLayout(_layout);
    tester.view.physicalSize = const Size(1600, 1000);
    await tester.pumpWidget(MaterialApp(
      home: SizedBox.expand(
        child: WorkbenchHost(
          tree: tree,
          chat: const Text('protected chat'),
          surfaceBuilder: (_, __) => const Text('registered surface'),
          mounts: SurfaceMountRegistry(),
        ),
      ),
    ));
    expect(find.text('protected chat'), findsOneWidget);
    expect(find.text('registered surface'), findsNothing);
  });
}

final Map<String, dynamic> _layout = {
  'schemaVersion': 1,
  'layoutRevision': 0,
  'rootId': 'wb_root',
  'shared': <String, dynamic>{},
  'nodes': [
    _node('wb_root', null,
        ['r_chat', 'r_left', 'r_right', 'r_canvas', 'r_tray'], 'workspace', {}),
    _node('r_chat', 'wb_root', [], 'region', {'role': 'chat'}),
    _node('r_left', 'wb_root', [], 'region', {'role': 'left'}),
    _node('r_right', 'wb_root', [], 'region', {'role': 'right'}),
    _node('r_canvas', 'wb_root', [], 'region', {'role': 'canvas'}),
    _node('r_tray', 'wb_root', [], 'region', {'role': 'tray'}),
  ],
};

Map<String, dynamic> _node(String id, String? parent, List<String> children,
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
