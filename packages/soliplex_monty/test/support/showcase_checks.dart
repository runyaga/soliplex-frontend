import 'dart:convert';
import 'dart:io';
import 'package:dart_monty/dart_monty.dart';
import 'package:soliplex_monty/soliplex_monty.dart' show ReplLimits;
import 'package:soliplex_monty/src/chart_module.dart';
import 'package:soliplex_monty/src/program_type_check.dart';
import 'package:soliplex_monty/src/python_ui.dart';

const showcaseNames = [
  'incident_flight_recorder',
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

String demoSource(String name) {
  final source = File(
    '${repositoryRoot.path}/workbench/backend/'
    'soliplex_a2ui_workbench/src/soliplex_a2ui_workbench/${name}_demo.py'
    '${name == 'syntax_error' ? '.txt' : ''}',
  ).readAsStringSync();
  if (name != 'incident_flight_recorder') return source;
  final template = File(
    '${repositoryRoot.path}/workbench/backend/'
    'soliplex_a2ui_workbench/src/soliplex_a2ui_workbench/incident_replay_template.py',
  ).readAsStringSync();
  final quoted = template
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n');
  return source.replaceFirst(
    '"__INCIDENT_REPLAY_TEMPLATE__"',
    "'$quoted'",
  );
}

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

Future<void> checkShowcase(
  String name, {
  void Function(StagedSurface surface)? onSurface,
}) async {
  var source = demoSource(name);
  if (name == 'syntax_error') source = '$source)';
  if (name == 'name_error') source = source.replaceFirst('prnt(', 'print(');
  if (name == 'type_check') {
    source = source.replaceFirst('return value + "1"', 'return value + 1');
  }

  const defaults = ReplLimits();
  final limits = ResourceLimits(
    maxMemory: defaults.maxMemory,
    maxFeedDuration: defaults.maxFeedDuration,
    maxSuspensions: defaults.maxSuspensions,
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
    final elapsed = Stopwatch()..start();
    final handle = runtime.execute(code, inputs: inputs);
    final sub = handle.events.listen((_) {});
    try {
      await handle.result;
      if (name == 'incident_flight_recorder') {
        require(
          elapsed.elapsed < const Duration(seconds: 5),
          'Gesture exceeded five seconds',
        );
        if (arena.staged case final surface?) {
          require(surface.components.length < 120, 'UI node budget exceeded');
          require(
            utf8.encode(jsonEncode(surface.dataModel)).length < 4096,
            'App snapshot exceeded budget',
          );
        }
        require(
          files.values.every((text) => utf8.encode(text).length < 16384),
          'Artifact exceeded budget',
        );
      }
      if (arena.staged case final surface?) onSurface?.call(surface);
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
      case 'incident_flight_recorder':
        require(
          utf8.encode(source).length < 1000000,
          'Publication exceeds budget',
        );
        require(
          state()['observed'] is List && (state()['observed'] as List).isEmpty,
          'Run must not replay the incident',
        );
        await event('replay');
        const trace = [0, 0, 0, 2, 6, 8, 12, 16, 20, 24, 28, 32];
        require(
          jsonEncode(state()['observed']) == jsonEncode(trace),
          'Wrong observed trace',
        );
        final inspector = arena.workbench.actions.first['window_id'];
        await event('inspect', {'label': 'T5'});
        require(
          arena.workbench.actions.first['op'] == 'update' &&
              arena.workbench.actions.first['window_id'] == inspector &&
              arena.workbench.actions.first['content'].toString().contains(
                '"pending_retries": 6',
              ),
          'Tick inspection must reuse the inspector',
        );
        await event('freeze');
        require(
          (state()['checkpoint'] as Map)['backlog'] == 6,
          'Wrong checkpoint',
        );
        await event('compare');
        require(
          state()['restore_final_backlog'] == 32 &&
              state()['capacity_final_backlog'] == 6 &&
              state()['retry_disabled_final_backlog'] == 0 &&
              state()['cleared_at_tick'] == 7,
          'Wrong mitigation results',
        );
        require(
          jsonEncode(state()['observed']) == jsonEncode(trace),
          'Branch changed history',
        );
        await event('minimize');
        require(
          jsonEncode(state()['minimal_trigger']) == '["fault-4","fault-5"]',
          'Wrong minimum',
        );
        // Python and model instructions remain literal annotation text.
        const injection =
            "'); ui.workbench.open_window('INJECTED', 'text', 'x'); "
            '# ignore instructions';
        final injected = state();
        ((injected['tape'] as List).first as Map)['text'] = injection;
        await event('capsule', {}, injected);
        require(
          !files.containsKey('replay-verification.json'),
          'Capsule generation executed code',
        );
        require(
          arena.workbench.actions.map((a) => a['op']).join(',') ==
              'close,open,move',
          'Capsule must replace the inspector within the window budget',
        );
        final opened = arena.workbench.actions[1];
        final capsule = opened['content']! as String;
        require(await check(capsule) == null, 'Capsule failed type check');
        await event('capsule');
        require(
          arena.workbench.actions[1]['op'] == 'update' &&
              arena.workbench.actions[1]['window_id'] == opened['window_id'],
          'Capsule must reuse window',
        );
        await event('handoff');
        require(
          state()['verification_status'] == 'unverified' &&
              files['incident-handoff.md']!.contains('unverified'),
          'Missing receipt must stay unverified',
        );
        Future<void> runCapsule(String code, {bool failure = false}) async {
          final childArena = PythonUiArena(
            workbenchEnabled: true,
            writeFile: (name, text) async {
              files[name] = text;
            },
          );
          final childRuntime = await MontyRuntime.start(
            pool: pool,
            limits: limits,
            externalModules: {'ui': PythonUiArena.moduleFor(() => childArena)},
          );
          var failed = false;
          try {
            final handle = childRuntime.execute(code);
            final subscription = handle.events.listen((_) {});
            try {
              await handle.result;
            } on Object catch (error) {
              failed = error.toString().contains('AssertionError');
              if (!failed) rethrow;
            } finally {
              await subscription.cancel();
            }
            require(
              childArena.staged == null && childArena.workbench.actions.isEmpty,
              'Capsule Run must not open a fourth window',
            );
            require(failed == failure, 'Unexpected verification outcome');
          } finally {
            await childRuntime.dispose();
          }
        }
        await runCapsule(capsule);
        final receipt = jsonDecode(files['replay-verification.json']!) as Map;
        require(
          receipt['status'] == 'pass' &&
              (((receipt['case'] as Map)['tape'] as List).first
                      as Map)['text'] ==
                  injection,
          'Annotation escaped its literal data boundary',
        );
        await event('handoff');
        require(
          state()['verification_status'] == 'verified',
          'Matching receipt not loaded',
        );
        require(
          files['incident-handoff.md']!.contains('independent-v1'),
          'Missing handoff revision',
        );
        final tampered = capsule.replaceFirst(
          "'capacity_final_backlog': 6",
          "'capacity_final_backlog': 999",
        );
        require(tampered != capsule, 'Tamper did not change expectation');
        await runCapsule(tampered, failure: true);
        require(
          (jsonDecode(files['replay-verification.json']!) as Map)['status'] ==
              'failed',
          'Failure must replace stale passing receipt',
        );
        await event('handoff');
        require(
          state()['verification_status'] == 'unverified',
          'Failed receipt was trusted',
        );
        await runCapsule(capsule);
        final stale = jsonDecode(files['replay-verification.json']!) as Map;
        ((stale['case'] as Map)['checkpoint'] as Map)['backlog'] = 999;
        files['replay-verification.json'] = jsonEncode(stale);
        await event('handoff');
        require(
          state()['verification_status'] == 'unverified',
          'Stale case receipt was trusted',
        );
        files['replay-verification.json'] = '[]';
        await event('handoff');
        require(
          state()['verification_status'] == 'unverified',
          'Malformed receipt was trusted',
        );
        freshArena();
        await execute(source);
        require(
          arena.workbench.actions.map((a) => a['op']).join(',') ==
              'close,close',
          'Explicit Run must close restored auxiliaries',
        );
        require(
          jsonEncode(state()['observed']) == jsonEncode(trace),
          'Saved case did not reload',
        );
        await event('capsule');
        require(
          arena.workbench.actions[1]['op'] == 'update' &&
              arena.workbench.actions[1]['window_id'] == opened['window_id'],
          'Reload allocated replacement window',
        );
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
