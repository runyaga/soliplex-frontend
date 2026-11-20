@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/monty_native.dart';

void main() {
  test('package and example resolve the same default worker', () {
    final original = Directory.current;
    addTearDown(() => Directory.current = original);
    final worker = defaultMontyWorker();
    Directory.current = Directory('example');
    expect(defaultMontyWorker(), worker);
    expect(File(worker).isAbsolute, isTrue);
    if (File(worker).existsSync() &&
        !Platform.environment.containsKey('MONTY_WORKER')) {
      expect(skipWithoutMonty, isFalse);
    }
  });
}
