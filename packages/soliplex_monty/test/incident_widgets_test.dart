@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

import 'python_repl_test.dart' as repl;
import 'support/monty.dart';
import 'support/showcase_checks.dart';

Widget _app(ProgramApps apps, Widget program) => MaterialApp(
  theme: soliplexLightTheme(),
  home: Scaffold(
    body: ProgramAppScope(
      apps: apps,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: SingleChildScrollView(child: program)),
          Expanded(
            child: ProgramAppView(program: 'incident', apps: apps),
          ),
        ],
      ),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('publication and remount stay inert until Run', (tester) async {
    final apps = ProgramApps();
    addTearDown(apps.dispose);
    var starts = 0;
    var reads = 0;
    apps.readFile = (_) async {
      reads++;
      return '';
    };
    for (var revision = 0; revision < 2; revision++) {
      await tester.pumpWidget(
        _app(
          apps,
          PythonReplView(
            key: ValueKey(revision),
            source: demoSource('incident_flight_recorder'),
            surfaceId: 'incident',
            limits: const ReplLimits(),
            startRuntime: (_, _) async {
              starts++;
              throw StateError('Reload must not execute source');
            },
            onWorkbench: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Run'), findsOneWidget);
      expect(find.text('Replay observed incident'), findsNothing);
      expect(starts, 0);
      expect(reads, 0);
      expect(apps.view('incident'), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'embedded charts inspect ticks and compare without losing controls',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1800, 5000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      final disk = <String, String>{};
      final apps = ProgramApps()
        ..readFile = ((name) async => disk[name] ?? '')
        ..writeFile = (name, text) async {
          disk[name] = text;
        };
      final starter = MontyStarter();
      final actions = <Map<String, Object?>>[];
      var result = <String, Object?>{};
      await tester.pumpWidget(
        _app(
          apps,
          PythonReplView(
            source: demoSource('incident_flight_recorder'),
            surfaceId: 'incident',
            limits: const ReplLimits(),
            startRuntime: starter.call,
            writeResult: (value) => result = value,
            onWorkbench: () async {
              actions.add({...result});
            },
          ),
        ),
      );
      expect(starter.starts, 0);
      await repl.tapRun(tester);
      await repl.waitFor(
        tester,
        () => repl.idle(tester) && apps.view('incident') != null,
      );
      Future<void> click(String label, bool Function() ready) async {
        await tester.runAsync(() => tester.tap(find.text(label)));
        await tester.pump();
        await repl.waitFor(
          tester,
          () => repl.idle(tester) && ready(),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await click(
        'Replay observed incident',
        () => find.byKey(const ValueKey('chart-bar:T5')).evaluate().isNotEmpty,
      );
      expect(find.bySemanticsLabel(RegExp('Bar T5: 6')), findsOneWidget);
      expect(find.text('Freeze before tick 6'), findsOneWidget);
      final before = actions.length;
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('chart-bar:T5'))),
      );
      await repl.waitFor(
        tester,
        () => repl.idle(tester) && actions.length > before,
      );
      expect(find.text('Inspecting tick 5.'), findsOneWidget);
      final update = (actions.last['actions']! as List)
          .cast<Map<Object?, Object?>>()
          .singleWhere(
            (a) => a['op'] == 'update',
          );
      expect(update['content'], contains('"pending_retries": 6'));
      expect(update['content'], contains('fault-5'));
      await click(
        'Freeze before tick 6',
        () => find.text('Compare mitigations').evaluate().isNotEmpty,
      );
      await click(
        'Compare mitigations',
        () => find.text('Capacity 12: final backlog 6').evaluate().isNotEmpty,
      );
      expect(find.text('Capacity 12: final backlog 6'), findsOneWidget);
      expect(
        find.text('Retries disabled: backlog 0 at tick 7'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) => w.runtimeType.toString() == 'LineChart'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) => w.runtimeType.toString() == 'BarChart'),
        findsWidgets,
      );
      expect(find.text('Minimize triggering events'), findsOneWidget);
      expect(find.textContaining('Invalid chart'), findsNothing);
      expect((apps.snapshot()['incident']! as Map)['observed'], [
        0,
        0,
        0,
        2,
        6,
        8,
        12,
        16,
        20,
        24,
        28,
        32,
      ]);
      expect(starter.starts, 1);
      await tester.pumpWidget(const SizedBox());
      apps.dispose();
      await tester.runAsync(starter.close);
      semantics.dispose();
    },
    skip: skipWithoutMonty != false,
  );
}
