import 'dart:convert';
import 'dart:io';

import 'package:dart_monty/dart_monty.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Resolve through the package configuration, including from example/ tests.
final String montyWorker =
    Platform.environment['MONTY_WORKER'] ?? defaultMontyWorker();

/// Finds the worker relative to dart_monty's installed package location.
String defaultMontyWorker() {
  var directory = Directory.current.absolute;
  while (true) {
    final config = File('${directory.path}/.dart_tool/package_config.json');
    if (config.existsSync()) {
      final data =
          jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
      final packages = (data['packages'] as List).cast<Map<String, dynamic>>();
      final monty = packages
          .where((p) => p['name'] == 'dart_monty')
          .firstOrNull;
      if (monty != null) {
        final root = Directory.fromUri(
          config.uri.resolve(monty['rootUri'] as String),
        ).uri;
        return root
            .resolve('lib/src/bin/macos-arm64/dart_monty_worker')
            .toFilePath();
      }
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('No package configuration containing dart_monty');
    }
    directory = parent;
  }
}

/// Skip reason when no worker binary is present.
Object get skipWithoutMonty =>
    File(montyWorker).existsSync() ? false : 'No dart_monty worker';

/// Starts real runtimes after [delay] and records them for teardown.
class MontyStarter {
  MontyStarter({this.delay = Duration.zero});

  final Duration delay;
  final List<Monty> pools = [];
  final List<MontyRuntime> runtimes = [];
  int starts = 0;

  Future<MontyRuntime> call(
    ResourceLimits limits,
    Map<String, Object?> externalModules,
  ) async {
    starts++;
    await Future<void>.delayed(delay);
    final pool = await Monty.start(
      maxProcesses: 2,
      checkoutTimeout: const Duration(seconds: 30),
      workerLocation: montyWorker,
    );
    pools.add(pool);
    final runtime = await MontyRuntime.start(
      pool: pool,
      limits: limits,
      externalModules: externalModules,
    );
    runtimes.add(runtime);
    return runtime;
  }

  Future<void> close() async {
    for (final runtime in runtimes) {
      await runtime.dispose();
    }
    for (final pool in pools) {
      await pool.close();
    }
  }
}

/// Pumps in the real zone until [done], failing after [timeout].
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) {
      final texts = [
        for (final e in find.byType(SelectableText).evaluate())
          (e.widget as SelectableText).data,
        for (final e in find.byType(Text).evaluate()) (e.widget as Text).data,
      ].whereType<String>().where((t) => t.length > 2).take(30).join(' | ');
      fail('Timed out: $texts ${tester.takeException()}');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pump();
}

/// Pumps in the real zone for [duration], for checks that nothing happens.
Future<void> settleFor(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 600),
]) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}
