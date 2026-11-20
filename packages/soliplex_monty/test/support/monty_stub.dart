import 'package:dart_monty/dart_monty.dart';
import 'package:flutter_test/flutter_test.dart';

/// Browser-side marker; browser tests must not import a native worker.
const Object skipWithoutMonty = 'Monty runtime is native-only';

/// Placeholder for shared test sources; native-worker tests are skipped.
const String montyWorker = '';

/// Runtime starter stub for browser test loading.
class MontyStarter {
  MontyStarter({this.delay = Duration.zero});

  final Duration delay;
  final List<Monty> pools = [];
  final List<MontyRuntime> runtimes = [];
  int starts = 0;

  Future<MontyRuntime> call(
    ResourceLimits limits,
    Map<String, Object?> externalModules,
  ) async =>
      throw UnsupportedError('Monty runtimes require the native test runner.');

  Future<void> close() async {}
}

/// Pumps frames while waiting for a browser-side test condition.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(end)) {
    // Real async work (preference reads) needs the real zone, as on the VM.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (!done()) fail('Timed out waiting for browser test condition');
}

/// Pumps frames for a fixed period.
Future<void> settleFor(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 600),
]) async {
  await tester.pump(duration);
}
