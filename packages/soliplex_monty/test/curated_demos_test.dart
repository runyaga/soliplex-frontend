@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'support/monty.dart';
import 'support/showcase_checks.dart';

void main() {
  for (final name in showcaseNames) {
    test(
      '$name checks, runs and handles events in real Monty',
      () => checkShowcase(name),
      skip: skipWithoutMonty,
    );
  }
}
