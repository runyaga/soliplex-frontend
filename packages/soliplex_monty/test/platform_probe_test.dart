@TestOn('vm')
library;

import 'dart:convert';

import 'package:dart_monty/dart_monty.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_monty/soliplex_monty.dart';
import 'package:soliplex_monty/src/program_type_check.dart';
import 'package:soliplex_monty/src/python_workbench.dart';

import 'python_repl_test.dart' as repl;
import 'support/monty.dart';
import 'support/showcase_checks.dart' show demoSource;

void main() {
  test('fast probe gestures run in real Monty and persist receipts', () async {
    final source = demoSource('platform_probe');
    expect(utf8.encode(source).length, lessThan(1000000));
    const defaults = ReplLimits();
    final limits = ResourceLimits(
      maxMemory: defaults.maxMemory,
      maxFeedDuration: defaults.maxFeedDuration,
      maxSuspensions: defaults.maxSuspensions,
    );
    expect(
      await checkProgramTypes(source, limits, workerLocation: montyWorker),
      isNull,
    );
    final files = <String, String>{};
    PythonUiArena arena() => PythonUiArena(
      workbenchEnabled: true,
      readFile: (name) async {
        if (!files.containsKey(name)) throw StateError('Missing file');
        return files[name]!;
      },
      writeFile: (name, text) async => files[name] = text,
    );
    var current = arena();
    final starter = MontyStarter();
    final runtime = await starter.call(limits, {
      'ui': PythonUiArena.moduleFor(() => current),
    });
    Future<void> execute(String code, [Map<String, Object?>? inputs]) async {
      final handle = runtime.execute(code, inputs: inputs);
      final subscription = handle.events.listen((_) {});
      try {
        await handle.result;
      } finally {
        await subscription.cancel();
      }
    }

    Map<String, dynamic> book() =>
        jsonDecode(files['probe-results.json']!) as Map<String, dynamic>;
    Map<String, dynamic> last() =>
        (book()['results'] as List).last as Map<String, dynamic>;
    Object? statusText() => current.staged!.components[1]['text'];
    Future<void> event(String name, [Map<String, Object?>? state]) async {
      final data = state ?? current.staged?.dataModel ?? {};
      current = arena();
      await execute('handle_event(EVENT["name"], EVENT["context"])', {
        'EVENT': {'name': name, 'context': <String, Object?>{}},
        'DATA': data,
      });
    }

    try {
      await execute(source);
      expect(book()['results'], isEmpty); // Run never starts a probe.
      expect(current.staged, isNotNull);
      expect(statusText(), 'Probe ready');
      await event('events');
      expect(last()['count'], 1);
      final eventMessage = last()['message'];
      expect(statusText(), eventMessage);
      final eventId = last()['id'];
      await event('receipt', {
        'receipt': jsonEncode({
          'id': eventId,
          'wall_ms': 12.25,
          'status': 'harness_error',
          'error': 'visibility failed',
        }),
      });
      expect(last()['wall_ms'], 12.25);
      expect(last()['status'], 'completed');
      expect(last().containsKey('error'), isFalse);
      expect(
        (last()['observation'] as Map<String, dynamic>)['status'],
        'harness_error',
      );
      expect(statusText(), eventMessage);
      await event('compute');
      expect(last()['size'], 10000);
      expect(last()['status'], 'completed');
      expect(last()['checksum'], isA<int>());
      expect(statusText(), last()['message']);
      for (final size in [50, 20000]) {
        await event('redraw');
        expect(current.staged!.components, hasLength(size));
        expect(last()['status'], 'completed');
        expect(statusText(), last()['message']);
      }
      await event('redraw');
      expect(last()['status'], 'error');
      expect(last()['error'], 'Too many components in one run.');
      await event('charts');
      expect(statusText(), last()['message']);
      final chart = current.staged!.components.singleWhere(
        (node) => node['component'] == 'Chart',
      );
      expect((chart['spec']! as Map)['points'] as List, hasLength(8));
      for (final size in [1024, PythonWorkbench.maxFileBytes]) {
        await event('files');
        expect(last()['matches'], true);
        expect(last()['read_bytes'], size);
      }
      await event('files');
      expect(last()['status'], 'error');
      expect(last()['error'], contains('Thread file request failed'));
      expect(files['probe-payload.txt']!.length, PythonWorkbench.maxFileBytes);
      await event('state');
      expect(last()['field_bytes'], 1024);
      expect(last()['data_bytes'], greaterThan(1024));
      await event('types');
      final child = current.workbench.actions.single['content']! as String;
      expect(utf8.encode(child), hasLength(1000000));
      expect(
        await checkProgramTypes(child, limits, workerLocation: montyWorker),
        isNull,
      );
      // Restoring the source after a cancelled VM keeps measured attempts.
      current = arena();
      await execute(source);
      expect(book()['results'], isNotEmpty);
      expect(current.staged, isNotNull);
    } finally {
      await starter.close();
    }
  }, skip: skipWithoutMonty != false);

  testWidgets('a checked Run shows checker duration and preserves stdout', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final starter = MontyStarter();
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(
          body: PythonReplView(
            source: 'print("timing stdout")',
            typeCheck: true,
            limits: const ReplLimits(),
            startRuntime: starter.call,
            checkTypes: (source, limits) => checkProgramTypes(
              source,
              limits,
              workerLocation: montyWorker,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Type check:'), findsNothing);
    await repl.tapRun(tester);
    await tester.pump();
    await repl.waitFor(tester, () => repl.idle(tester));
    expect(find.text('timing stdout'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'^Type check: \d+(\.\d+)? ms\.$')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(starter.close);
  }, skip: skipWithoutMonty != false);
}
