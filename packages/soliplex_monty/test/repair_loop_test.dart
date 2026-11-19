import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

import 'support/lab_surface.dart';
import 'support/monty.dart';

const failing = 'import tkinter\nprint("board")';

/// A server-published editor with the repair action, as the lab tool sends.
List<Map<String, Object?>> replSurface(
  String surfaceId,
  String source, {
  Map<String, Object?> retry = const {},
}) => [
  {
    'version': '1.0',
    'createSurface': {'surfaceId': surfaceId, 'catalogId': labCatalogId},
  },
  {
    'version': '1.0',
    'updateDataModel': {
      'surfaceId': surfaceId,
      'path': '/',
      'value': {
        'repl': {'source': source},
      },
    },
  },
  {
    'version': '1.0',
    'updateComponents': {
      'surfaceId': surfaceId,
      'components': [
        {
          'id': 'root',
          'component': 'PythonRepl',
          'source': {'@path': '/repl/source'},
          'outputPath': '/repl/result',
          'retry': retry,
          'onFailure': {
            'event': {
              'name': 'python_failed',
              'context': {
                'result': {'@path': '/repl/result'},
              },
            },
          },
        },
      ],
    },
  },
];

/// One host per controller, so each REPL's controls are found by host.
class Hosts {
  Hosts(this.starter, this.chains);

  final MontyStarter starter;
  final RepairChains chains;
  final List<LabSurfaceController> controllers = [];
  final List<Map<String, Object?>> actions = [];

  LabSurfaceController add({required bool live, ReplLimits? limits}) {
    final controller = LabSurfaceController(
      startRuntime: starter.call,
      limits: limits ?? const ReplLimits(),
      live: live,
      chains: chains,
      onActionPayload: actions.add,
    );
    controllers.add(controller);
    return controller;
  }

  Widget build() => MaterialApp(
    theme: soliplexLightTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            for (final (i, c) in controllers.indexed)
              KeyedSubtree(
                key: ValueKey('host-$i'),
                child: LabSurfaceView(controller: c),
              ),
          ],
        ),
      ),
    ),
  );

  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
  }
}

Finder inHost(int host, String key) => find.descendant(
  of: find.byKey(ValueKey('host-$host')),
  matching: find.byKey(ValueKey(key)),
);

Map<String, Object?> resultOf(Map<String, Object?> action) =>
    ((action['context']! as Map)['result']! as Map).cast<String, Object?>();

bool enabled(WidgetTester tester, Finder button) =>
    tester.widget<SoliplexButton>(button).onPressed != null;

