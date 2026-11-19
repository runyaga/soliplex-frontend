import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_monty/src/python_ui.dart';
import 'package:soliplex_monty/src/workspace_files.dart';

const _sales = 'month,region,revenue\n2026-01,North,10.5\n2026-01,South,\n';

void main() {
  test('Python UI arena creates a nonce in the browser runtime', () {
    expect(PythonUiArena(), isA<PythonUiArena>());
  });

  group('workspaceFiles', () {
    test('reads name and content pairs', () {
      final files = workspaceFiles([
        {'name': 'sales.csv', 'content': _sales},
      ]);

      expect(files.single.path, '/workspace/room/sales.csv');
      expect(files.single.bytes.length, _sales.length);
    });

    test('mounts nothing for a malformed or oversized payload', () {
      final big = 'x' * (maxWorkspaceBytes ~/ 2 + 1);
      for (final raw in <List<Object?>>[
        [
          {'name': '../x.csv', 'content': ''},
        ],
        [
          {'name': 'a/b.csv', 'content': ''},
        ],
        [
          {'name': 'a.csv'},
        ],
        [
          {'name': 'a.csv', 'content': ''},
          {'name': 'a.csv', 'content': ''},
        ],
        [
          for (var i = 0; i <= maxWorkspaceFiles; i++)
            {'name': 'f$i.csv', 'content': ''},
        ],
        [
          {'name': 'a.csv', 'content': big},
          {'name': 'b.csv', 'content': big},
        ],
      ]) {
        expect(workspaceFiles(raw), isEmpty, reason: '$raw');
      }
    });
  });
}
