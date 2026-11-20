import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_scope.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_view.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/workbench_host.dart';
import 'package:soliplex_monty/soliplex_monty.dart';
import 'package:soliplex_monty/src/program_type_check.dart';

import '../../test/support/monty.dart';

const _source = '''
import ui
count = 0
def draw():
    ui.show(ui.Column([
        ui.Text(f"Count: {count}"),
        ui.Button(ui.Text("+1"), action=ui.Event("plus", {})),
    ]))
def handle_event(name, context):
    global count
    count += 1
    print("event received", name)
    draw()
draw()
''';

void main() {
  for (final demo in [false, true]) {
    testWidgets(
      'real Monty app demo=$demo uses layout, session, reuse and closing',
      (
        tester,
      ) async {
        tester.view
          ..physicalSize = const Size(1600, 1000)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        final starter = MontyStarter();
        final actions = <Map<String, Object?>>[];
        var checks = 0;
        final fixture =
            jsonDecode(
                  File('test/fixtures/program_app.json').readAsStringSync(),
                )
                as Map<String, dynamic>;
        final messages = <String, GenUiMessage>{};
        final store = ChatSurfaceStore(
          catalogs: [
            labCatalog(
              startRuntime: starter.call,
              checkTypes: (source, limits) {
                checks++;
                return checkProgramTypes(
                  source,
                  limits,
                  workerLocation: montyWorker,
                );
              },
            ),
          ],
          onAction: (_, action) => actions.add(action),
        );
        void ingest(String phase) {
          for (final raw in fixture[phase] as List) {
            final event = Map<String, dynamic>.from(raw as Map);
            final content = event['content'] as Map;
            final operations =
                jsonDecode(jsonEncode(content['a2ui_operations'])) as List;
            for (final op in operations.cast<Map<String, dynamic>>()) {
              final components = op['updateComponents'];
              if (components is Map) {
                for (final component in components['components'] as List) {
                  if (component is Map &&
                      component['component'] == 'PythonRepl') {
                    component['typeCheck'] = true;
                  }
                }
              }
              final update = op['updateDataModel'];
              if (update is Map &&
                  update['value'] is Map &&
                  (update['value'] as Map)['source'] == '__SOURCE__') {
                (update['value'] as Map)['source'] = demo
                    ? File(
                        '../../../workbench/backend/soliplex_a2ui_workbench/'
                        'src/soliplex_a2ui_workbench/monty_gui_demo.py',
                      ).readAsStringSync()
                    : _source;
              }
            }
            messages[event['messageId'] as String] = GenUiMessage.create(
              id: event['messageId'] as String,
              widgetName: 'a2ui',
              data: {
                'messages': operations,
                'workbenchRegistration': content['workbenchPublication'],
              },
            );
          }
          store.ingest(messages.values);
        }

        Future<void> mount() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: soliplexLightTheme(),
              home: Scaffold(
                body: ChatSurfaceScope(
                  store: store,
                  child: const ClientWorkbenchPresentation().buildHost(
                    roomId: 'room',
                    threadId: 'thread',
                    chat: const Text('Chat'),
                    surfaceBuilder: (activity, surface) => ChatSurfaceView(
                      controller: store[activity]!,
                      surfaceId: surface,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        final run = find.byKey(const ValueKey('python-repl-run'));
        final programWindow = find.bySemanticsLabel(
          'Workbench window Monty GUI demo',
        );
        final appWindow = find.bySemanticsLabel(
          'Workbench window Monty GUI demo app',
        );
        final semantics = tester.ensureSemantics();
        ingest('initial');
        await mount();
        expect(starter.starts, 0);
        expect(checks, 0);
        expect(appWindow, findsNothing);
        Future<void> runProgram() async {
          final before = actions.length;
          await tester.runAsync(() => tester.tap(run));
          await pumpUntil(tester, () => actions.length > before);
          expect(actions.last['name'], 'workbench.program.layout');
          expect(((actions.last['context']! as Map)['actions'] as List).first, {
            'op': 'show_app',
          });
        }

        await runProgram();
        // The client cannot open a window until the server accepts the gesture.
        expect(appWindow, findsNothing);
        ingest('open');
        await tester.pumpAndSettle();
        expect(store.layoutError, isNull);
        expect(
          find.descendant(of: programWindow, matching: find.text('Count: 0')),
          findsNothing,
        );
        expect(
          find.descendant(of: appWindow, matching: find.text('Count: 0')),
          findsOneWidget,
        );
        final programRect = tester.getRect(programWindow);
        final appRect = tester.getRect(appWindow);
        expect(appRect.left, greaterThanOrEqualTo(programRect.right));
        expect(appRect.top, programRect.top);
        final plus = find.descendant(of: appWindow, matching: find.text('+1'));
        final buttonRect = tester.getRect(plus);
        expect(appRect.contains(buttonRect.topLeft), isTrue);
        expect(appRect.contains(buttonRect.bottomRight), isTrue);
        expect(plus.hitTestable(), findsOneWidget);
        if (demo) {
          for (final label in [
            '+1',
            '-1',
            'Reset',
            'Add point',
            'Open log window',
            'Close log window',
            'Count: 0',
          ]) {
            final control = find.descendant(
              of: appWindow,
              matching: find.text(label),
            );
            final rect = tester.getRect(control);
            expect(appRect.contains(rect.topLeft), isTrue, reason: label);
            expect(appRect.contains(rect.bottomRight), isTrue, reason: label);
            expect(control.hitTestable(), findsOneWidget, reason: label);
          }
        }
        final appElement = appWindow.evaluate().single;
        await tester.runAsync(() => tester.tap(plus));
        await pumpUntil(
          tester,
          () => find.text('Count: 1').evaluate().isNotEmpty,
        );
        expect(appWindow.evaluate().single, same(appElement));
        expect(actions, hasLength(1));
        expect(checks, 2); // Run and the user-started event, once each.
        await runProgram();
        await tester.pumpAndSettle();
        expect(appWindow.evaluate().single, same(appElement));
        expect(find.text('Count: 0'), findsOneWidget);
        expect(starter.starts, 1);
        expect(find.text('Run 1 · ok'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('python-repl-history')));
        await tester.pumpAndSettle();
        expect(find.text('Run 1 · ok'), findsOneWidget);
        ingest('closed');
        await tester.pumpAndSettle();
        expect(appWindow, findsNothing);
        expect(find.byType(PythonReplView), findsOneWidget);
        await runProgram();
        ingest('reopened');
        await tester.pumpAndSettle();
        expect(appWindow, findsOneWidget);
        expect(starter.starts, 1);
        // Reload drops interpreter and app state. Replay is a placeholder.
        await tester.pumpWidget(const SizedBox());
        await mount();
        expect(find.text('Press Run to open this app.'), findsOneWidget);
        expect(find.text('Count: 0'), findsNothing);
        expect(starter.starts, 1);
        expect(actions, hasLength(3));
        expect(checks, 4); // Reload and replay did not check the source.
        await runProgram();
        await tester.pumpAndSettle();
        expect(starter.starts, 2);
        expect(find.text('Count: 0'), findsOneWidget);
        final apps = ProgramAppScope.maybeOf(
          tester.element(find.byType(PythonReplView)),
        )!;
        final program = tester
            .widget<PythonReplView>(
              find.byType(PythonReplView),
            )
            .surfaceId!;
        expect(apps.view(program), isNotNull);
        ingest('cascade');
        await tester.pumpAndSettle();
        expect(appWindow, findsNothing);
        expect(programWindow, findsNothing);
        expect(find.byType(PythonReplView), findsNothing);
        expect(apps.view(program), isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        store.dispose();
        await settleFor(tester, const Duration(milliseconds: 100));
        await tester.runAsync(starter.close);
        semantics.dispose();
      },
      skip: skipWithoutMonty != false,
    );
  }
}
