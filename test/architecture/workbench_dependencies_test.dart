import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('frontend workspace packages do not resolve dart_monty', () {
    final packageConfig = jsonDecode(
      File('.dart_tool/package_config.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final packages = packageConfig['packages']! as List<Object?>;
    expect(
      packages.whereType<Map<String, Object?>>().map((p) => p['name']),
      isNot(contains('dart_monty')),
    );
  });

  test('app, client, and agent do not depend on or import dart_monty', () {
    for (final path in [
      'pubspec.yaml',
      'packages/soliplex_client/pubspec.yaml',
      'packages/soliplex_agent/pubspec.yaml',
    ]) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('dart_monty:')),
        reason: path,
      );
    }

    for (final root in [
      Directory('lib'),
      Directory('packages/soliplex_client/lib'),
      Directory('packages/soliplex_agent/lib'),
    ]) {
      for (final file in root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))) {
        expect(
          file.readAsStringSync(),
          isNot(contains('package:dart_monty/')),
          reason: file.path,
        );
      }
    }
  });

  test('dependency checker rejects a constructed forbidden edge', () {
    expect(
      _isForbiddenEdge(
        from: 'packages/soliplex_catalogs/lib/catalog.dart',
        to: 'package:dart_monty/dart_monty.dart',
      ),
      isTrue,
    );
    expect(
      _isForbiddenEdge(
        from: 'packages/soliplex_client/lib/client.dart',
        to: 'package:soliplex_logging/soliplex_logging.dart',
      ),
      isFalse,
    );
  });
}

bool _isForbiddenEdge({required String from, required String to}) =>
    (from.startsWith('lib/') ||
        from.startsWith('packages/soliplex_client/') ||
        from.startsWith('packages/soliplex_agent/') ||
        from.startsWith('packages/soliplex_catalogs/')) &&
    to.startsWith('package:dart_monty/');
