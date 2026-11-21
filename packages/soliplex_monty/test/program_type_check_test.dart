// Reads repository fixtures with dart:io and checks them with a native worker.
@TestOn('vm')
library;

import 'dart:io';

import 'package:dart_monty/dart_monty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_monty/soliplex_monty.dart' show ReplLimits;
import 'package:soliplex_monty/src/program_type_check.dart';

import 'support/monty.dart';
import 'support/showcase_checks.dart' show repositoryRoot;

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
  const limits = ResourceLimits(
    maxMemory: 256 * 1024 * 1024,
    maxFeedDuration: Duration(seconds: 30),
  );
  Future<String?> check(String code) =>
      checkProgramTypes(code, limits, workerLocation: montyWorker);

  test('strict stubs reject invalid host calls before execution', () async {
    for (final code in [
      'ui.Text("x", typo=True)',
      'ui.Text(42)',
      'ui.Text("x", variant="heading")',
      'ui.Text("x", weight=ui.bind("/weight"))',
      'ui.Button(ui.Text("x"))',
      'ui.Column("not children")',
      'ui.CheckBox("x", "not a bool")',
      'ui.bind(42)',
      'ui.Event("x", [])',
      'ui.show(ui.Text("x"), [])',
      'ui.workbench.read_file(42)',
      'ui.workbench.write_file("x.txt", 42)',
      'ui.workbench.open_window("x", "html", "x")',
      'ui.workbench.move_window("id", "first")',
      'ui.workbench.close_window("id", extra=1)',
      'chart.bar([{"id":"a", "label":"A", "value":"wrong"}])',
      'chart.gauge(2, 0, 100)',
      'chart.gauge(2, min_value=0)',
      'chart.line([], typo=True)',
      'ui.graphics.Chart(chart.bar([]), [], "x", height="tall")',
      'ui.graphics.Chart({"kind":"unknown"}, [], "x")',
    ]) {
      expect(
        await check('import ui\nimport ui.workbench\nimport chart\n$code'),
        isNotNull,
        reason: code,
      );
    }
    expect(
      await check('''
import ui
import chart
ui.show(ui.Column([
    ui.Text(ui.bind("/title")),
    ui.Slider(max=100, value=ui.bind("/value")),
    ui.ChoicePicker(options=["A", "B"], value=ui.bind("/choice")),
    ui.Button(ui.Text("Go"), action=ui.Event("go")),
    ui.graphics.Chart(chart.gauge(2, min_value=0, max_value=100), [], "Gauge"),
]))
'''),
      isNull,
    );
  }, skip: skipWithoutMonty);

  test(
    'every curated demo and walkthrough program passes strict type check',
    () async {
      final directory = Directory(
        '${repositoryRoot.path}/workbench/backend/'
        'soliplex_a2ui_workbench/src/soliplex_a2ui_workbench',
      );
      final demos = directory
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('_demo.py') || f.path.endsWith('_demo.py.txt'),
          )
          .toList();
      expect(demos.length, greaterThanOrEqualTo(13));
      for (final file in demos) {
        var code = file.readAsStringSync();
        // These four examples intentionally teach syntax/name/type repair.
        if (file.path.endsWith('/syntax_error_demo.py.txt')) {
          expect(await check(code), isNotNull);
          code = '$code)';
        } else if (file.path.endsWith('/name_error_demo.py')) {
          expect(await check(code), isNotNull);
          code = code.replaceFirst('prnt(', 'print(');
        } else if (file.path.endsWith('/type_check_demo.py')) {
          expect(await check(code), contains('unsupported-operator'));
          code = code.replaceFirst('return value + "1"', 'return value + 1');
        } else if (file.path.endsWith('/healing_pipeline_demo.py')) {
          expect(await check(code), contains('unsupported-operator'));
          code = code.replaceFirst('return value + "0"', 'return value + 0');
        }
        expect(await check(code), isNull, reason: file.path);
      }
      // The tour uses monty_gui_demo.py, covered above; include the room's
      // executable teaching program as well, using its actual source.
      final teaching = File(
        '${directory.path}/workbench_teaching.py',
      ).readAsStringSync();
      final demo = RegExp(
        r'DEMO = """([\s\S]*?)"""',
      ).firstMatch(teaching)!.group(1)!;
      expect(await check(demo), isNull);
    },
    skip: skipWithoutMonty,
    timeout: const Timeout(Duration(minutes: 3)),
  );

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
