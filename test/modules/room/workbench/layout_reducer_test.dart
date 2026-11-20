import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkbenchSnapshot;
import 'package:soliplex_frontend/src/modules/room/workbench/layout_reducer.dart';

void main() {
  test('accepts a complete snapshot and retains it on missing input', () {
    final reducer = LayoutReducer();
    final snapshot = WorkbenchSnapshot(
      revision: 0,
      layout: _layout,
      registrations: const [],
      records: const [],
    );
    expect(reducer.acceptSnapshot(snapshot), isTrue);
    final accepted = reducer.current;
    expect(reducer.acceptSnapshot(null), isFalse);
    expect(reducer.current, same(accepted));
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
