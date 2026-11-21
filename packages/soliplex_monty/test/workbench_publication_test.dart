import 'dart:async';
import 'dart:convert';

import 'package:dart_monty/dart_monty.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/workbench_activity_events.dart';
import 'support/lab_surface.dart';
import 'support/monty.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('server Python publication validates and stays inert on replay', (
    tester,
  ) async {
    var starts = 0;
    final controller = LabSurfaceController(
      startRuntime: (_, _) {
        starts++;
        throw StateError('Replay must not start a runtime');
      },
    );
    addTearDown(controller.dispose);
    final events = jsonDecode(publishedProgramEventsJson) as List;
    final program = events.cast<Map<String, dynamic>>().singleWhere((event) {
      final content = event['content'] as Map;
      final registration = content['workbenchPublication'] as Map;
      return registration['role'] == 'program';
    });
    final operations = ((program['content'] as Map)['a2ui_operations'] as List)
        .map((op) => Map<String, Object?>.from(op as Map))
        .toList();
    controller.apply(operations);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LabSurfaceView(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.error, isNull);
    expect(starts, 0);
    expect(find.text('Run'), findsOneWidget);
    expect(controller.surfaces.single.dataModel.get('/source'), 'print(1)');
    final update = operations.last['updateComponents']! as Map;
    final root = (update['components'] as List).first as Map;
    expect(root['outputPath'], '/output');
    expect(root.containsKey('output'), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('published REPL sends bounded run-result data only after Run', (
    tester,
  ) async {
    var starts = 0;
    final actions = <Map<String, Object?>>[];
    final controller = LabSurfaceController(
      startRuntime: (_, _) async {
        starts++;
        return _Runtime();
      },
      onActionPayload: actions.add,
    );
    addTearDown(controller.dispose);
    final events = (jsonDecode(publishedProgramEventsJson) as List)
        .cast<Map<String, dynamic>>();
    final program = events.singleWhere(
      (event) =>
          ((event['content'] as Map)['workbenchPublication'] as Map)['role'] ==
          'program',
    );
    controller.apply(
      ((program['content'] as Map)['a2ui_operations'] as List)
          .map((op) => Map<String, Object?>.from(op as Map))
          .toList(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LabSurfaceView(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(starts, 0);
    expect(actions, isEmpty);
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('python-repl-run'))),
    );
    await pumpUntil(tester, () => actions.isNotEmpty);
    expect(starts, 1);
    final action = actions.single;
    expect(action['name'], 'workbench.program.run_result');
    expect(action['sourceComponentId'], 'root');
    final context = action['context']! as Map;
    expect(
      context.keys,
      unorderedEquals([
        'side',
        'engine',
        'invocationId',
        'chainId',
        'outcome',
        'output',
      ]),
    );
    expect(context['side'], 'client');
    expect(context['engine'], 'monty-1.3.0');
    expect(context['invocationId'], isA<String>());
    expect(context['chainId'], isA<String>());
    expect(context['outcome'], 'success');
    expect((context['output']! as String).trim(), '1');
    await tester.pumpAndSettle();
    expect(actions, hasLength(1));
    expect(starts, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

// The widget owns execution; this deterministic runtime exercises its result
// binding and emitted action without requiring a native Monty worker.
class _Runtime implements MontyRuntime {
  @override
  ExecutionHandle execute(
    String code, {
    OsHandler? os,
    Map<String, Object?>? inputs,
  }) => ExecutionHandle(
    events: const Stream.empty(),
    result: Future.value(const MontyInt(1)),
    executionId: 'execution-1',
    cancel: () async {},
  );

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
