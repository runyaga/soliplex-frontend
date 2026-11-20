import 'dart:async';

import '../../test/flutter_test_config.dart' as monty;

Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    monty.testExecutable(testMain);
