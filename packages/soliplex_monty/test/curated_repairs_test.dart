@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_monty/soliplex_monty.dart';
import 'package:soliplex_monty/src/program_type_check.dart';

import 'python_repl_test.dart' as repl;
import 'support/monty.dart';
import 'support/showcase_checks.dart';

void main() {
  for (final name in ['hot_patch', 'healing_pipeline']) {
    testWidgets(
      '$name repairs in the retained session within the budget of two',
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
        Widget app() => MaterialApp(
          theme: soliplexLightTheme(),
          home: Scaffold(
            body: ProgramAppScope(
              apps: apps,
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: PythonReplView(
                        key: const ValueKey('retained'),
                        source: source,
                        surfaceId: 'program',
                        limits: const ReplLimits(),
                        startRuntime: starter.call,
                        typeCheck: name == 'healing_pipeline',
                        checkTypes: (code, limits) => checkProgramTypes(
                          code,
                          limits,
                          workerLocation: nativeWorker,
                        ),
                        live: true,
                        chains: chains,
                        includeRunMetadata: true,
                        writeResult: (value) => result = value,
                        onFailure: () async {
                          repairs.add({...result});
                        },
                        onWorkbench: () async {},
                        onRun: () async {
                          outputs.add({...result});
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: ProgramAppView(program: 'program', apps: apps),
                  ),
                ],
              ),
            ),
          ),
        );
        Future<void> deliver(String replacement) async {
          source = replacement;
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
        apps.dispose();
        await tester.runAsync(starter.close);
      },
      skip: skipWithoutMonty != false,
    );
  }
}
