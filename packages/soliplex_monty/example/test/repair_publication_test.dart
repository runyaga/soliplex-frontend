@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_scope.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_view.dart';
import 'package:soliplex_monty/soliplex_monty.dart';
import 'package:soliplex_monty/src/program_type_check.dart';

import '../../test/python_repl_test.dart' as repl;
import '../../test/repair_loop_test.dart' show replSurface, resultOf;
import '../../test/support/monty.dart';
import '../../test/support/showcase_checks.dart';

void main() {
  for (final name in ['hot_patch', 'healing_pipeline']) {
    testWidgets(
      '$name full repair snapshots retain the runtime through both stages',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'soliplex.python.aiFix.program': true,
        });
        tester.view.physicalSize = const Size(1600, 2600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final disk = <String, String>{};
        final apps = ProgramApps()
          ..readFile = ((name) async => disk[name] ?? '')
          ..writeFile = (name, text) async {
            disk[name] = text;
          };
        final chains = RepairChains();
        final starter = MontyStarter();
        final repairs = <Map<String, Object?>>[];
        final outputs = <Map<String, Object?>>[];
        final scheduled = <VoidCallback>[];
        PythonReplView.debugScheduleAutoRun = scheduled.add;
        addTearDown(() => PythonReplView.debugScheduleAutoRun = null);
        var source = demoSource(name);
        var result = <String, Object?>{};
        String? activeRunId;
        final store = ChatSurfaceStore(
          catalogs: [
            labCatalog(
              startRuntime: starter.call,
              checkTypes: (code, limits) => checkProgramTypes(
                code,
                limits,
                workerLocation: nativeWorker,
              ),
              isLive: ChatSurfaceOrigin.isLive,
              activeRunId: ChatSurfaceOrigin.activeRunIdOf,
              chains: chains,
            ),
          ],
          onAction: (_, action) {
            result = resultOf(action);
            if (action['name'] == 'workbench.program.repair') {
              repairs.add({...result});
            } else if (action['name'] == 'workbench.program.run_result') {
              outputs.add({...result});
            }
          },
        );
        const activityId = 'activity';
        void publish({bool live = true}) {
          final ops = replSurface(
            source,
            workbench: true,
          );
          if (name == 'healing_pipeline') {
            final update = ops.last['updateComponents']! as Map;
            final component = (update['components'] as List).single as Map;
            component['typeCheck'] = true;
          }
          store.obtain(activityId, ops, live: live);
        }

        Widget app() => ChatSurfaceScope(
          store: store,
          activeRunId: activeRunId,
          child: MaterialApp(
            theme: soliplexLightTheme(),
            home: Scaffold(
              body: ProgramAppScope(
                apps: apps,
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: ChatSurfaceView(controller: store[activityId]!),
                      ),
                    ),
                    Expanded(
                      child: ProgramAppView(program: 'program', apps: apps),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        Future<void> deliver(String replacement) async {
          activeRunId = 'repair-${repairs.length}';
          source = replacement;
          publish();
          await tester.pumpWidget(app());
          await tester.pump();
          await tester.pump();
          expect(scheduled, hasLength(1));
          final start = scheduled.removeAt(0);
          await tester.runAsync(() async {
            start();
          });
          await tester.pump();
        }

        publish(live: false);
        await tester.pumpWidget(app());
        await tester.pump();
        expect(starter.starts, 0);
        await repl.tapRun(tester);
        await tester.pump();
        await repl.waitFor(
          tester,
          () =>
              repl.idle(tester) &&
              (name == 'hot_patch'
                  ? apps.view('program') != null
                  : repairs.isNotEmpty),
        );
        if (name == 'hot_patch') {
          for (final button in ['Normal traffic', 'Burst', 'Export report']) {
            await tester.runAsync(() => tester.tap(find.text(button)));
            await tester.pump();
            await repl.waitFor(tester, () => repl.idle(tester));
          }
          expect(repairs, hasLength(1));
          expect(repairs.single['error'], contains('ZeroDivisionError'));
          await deliver(
            source.replaceFirst(
              'sum(samples) / 0',
              'sum(samples) / len(samples)',
            ),
          );
          await repl.waitFor(
            tester,
            () => repl.idle(tester) && outputs.isNotEmpty,
          );
          expect((apps.snapshot()['program']! as Map)['samples'], [
            40,
            50,
            60,
            140,
          ]);
          expect(
            disk['traffic-report.txt'],
            contains('Samples: 4; peak: 140; target: 100'),
          );
        } else {
          expect(repairs, hasLength(1));
          expect(repairs.first['error'], contains('unsupported-operator'));
          expect(disk, isEmpty);
          await deliver(
            source.replaceFirst('return value + "0"', 'return value + 0'),
          );
          await repl.waitFor(
            tester,
            () => repl.idle(tester) && repairs.length == 2,
          );
          expect(repairs.last['error'], contains('ValueError'));
          activeRunId = null;
          await tester.pumpWidget(app());
          await tester.pump();
          expect(chains[repairs.last['chainId']! as String]!.awaiting, 2);
          expect(disk, isEmpty);
          await deliver(
            source.replaceFirst(
              'amount = int(row["total"])',
              'amount = int(row["total"]) if row["total"].isdigit() else 0',
            ),
          );
          await repl.waitFor(
            tester,
            () => repl.idle(tester) && outputs.isNotEmpty,
          );
          expect(disk['clean.csv'], 'month,total\nJan,10\nMar,30\n');
          expect(repairs.map((r) => r['attempt']), [1, 2]);
          expect(repairs.map((r) => r['chainId']).toSet(), hasLength(1));
          expect(chains[repairs.first['chainId']! as String]!.max, 2);
          expect(find.text('Fixed after 2 attempts'), findsOneWidget);
        }
        expect(starter.starts, 1);
        expect(outputs.last['outcome'], 'success');
        expect(outputs.last['chainId'], repairs.last['chainId']);
        await tester.pumpWidget(const SizedBox());
        store.dispose();
        apps.dispose();
        await tester.runAsync(starter.close);
      },
      skip: skipWithoutMonty != false,
    );
  }
}
