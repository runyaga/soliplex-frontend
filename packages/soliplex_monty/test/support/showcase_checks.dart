import 'dart:convert';
import 'dart:io';
import 'package:dart_monty/dart_monty.dart';
import 'package:soliplex_monty/src/chart_module.dart';
import 'package:soliplex_monty/src/program_type_check.dart';
import 'package:soliplex_monty/src/python_ui.dart';

const showcaseNames = [
  'survey_results',
  'notes',
  'todo',
  'sales_pipeline',
  'hot_patch',
  'reproducer',
  'healing_pipeline',
  'monty_gui',
  'syntax_error',
  'name_error',
  'type_check',
];

Directory get repositoryRoot {
  var root = Directory.current.absolute;
  while (!Directory('${root.path}/workbench/backend').existsSync()) {
    if (root.parent.path == root.path) throw StateError('Repository not found');
    root = root.parent;
  }
  return root;
}

String demoSource(String name) => File(
  '${repositoryRoot.path}/workbench/backend/'
  'soliplex_a2ui_workbench/src/soliplex_a2ui_workbench/${name}_demo.py'
  '${name == 'syntax_error' ? '.txt' : ''}',
).readAsStringSync();

String get nativeWorker {
  final configured = Platform.environment['MONTY_WORKER'];
  if (configured != null) return configured;
  final config = File('.dart_tool/package_config.json');
  final packages =
      (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
  final monty = packages.cast<Map<String, dynamic>>().singleWhere(
    (p) => p['name'] == 'dart_monty',
  );
  return Directory.fromUri(
    config.absolute.uri.resolve(monty['rootUri'] as String),
  ).uri.resolve('lib/src/bin/macos-arm64/dart_monty_worker').toFilePath();
}

// These checks read like assertions.
// ignore: avoid_positional_boolean_parameters
void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> checkShowcase(String name) async {
  var source = demoSource(name);
  if (name == 'syntax_error') source = '$source)';
  if (name == 'name_error') source = source.replaceFirst('prnt(', 'print(');
  if (name == 'type_check') {
    source = source.replaceFirst('return value + "1"', 'return value + 1');
  }

  const limits = ResourceLimits(
    maxMemory: 32 * 1024 * 1024,
    maxFeedDuration: Duration(seconds: 5),
    maxSuspensions: 1000000,
  );
  Future<String?> check(String code) =>
      checkProgramTypes(code, limits, workerLocation: nativeWorker);
  if (name == 'healing_pipeline') {
    require(
      (await check(source))?.contains('unsupported-operator') ?? false,
      'Missing type failure',
    );
    source = source.replaceFirst('return value + "0"', 'return value + 0');
  }
  final diagnostic = await check(source);
  require(diagnostic == null, '$name failed type check: $diagnostic');
  final files = <String, String>{};
  var arena = PythonUiArena(
    workbenchEnabled: true,
    readFile: (name) async => files[name] ?? '',
    writeFile: (name, text) async {
      files[name] = text;
    },
  );
  void freshArena() {
    arena = PythonUiArena(
      workbenchEnabled: true,
      readFile: (name) async => files[name] ?? '',
      writeFile: (name, text) async {
        files[name] = text;
      },
    );
  }

  final pool = await Monty.start(maxProcesses: 2, workerLocation: nativeWorker);
  final runtime = await MontyRuntime.start(
    pool: pool,
    limits: limits,
    externalModules: {
      'ui': PythonUiArena.moduleFor(() => arena),
      'chart': chartModule(),
    },
  );
  Future<void> execute(String code, {Map<String, Object?>? inputs}) async {
    final handle = runtime.execute(code, inputs: inputs);
    final sub = handle.events.listen((_) {});
    try {
      await handle.result;
    } finally {
      await sub.cancel();
    }
  }

  Map<String, dynamic> state() =>
      Map<String, dynamic>.from(arena.staged!.dataModel! as Map);
  Future<void> event(
    String event, [
    Map<String, Object?> context = const {},
    Map<String, Object?>? data,
  ]) async {
    final previous = data ?? state();
    freshArena();
    await execute(
      'handle_event(EVENT["name"], EVENT["context"])',
      inputs: {
        'EVENT': {'name': event, 'context': context},
        'DATA': previous,
      },
    );
    require(arena.staged != null, '$name did not redraw after $event');
  }

  try {
    if (name == 'healing_pipeline') {
      var failed = false;
      try {
        await execute(source);
      } on Object catch (e) {
        failed = e.toString().contains('ValueError');
      }
      require(failed && files.isEmpty, 'Stage 2 must fail before writing');
      source = source.replaceFirst(
        'amount = int(row["total"])',
        'amount = int(row["total"]) if row["total"].isdigit() else 0',
      );
      require(await check(source) == null, 'Final repair failed type check');
      freshArena();
    }
    await execute(source);
    if (['syntax_error', 'name_error', 'type_check'].contains(name)) return;
    require(arena.staged != null, '$name did not publish UI');
    switch (name) {
      case 'survey_results':
        require(state()['rows'] == 0, 'Empty survey must be valid');
        files['team-survey.csv'] =
            'submitted_at,submission_id,name,color\n'
            'now,1,Casey,Blue\nnow,2,Alex,Red\n';
        await event('refresh');
        require(
          (state()['counts'] as Map)['Blue'] == 1,
          'Refresh must reread CSV',
        );
        await event('select', {'label': 'Blue'});
        require(
          (state()['respondents'] as List).single == 'Casey',
          'Selection lost respondents',
        );
      case 'notes':
        await event('save', {}, {
          ...state(),
          'text': 'Keep these notes\nsecond line',
        });
        require(
          files['notes.md'] == 'Keep these notes\nsecond line',
          'Notes did not save',
        );
        freshArena();
        await execute(source);
        require(state()['text'] == files['notes.md'], 'Notes did not reload');
      case 'todo':
        await event('add', {}, {...state(), 'new': 'Buy tea'});
        await event('add', {}, {...state(), 'new': 'Call Sam'});
        await event('done', {'index': 0});
        require(
          ((state()['items'] as List).first as Map)['done'] == true,
          'Done state missing',
        );
        await event('remove', {'index': 0});
        require(
          files['todo.json']!.contains('Call Sam') &&
              !files['todo.json']!.contains('Buy tea'),
          'Task file mismatch',
        );
      case 'sales_pipeline':
        await event('generate', {}, {...state(), 'rows': '3'});
        require(
          files['sales.csv'] == 'month,total\nJan,10\nFeb,20\nMar,30\n',
          'Pipeline CSV mismatch',
        );
        await event('generate', {}, {...state(), 'rows': '99'});
        require(
          state()['notice'].toString().contains('1 to 12'),
          'Rows should be bounded',
        );
      case 'hot_patch':
        await event('normal');
        await event('burst');
        var failed = false;
        try {
          await event('export');
        } on Object catch (e) {
          failed = e.toString().contains('ZeroDivisionError');
        }
        require(failed && files.isEmpty, 'Export must fail before saving');
        source = source.replaceFirst(
          'sum(samples) / 0',
          'sum(samples) / len(samples)',
        );
        require(await check(source) == null, 'Hot patch failed type check');
        freshArena();
        await execute(source);
        require(
          (state()['samples'] as List).length == 4 &&
              state()['breached'] == true,
          'Repair lost samples',
        );
        require(
          files['traffic-report.txt']!.contains('peak: 140'),
          'Pending export was not retried',
        );
      case 'reproducer':
        await event('select', {'label': 'C'});
        await event('spawn');
        final opened = arena.workbench.actions.single;
        require(
          opened['op'] == 'open' && opened['kind'] == 'python',
          'Child must be inert source',
        );
        final child = opened['content']! as String;
        require(await check(child) == null, 'Reproducer failed type check');
        final childRuntime = await MontyRuntime.start(
          pool: pool,
          limits: limits,
        );
        try {
          final handle = childRuntime.execute(child);
          final subscription = handle.events.listen((_) {});
          try {
            await handle.result;
          } finally {
            await subscription.cancel();
          }
        } finally {
          await childRuntime.dispose();
        }
        require(
          (state()['rows'] as List).length == 4,
          'Child must not alter the parent session',
        );
        await event('spawn');
        require(
          arena.workbench.actions.single['op'] == 'update',
          'Repeated spawn must reuse child',
        );
        freshArena();
        await execute(source);
        require(
          arena.workbench.actions.single['op'] == 'close',
          'Run should close the previous child',
        );
        await event('select', {'label': 'C'});
        await event('spawn');
        require(
          arena.workbench.actions.single['op'] == 'update' &&
              arena.workbench.actions.single['window_id'] ==
                  opened['window_id'],
          'Run must retain the child identity',
        );
      case 'healing_pipeline':
        require(
          files['clean.csv'] == 'month,total\nJan,10\nMar,30\n',
          'Clean CSV mismatch',
        );
        require(
          state()['dropped'] == 1 && state()['total'] == 40,
          'Wrong cleaning state',
        );
      case 'monty_gui':
        require(arena.workbench.actions.isEmpty, 'Log must start closed');
        await event('open_log');
        final window = arena.workbench.actions.first['window_id'];
        await event('close_log');
        await event('open_log');
        require(
          arena.workbench.actions.first['op'] == 'update' &&
              arena.workbench.actions.first['window_id'] == window,
          'Log must reuse its stable window',
        );
    }
  } finally {
    await runtime.dispose();
    await pool.close();
  }
}
