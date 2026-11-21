// Reads repository fixtures with dart:io and checks them with a native worker.
@TestOn('vm')
library;

import 'dart:io';

import 'package:dart_monty/dart_monty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_monty/soliplex_monty.dart' show ReplLimits;
import 'package:soliplex_monty/src/program_type_check.dart';

import 'support/monty.dart';

String source(String name) {
  var root = Directory.current.absolute;
  while (!Directory('${root.path}/workbench/backend').existsSync()) {
    root = root.parent;
  }
  return File(
    '${root.path}/workbench/backend/soliplex_a2ui_workbench/'
    'src/soliplex_a2ui_workbench/$name',
  ).readAsStringSync();
}

void main() {
  test(
    'stubs accept GUI demo and tally; checker refuses annotated error',
    () async {
      const defaults = ReplLimits();
      final limits = ResourceLimits(
        maxMemory: defaults.maxMemory,
        maxFeedDuration: defaults.maxFeedDuration,
      );
      Future<String?> check(String code) =>
          checkProgramTypes(code, limits, workerLocation: montyWorker);
      expect(await check(source('monty_gui_demo.py')), isNull);
      expect(
        await check('''
import ui
count = 0

def draw():
    ui.show(ui.Column([ui.Text(f"Count: {count}"),
        ui.Button(ui.Text("+1"), action=ui.Event("plus", {})),
        ui.Button(ui.Text("-1"), action=ui.Event("minus", {})),
        ui.Button(ui.Text("Reset"), action=ui.Event("reset", {}))]))

def handle_event(name, context):
    global count
    if name == "plus":
        count += 1
    elif name == "minus":
        count -= 1
    else:
        count = 0
    draw()

draw()
'''),
        isNull,
      );
      final error = await check(source('type_check_demo.py'));
      expect(error, contains('unsupported-operator'));
      expect(
        await check('print("must not run")\nraise ValueError("must not run")'),
        isNull,
      );
    },
    skip: skipWithoutMonty,
  );
}
