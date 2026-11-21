import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_monty/ui_bridge.dart';

void main() {
  test('ui_bridge builds an arena without the lab runtime', () {
    final arena = PythonUiArena();
    expect(arena.maxNodes, PythonUiArena.defaultMaxNodes);
    expect(chartModule, isNotNull);
  });

  test('ui_bridge does not reach lab_catalog.dart', () {
    final seen = <String>{};
    final pending = ['lib/ui_bridge.dart'];
    final directive = RegExp(
      "^(?:import|export|part) '([^']+)'",
      multiLine: true,
    );
    while (pending.isNotEmpty) {
      final path = pending.removeLast();
      if (!seen.add(path) || !File(path).existsSync()) continue;
      for (final match in directive.allMatches(File(path).readAsStringSync())) {
        final uri = match.group(1)!;
        if (uri.startsWith('package:soliplex_monty/')) {
          pending.add('lib/${uri.substring('package:soliplex_monty/'.length)}');
        } else if (!uri.startsWith('package:') && !uri.startsWith('dart:')) {
          pending.add(
            File(
              path,
            ).parent.uri.resolve(uri).path.replaceFirst(RegExp('^/'), ''),
          );
        }
      }
    }
    expect(seen, contains('lib/src/python_ui.dart'));
    expect(seen.where((p) => p.endsWith('lab_catalog.dart')), isEmpty);
  }, testOn: 'vm');
}
