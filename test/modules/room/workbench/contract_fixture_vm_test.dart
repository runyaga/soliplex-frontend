@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/workbench/workbench_fixtures.g.dart';

void main() {
  test('generated fixtures exactly match on-disk JSON', () {
    final files = Directory('test/fixtures/workbench')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'));
    final onDisk = {
      for (final file in files)
        file.uri.pathSegments.last: utf8.decode(file.readAsBytesSync()),
    };
    expect(workbenchFixtures, onDisk);
  });
}
