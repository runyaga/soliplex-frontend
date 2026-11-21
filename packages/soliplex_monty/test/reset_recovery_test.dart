import 'dart:async';

import 'package:dart_monty/dart_monty.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

import 'python_repl_test.dart' as repl;
import 'support/monty.dart';

String _program(String failure, {bool initData = true}) =>
    '''
import ui
state = 0
def handle_event(name, context):
    global state
    if name == "reset":
        $failure
    state += 1
    print("handled", state, DATA.get("value"))
    ui.show(ui.Text("Recovered"))
ui.show(ui.Text("Ready")${initData ? ', data={"value": "kept"}' : ''})
''';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (name, failure, limits) in [
    (
      'TimeoutError',
      'raise TimeoutError("event timed out")',
      const ReplLimits(),
    ),
    (
      'MemoryError',
      'raise MemoryError("event exhausted memory")',
      const ReplLimits(),
    ),
    (
      'feed limit',
      'while True: pass',
      const ReplLimits(maxFeedDuration: Duration(milliseconds: 100)),
    ),
    (
      'deadline',
      'while True: pass',
      const ReplLimits(deadline: Duration(milliseconds: 500)),
    ),
  ]) {
    testWidgets('$name reloads current source before the next event', (
      tester,
    ) async {
      final host = _Host(tester, limits);
      await host.mount(_program(failure));
      await host.run();
      final view = host.apps.view('program');
      await host.event('reset');
      expect(
        find.textContaining('Interpreter state was reset.'),
        findsOneWidget,
      );
      expect(host.apps.view('program'), same(view));
      expect(find.text('Ready'), findsOneWidget);
      // Recovery uses edited source; init without data keeps the visible model.
      await repl.typeSource(
        tester,
        '${_program(failure, initData: false)}\nprint("edited init")',
      );
      await host.event('ok');
      expect(find.textContaining('edited init'), findsOneWidget);
      expect(find.textContaining('handled 1 kept'), findsOneWidget);
      expect(find.text('Recovered'), findsOneWidget);
      expect(host.apps.snapshot()['program'], {'value': 'kept'});
      expect(
        find.textContaining('App state was reset; the program was reloaded.'),
        findsOneWidget,
      );
      await host.event('ok');
      expect(find.textContaining('handled 2 kept'), findsOneWidget);
      expect(find.textContaining('App state was reset;'), findsNothing);
      expect(host.starter.starts, 1);
      expect(tester.takeException(), isNull);
      await host.close();
    }, skip: skipWithoutMonty != false);
  }

  testWidgets(
    'failed recovery keeps the app and retries loading on the next event',
    (tester) async {
      final host = _Host(tester, const ReplLimits());
      await host.mount(_program('raise TimeoutError("reset")'));
      await host.run();
      final view = host.apps.view('program');
      await host.event('reset');
      await repl.typeSource(
        tester,
        'import ui\nui.show(ui.Text("Uncommitted"))\n1 / 0',
      );
      await host.event('ok');
      expect(find.textContaining('ZeroDivisionError'), findsOneWidget);
      expect(host.apps.view('program'), same(view));
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Uncommitted'), findsNothing);
      expect(host.apps.snapshot()['program'], {'value': 'kept'});
      await repl.typeSource(tester, _program('pass', initData: false));
      await host.event('ok');
      expect(find.textContaining('handled 1 kept'), findsOneWidget);
      await host.close();
    },
    skip: skipWithoutMonty != false,
  );

  testWidgets('a failing Run leaves the published app visible', (tester) async {
    final host = _Host(tester, const ReplLimits());
    await host.mount(_program('pass'));
    await host.run();
    final view = host.apps.view('program');
    await repl.typeSource(
      tester,
      'import ui\nui.show(ui.Text("Uncommitted"))\n1 / 0',
    );
    await host.run();
    expect(find.textContaining('ZeroDivisionError'), findsOneWidget);
    expect(host.apps.view('program'), same(view));
    expect(find.text('Ready'), findsOneWidget);
    expect(host.apps.snapshot()['program'], {'value': 'kept'});
    expect(find.text('Uncommitted'), findsNothing);
    await host.close();
  }, skip: skipWithoutMonty != false);

  testWidgets('a pending or refused interpreter reset keeps the app visible', (
    tester,
  ) async {
    late _ResetRuntime runtime;
    final host = _Host(
      tester,
      const ReplLimits(),
      wrapRuntime: (delegate) => runtime = _ResetRuntime(delegate),
    );
    await host.mount(_program('pass'));
    await host.run();
    final view = host.apps.view('program');
    final gate = Completer<void>();
    runtime.beforeClear = () => gate.future;
    Future<void>? pending;
    await tester.runAsync(() async {
      pending = host.apps.controls('program')!.run();
    });
    await tester.pump();
    expect(host.apps.view('program'), same(view));
    expect(find.text('Ready'), findsOneWidget);
    await tester.runAsync(() async {
      gate.completeError(StateError('reset refused'));
      await pending;
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Python failed to reset:'), findsOneWidget);
    expect(host.apps.view('program'), same(view));
    expect(host.apps.snapshot()['program'], {'value': 'kept'});
    runtime.beforeClear = null;
    await host.close();
  }, skip: skipWithoutMonty != false);
}

class _Host {
  _Host(this.tester, this.limits, {this.wrapRuntime});
  final WidgetTester tester;
  final ReplLimits limits;
  final MontyRuntime Function(MontyRuntime)? wrapRuntime;
  final starter = MontyStarter();
  final apps = ProgramApps();

  Future<void> mount(String source) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(
          body: ProgramAppScope(
            apps: apps,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  PythonReplView(
                    source: source,
                    surfaceId: 'program',
                    mode: ReplMode.run,
                    limits: limits,
                    startRuntime: (limits, modules) async {
                      final runtime = await starter.call(limits, modules);
                      return wrapRuntime?.call(runtime) ?? runtime;
                    },
                    onWorkbench: () async {},
                  ),
                  ProgramAppView(program: 'program', apps: apps),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> run() async {
    await tester.runAsync(() => apps.controls('program')!.run());
    await tester.pumpAndSettle();
  }

  Future<void> event(String name) async {
    await tester.runAsync(() => apps.controls('program')!.event(name));
    await tester.pumpAndSettle();
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    apps.dispose();
    await tester.runAsync(starter.close);
  }
}

// Control reset completion without changing how the real worker executes code.
class _ResetRuntime implements MontyRuntime {
  _ResetRuntime(this.delegate);
  final MontyRuntime delegate;
  Future<void> Function()? beforeClear;

  @override
  Future<void> clearState() async {
    await beforeClear?.call();
    await delegate.clearState();
  }

  @override
  ExecutionHandle execute(
    String code, {
    OsHandler? os,
    Map<String, Object?>? inputs,
  }) => delegate.execute(code, os: os, inputs: inputs);

  @override
  Future<void> dispose() => delegate.dispose();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
