import 'package:dart_monty/core.dart';

import 'package:soliplex_monty/src/chart_module.dart';
import 'package:soliplex_monty/src/python_ui.dart';
import 'package:soliplex_monty/src/ui_chart.dart';
import 'package:soliplex_monty/src/worker_location.dart';

/// Checks a whole program on a fresh worker without running any user statement.
///
/// The leading external call suspends immediately after the worker's check.
/// Closing that snapshot without resuming prevents prints, host calls and OS
/// access. The execution runtime and its retained globals are left untouched.
Future<String?> checkProgramTypes(
  String source,
  ResourceLimits limits, {
  String? workerLocation,
}) =>
    Monty.withPool<String?>(
      (pool) => pool.withSession(
        (session) async {
          var snapshot = await session.feedStart(
            'soliplex_check_ready()\n$source',
          );
          // Resolve import declarations before the checker can finish.
          // Never resume an executable call.
          while (snapshot is FunctionSnapshot &&
              snapshot.isOsFunction &&
              snapshot.functionName == 'import_stubs') {
            snapshot = await snapshot.resumeAuto();
          }
          final ready = switch (snapshot) {
            FunctionSnapshot(:final functionName) =>
              functionName == 'soliplex_check_ready',
            NameLookupSnapshot(:final variableName) =>
              variableName == 'soliplex_check_ready',
            _ => false,
          };
          if (!ready) {
            throw StateError('Type check did not reach its execution barrier.');
          }
          return null;
        },
        limits: limits,
        typeCheck: true,
        typeCheckFormat: 'concise',
        scriptName: 'program.py',
        typeCheckStubs: '''
from typing import Any
CLIENT: dict[str, Any]
DATA: dict[str, Any]
EVENT: dict[str, Any]
def soliplex_check_ready() -> None: ...
def handle_event(name: str, context: dict[str, Any]) -> None: ...
''',
        externalModules: _modules(),
      ),
      maxProcesses: 1,
      checkoutTimeout: const Duration(seconds: 30),
      workerLocation: workerLocation ?? montyWorkerBase(),
    ).onError<MontyTypingError>(
      (error, _) => error.display().replaceAllMapped(
        RegExp(r'program\.py:(\d+):'),
        (match) => 'program.py:${int.parse(match[1]!) - 1}:',
      ),
    );

Map<String, Object?> _modules() {
  final arena = PythonUiArena(workbenchEnabled: true);
  final ui = PythonUiArena.moduleFor(() => arena);
  final constructors = {...basicSignatures, ...uiChartSignatures};
  final stubs = StringBuffer(
    'from typing import Any\nfrom . import workbench, graphics\n',
  );
  // Constructors accept heterogeneous property/binding values; validation of
  // the constructed component remains with the catalog.
  for (final name in constructors.keys) {
    stubs.writeln('def $name(*args: Any, **kwargs: Any) -> str: ...');
  }
  stubs.write('''
def bind(path: str) -> Any: ...
def Event(name: str, context: dict[str, Any] = {}) -> str: ...
def show(root: str, data: Any = None) -> None: ...
''');
  final chart = chartModule();
  return {
    'ui': ExternalModule({
      ...ui.attrs,
      'workbench': ExternalModule(
        (ui.attrs['workbench']! as ExternalModule).attrs,
        stubs: '''
def read_file(filename: str) -> str: ...
def write_file(filename: str, text: str) -> None: ...
def open_window(title: str, kind: str, content: str) -> str: ...
def update_window(window_id: str, content: str) -> None: ...
def move_window(window_id: str, order: int = 0) -> None: ...
def close_window(window_id: str) -> None: ...
''',
      ),
      'graphics': ExternalModule(
        (ui.attrs['graphics']! as ExternalModule).attrs,
        stubs:
            'from typing import Any\n'
            'def Chart(*args: Any, **kwargs: Any) -> str: ...',
      ),
    }, stubs: stubs.toString()),
    'chart': ExternalModule(
      chart.attrs,
      stubs:
          'from typing import Any\n'
          '${chart.attrs.keys.map((name) => 'def $name(*args: Any, '
              '**kwargs: Any) -> dict[str, Any]: ...').join('\n')}',
    ),
  };
}
