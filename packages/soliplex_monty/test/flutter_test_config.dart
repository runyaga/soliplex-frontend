import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // A platform read started in a widget test's fake zone can be abandoned
  // when that test ends. Never carry its cached future into the next test.
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(SharedPreferences.resetStatic);
  await testMain();
}
