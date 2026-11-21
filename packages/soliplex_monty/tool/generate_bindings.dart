// Run with: flutter test tool/generate_bindings.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_monty/src/bindings/generated_source.dart';
import 'package:soliplex_monty/src/bindings/host_bindings.dart';

void main() {
  test('regenerate host binding stubs', () {
    final stubs = {
      for (final entry in generateBindings().entries)
        entry.key: entry.value.stubs,
    };
    File(
      'lib/src/bindings/binding_stubs.g.dart',
    ).writeAsStringSync(generatedDart(stubs));
    // Package the same text with the backend for normal and AI Fix teaching.
    final backend = Directory(
      '../../workbench/backend/'
      'soliplex_a2ui_workbench/src/soliplex_a2ui_workbench/binding_stubs',
    )..createSync(recursive: true);
    for (final entry in stubs.entries) {
      File('${backend.path}/${entry.key}.pyi').writeAsStringSync(entry.value);
    }
  });
}
