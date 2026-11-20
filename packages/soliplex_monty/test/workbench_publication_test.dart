import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/workbench_activity_events.dart';
import 'support/lab_surface.dart';

void main() {
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
}
