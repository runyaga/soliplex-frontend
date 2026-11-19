@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  _registerPackageConfigTest();
  _registerRepositoryScanTest();
  _registerSyntheticScanTest();
  _registerAllowedClientEdgeTest();
}

void _registerPackageConfigTest() {
  test('frontend packages do not resolve dart_monty', () {
    final packageConfig = jsonDecode(
      File('.dart_tool/package_config.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final packages = packageConfig['packages']! as List<Object?>;
    expect(
      packages.whereType<Map<String, Object?>>().map((p) => p['name']),
      isNot(contains('dart_monty')),
    );
  });
}

void _registerRepositoryScanTest() {
  test('protected package sources have no forbidden dependency edges', () {
    expect(_scanForbiddenEdges(_repositorySources()), isEmpty);
  });
}

void _registerSyntheticScanTest() {
  test('shared scanner detects synthetic dependency and import edges', () {
    final synthetic = [
      _SourceFile(
        'packages/soliplex_catalogs/pubspec.yaml',
        'dependencies:\n  dart_monty: ^1.0.0\n',
      ),
      _SourceFile(
        'packages/soliplex_catalogs/lib/chart.dart',
        "import 'package:dart_monty/dart_monty.dart';\n",
      ),
      _SourceFile(
        'packages/soliplex_catalogs/pubspec.yaml',
        'dependencies:\n  soliplex_monty: ^1.0.0\n',
      ),
      _SourceFile(
        'packages/soliplex_catalogs/lib/runner.dart',
        "import 'package:soliplex_monty/soliplex_monty.dart';\n",
      ),
    ];
    final violations = _scanForbiddenEdges(synthetic);
    expect(violations, hasLength(4));
    expect(
        violations.map((edge) => edge.from),
        containsAll([
          'packages/soliplex_catalogs/pubspec.yaml',
          'packages/soliplex_catalogs/lib/chart.dart',
          'packages/soliplex_catalogs/lib/runner.dart',
        ]));
  });
}

void _registerAllowedClientEdgeTest() {
  test('unrelated client package imports remain allowed', () {
    final source = [
      _SourceFile(
        'packages/soliplex_client/lib/client.dart',
        "import 'package:soliplex_logging/soliplex_logging.dart';\n",
      ),
    ];
    expect(_scanForbiddenEdges(source), isEmpty);
  });
}

Iterable<_SourceFile> _repositorySources() sync* {
  const manifests = [
    'pubspec.yaml',
    'packages/soliplex_client/pubspec.yaml',
    'packages/soliplex_agent/pubspec.yaml',
    'packages/soliplex_catalogs/pubspec.yaml',
  ];
  for (final path in manifests) {
    final file = File(path);
    if (file.existsSync()) yield _SourceFile(path, file.readAsStringSync());
  }
  const sourceRoots = [
    'lib',
    'packages/soliplex_client/lib',
    'packages/soliplex_agent/lib',
    'packages/soliplex_catalogs/lib',
  ];
  for (final path in sourceRoots) {
    final root = Directory(path);
    if (!root.existsSync()) continue;
    for (final file in root
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      yield _SourceFile(file.path, file.readAsStringSync());
    }
  }
}

List<_DependencyEdge> _scanForbiddenEdges(Iterable<_SourceFile> sources) =>
    sources.expand(_edgesFromSource).where(_isForbiddenEdge).toList();

Iterable<_DependencyEdge> _edgesFromSource(_SourceFile source) sync* {
  final imports = RegExp(
    r'''(?:import|export|part\s+of)\s+['"]package:((?:dart_monty|soliplex_monty)/[^'"]+)['"]''',
  );
  for (final match in imports.allMatches(source.contents)) {
    yield _DependencyEdge(source.path, 'package:${match[1]}');
  }
  if (source.path.endsWith('pubspec.yaml')) {
    final dependencies = RegExp(
      r'^\s*(dart_monty|soliplex_monty)\s*:',
      multiLine: true,
    );
    for (final match in dependencies.allMatches(source.contents)) {
      yield _DependencyEdge(source.path, 'dependency:${match[1]}');
    }
  }
}

bool _isForbiddenEdge(_DependencyEdge edge) {
  const directCoreRoots = [
    'lib/',
    'packages/soliplex_client/',
    'packages/soliplex_agent/',
  ];
  final forbiddenCoreEdge = directCoreRoots.any(edge.from.startsWith) &&
      (edge.to.startsWith('package:dart_monty/') ||
          edge.to == 'dependency:dart_monty');
  final forbiddenCatalogEdge =
      edge.from.startsWith('packages/soliplex_catalogs/') &&
          (edge.to.startsWith('package:dart_monty/') ||
              edge.to.startsWith('package:soliplex_monty/') ||
              edge.to == 'dependency:dart_monty' ||
              edge.to == 'dependency:soliplex_monty');
  return forbiddenCoreEdge || forbiddenCatalogEdge;
}

class _SourceFile {
  const _SourceFile(this.path, this.contents);

  final String path;
  final String contents;
}

class _DependencyEdge {
  const _DependencyEdge(this.from, this.to);

  final String from;
  final String to;
}