void main() {
  late Hosts hosts;

  Future<void> mount(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1200, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(hosts.build());
  }

  Future<void> rebuild(WidgetTester tester) async {
    await tester.pumpWidget(hosts.build());
    await tester.pump();
  }

  /// Taps in the real zone, then rebuilds so the tap's state shows.
  Future<void> tap(WidgetTester tester, int host, String key) async {
    await tester.runAsync(() => tester.tap(inHost(host, key)));
    await tester.pump();
  }

  final autoRuns = <VoidCallback>[];

  setUp(() {
    hosts = Hosts(MontyStarter(), RepairChains());
    autoRuns.clear();
    PythonReplView.debugScheduleAutoRun = autoRuns.add;
  });

  tearDown(() => PythonReplView.debugScheduleAutoRun = null);

  /// Unmounts the REPLs, then closes their runtimes in the real zone.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Lets the views' runtime disposal, begun in the fake zone, finish.
    await settleFor(tester, const Duration(milliseconds: 300));
    hosts.dispose();
    await tester.runAsync(hosts.starter.close);
  }

  /// Mounts one editor with [source], runs it and waits for it to finish.
  Future<void> runFirst(
    WidgetTester tester,
    String source, {
    Map<String, Object?> retry = const {},
  }) async {
    hosts.add(live: false).apply(replSurface('first', source, retry: retry));
    await mount(tester);
    await tap(tester, 0, 'python-repl-run');
    await pumpUntil(
      tester,
      () => enabled(tester, inHost(0, 'python-repl-run')),
    );
    // The repair action resolves its context before it is dispatched.
    await settleFor(tester, const Duration(milliseconds: 200));
  }

  /// Delivers the model's repaired editor into a new host.
  Future<void> deliver(
    WidgetTester tester,
    String source, {
    required bool live,
    required int attempt,
    String? chainId,
    String surfaceId = 'fix',
  }) async {
    final id = chainId ?? resultOf(hosts.actions.last)['chainId']! as String;
    hosts
        .add(live: live)
        .apply(
          replSurface(
            surfaceId,
            source,
            retry: {'chainId': id, 'attempt': attempt},
          ),
        );
    await rebuild(tester);
    // Runs on arrival start in the real zone, as a frame callback does live.
    final starts = [...autoRuns];
    autoRuns.clear();
    await tester.runAsync(() async {
      for (final start in starts) {
        start();
      }
    });
  }

  testWidgets(
    'a failure dispatches python_failed once with the error and chain',
    (tester) async {
      await runFirst(tester, failing);
      await settleFor(tester);
      final action = hosts.actions.single;
      expect(action['name'], 'python_failed');
      final result = resultOf(action);
      expect(result['ok'], false);
      expect(result['attempt'], 1);
      expect(result['source'], failing);
      expect(result['error'], contains('tkinter'));
      expect(result['chainId'], isA<String>());
      expect(
        find.textContaining('Asking the model to fix it (attempt 1 of 2)'),
        findsOneWidget,
      );
      await finish(tester);
    },
    skip: skipWithoutMonty != false,
  );

  testWidgets(
    'a live repaired editor for a live chain runs on arrival',
    (tester) async {
      await runFirst(tester, failing);
      await deliver(tester, 'print("fixed")', live: true, attempt: 1);
      await pumpUntil(
        tester,
        () => find.text('Fixed after 1 attempt').evaluate().isNotEmpty,
      );
      expect(find.text('fixed'), findsOneWidget);
      expect(hosts.actions, hasLength(1));
      await finish(tester);
    },
    skip: skipWithoutMonty != false,
  );

  testWidgets(
    'the same editor restored from history waits for Run',
    (tester) async {
      await runFirst(tester, failing);
      final starts = hosts.starter.starts;
      await deliver(tester, 'print("fixed")', live: false, attempt: 1);
      await settleFor(tester);
      expect(hosts.starter.starts, starts);
      expect(find.text('Press Run to execute the code.'), findsOneWidget);
      await finish(tester);
    },
    skip: skipWithoutMonty != false,
  );

  testWidgets(
    'a repaired editor with no chain in memory waits for Run',
    (tester) async {
      hosts
          .add(live: true)
          .apply(
            replSurface(
              'fix',
              'print("fixed")',
              retry: {'chainId': 'from-another-session', 'attempt': 1},
            ),
          );
      await mount(tester);
      await settleFor(tester);
      expect(hosts.starter.starts, 0);
      await finish(tester);
    },
    skip: skipWithoutMonty != false,
  );

  testWidgets(
    'exhaustion asks, Yes requests one more round and No ends the chain',
    (tester) async {
      await runFirst(tester, failing, retry: {'max': 1});
      await deliver(tester, 'import pygame', live: true, attempt: 1);
      await pumpUntil(
        tester,
        () => find.text('Do you want to try again?').evaluate().isNotEmpty,
      );
      expect(hosts.actions, hasLength(1));

      await tap(tester, 1, 'python-repl-yes');
      await tester.pump();
      expect(hosts.actions, hasLength(2));
      expect(resultOf(hosts.actions.last)['attempt'], 2);
      expect(
        find.textContaining('(attempt 2 of 2)'),
        findsOneWidget,
      );

      await deliver(
        tester,
        'import numpy',
        live: true,
        attempt: 2,
        surfaceId: 'fix2',
      );
      await pumpUntil(
        tester,
        () => find.text('Do you want to try again?').evaluate().isNotEmpty,
      );
      await tap(tester, 2, 'python-repl-no');
      await tester.pump();
      expect(find.text('Do you want to try again?'), findsNothing);
      final chain =
          hosts.chains[resultOf(hosts.actions.last)['chainId']! as String]!;
      expect(chain.status, RepairStatus.ended);
      expect(hosts.actions, hasLength(2));
      await finish(tester);
    },
    skip: skipWithoutMonty != false,
  );

  testWidgets(
    'Stop cancels the pending repair before it arrives',
    (tester) async {
      await runFirst(tester, failing);
      await tap(tester, 0, 'python-repl-stop');
      await tester.pump();
      expect(find.byKey(const ValueKey('python-repl-stop')), findsNothing);
      final starts = hosts.starter.starts;
      await deliver(tester, 'print("fixed")', live: true, attempt: 1);
      await settleFor(tester);
      expect(hosts.starter.starts, starts);
      expect(hosts.actions, hasLength(1));
      await finish(tester);
    },
    skip: skipWithoutMonty != false,
  );

  testWidgets(
    'a failure of edited code asks instead of requesting a repair',
    (tester) async {
      await runFirst(tester, failing);
      await tap(tester, 0, 'python-repl-stop');
      await tester.enterText(inHost(0, 'python-repl-editor'), 'import pygame');
      await tester.pump();
      await tap(tester, 0, 'python-repl-run');
      await pumpUntil(
        tester,
        () => find.text('Do you want to try again?').evaluate().isNotEmpty,
      );
      expect(hosts.actions, hasLength(1));
      await finish(tester);
    },
    skip: skipWithoutMonty != false,
  );

  testWidgets(
    'two live copies of one repair run it once',
    (tester) async {
      await runFirst(tester, failing);
      final id = resultOf(hosts.actions.last)['chainId']! as String;
      final starts = hosts.starter.starts;
      await deliver(tester, 'print("fixed")', live: true, attempt: 1);
      await deliver(
        tester,
        'print("fixed")',
        live: true,
        attempt: 1,
        chainId: id,
        surfaceId: 'fix-copy',
      );
      await pumpUntil(
        tester,
        () => find.text('Fixed after 1 attempt').evaluate().isNotEmpty,
      );
      await settleFor(tester);
      expect(hosts.starter.starts, starts + 1);
      expect(find.text('Fixed after 1 attempt'), findsOneWidget);
      await finish(tester);
    },
    skip: skipWithoutMonty != false,
  );

  group('AI Fix', () {
    Finder aiFix(int host) => inHost(host, 'python-repl-ai-fix');

    testWidgets(
      'appears only after a failed run',
      (tester) async {
        hosts.add(live: false).apply(replSurface('first', 'print(1)'));
        await mount(tester);
        expect(aiFix(0), findsNothing);
        await tap(tester, 0, 'python-repl-run');
        await pumpUntil(
          tester,
          () => enabled(tester, inHost(0, 'python-repl-run')),
        );
        expect(aiFix(0), findsNothing);
        await tester.enterText(inHost(0, 'python-repl-editor'), failing);
        await tester.pump();
        await tap(tester, 0, 'python-repl-run');
        await pumpUntil(tester, () => aiFix(0).evaluate().isNotEmpty);
        await finish(tester);
      },
      skip: skipWithoutMonty != false,
    );

    testWidgets(
      'sends the edited code once per click and is disabled while pending',
      (tester) async {
        await runFirst(tester, failing, retry: {'max': 0});
        expect(hosts.actions, isEmpty);
        expect(find.text('Do you want to try again?'), findsOneWidget);
        expect(enabled(tester, aiFix(0)), isTrue);

        const edited = 'import pygame\nprint("mine")';
        await tester.enterText(inHost(0, 'python-repl-editor'), edited);
        await tester.pump();
        await tap(tester, 0, 'python-repl-ai-fix');
        await tester.pump();
        expect(hosts.actions, hasLength(1));
        final result = resultOf(hosts.actions.single);
        expect(result['source'], edited);
        expect(result['error'], contains('tkinter'));
        expect(result['attempt'], 1);
        expect(enabled(tester, aiFix(0)), isFalse);
        expect(find.textContaining('(attempt 1 of 1)'), findsOneWidget);

        await tap(tester, 0, 'python-repl-ai-fix');
        await tester.pump();
        expect(hosts.actions, hasLength(1));

        await deliver(tester, 'print("fixed")', live: true, attempt: 1);
        await pumpUntil(
          tester,
          () => find.text('Fixed after 1 attempt').evaluate().isNotEmpty,
        );
        await finish(tester);
      },
      skip: skipWithoutMonty != false,
    );
  });

  testWidgets(
    'the first Run shows Loading Monty… and then Running',
    (tester) async {
      hosts = Hosts(
        MontyStarter(delay: const Duration(milliseconds: 400)),
        RepairChains(),
      );
      hosts
          .add(
            live: false,
            limits: const ReplLimits(
              maxFeedDuration: Duration(seconds: 5),
              deadline: Duration(seconds: 10),
            ),
          )
          .apply(
            replSurface(
              'first',
              'n = 0\nfor i in range(3000000):\n    n += i\nn',
            ),
          );
      await mount(tester);
      await tap(tester, 0, 'python-repl-run');
      await tester.pump();
      expect(find.text('Loading Monty…'), findsOneWidget);
      await pumpUntil(
        tester,
        () => find.text('Running').evaluate().isNotEmpty,
      );
      expect(find.text('Loading Monty…'), findsNothing);
      await pumpUntil(
        tester,
        () => enabled(tester, inHost(0, 'python-repl-run')),
      );
      expect(find.text('Run'), findsOneWidget);
      await finish(tester);
    },
    skip: skipWithoutMonty != false,
  );
}
