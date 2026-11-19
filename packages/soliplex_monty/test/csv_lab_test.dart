import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

import 'support/lab_surface.dart';
import 'support/monty.dart';

const _sales = '''
month,region,units,revenue
2026-01,North,230,9570.22
2026-01,South,203,7891.91
2026-02,North,250,
2026-02,South,210,8120.50
''';

const _barProgram = '''
import ui
import csv

with open("/workspace/room/sales.csv") as f:
    rows = list(csv.DictReader(f.read().splitlines()))
totals = {}
skipped = 0
for row in rows:
    try:
        totals[row["region"]] = totals.get(row["region"], 0) + float(row["revenue"])
    except (ValueError, TypeError, KeyError):
        skipped += 1
bars = [{"label": k, "value": round(v, 2)} for k, v in sorted(totals.items())]
ui.show(ui.Column([
    ui.BarChart(bars, "Revenue by region"),
    ui.Text(f"Skipped {skipped} bad rows", "caption"),
]))
''';

const _lineProgram = '''
import ui
import csv

rows = list(csv.reader(open("/workspace/room/sales.csv").read().splitlines()))[1:]
months = sorted(set(r[0] for r in rows))
series = []
for region in ["North", "South"]:
    values = []
    for m in months:
        found = None
        for r in rows:
            if r[0] == m and r[1] == region and r[3] != "":
                found = float(r[3])
        values.append(found)
    series.append({"label": region, "values": values})
ui.show(ui.LineChart(months, series, "Revenue over time"))
''';

List<Map<String, Object?>> _surface(String source) => [
  {
    'version': '1.0',
    'createSurface': {'surfaceId': 'csv', 'catalogId': labCatalogId},
  },
  {
    'version': '1.0',
    'updateDataModel': {
      'surfaceId': 'csv',
      'path': '/',
      'value': {
        'repl': {'source': source},
      },
    },
  },
  {
    'version': '1.0',
    'updateComponents': {
      'surfaceId': 'csv',
      'components': [
        {
          'id': 'root',
          'component': 'PythonRepl',
          'source': {'@path': '/repl/source'},
          'outputPath': '/repl/result',
          'files': [
            {'name': 'sales.csv', 'content': _sales},
          ],
        },
      ],
    },
  },
];

void main() {
  late MontyStarter starter;
  late LabSurfaceController controller;

  Map<Object?, Object?>? result() =>
      controller.surfaces.single.dataModel.get('/repl/result')
          as Map<Object?, Object?>?;

  Future<void> runProgram(WidgetTester tester, String source) async {
    starter = MontyStarter();
    controller = LabSurfaceController(startRuntime: starter.call);
    tester.view
      ..physicalSize = const Size(1200, 3000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller.apply(_surface(source));
    expect(controller.error, isNull);
    await tester.pumpWidget(
      MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: LabSurfaceView(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('python-repl-run'))),
    );
    await pumpUntil(tester, () => result() != null);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.runAsync(starter.close);
  }

  testWidgets('a program reads a delivered CSV and draws a bar chart', (
    tester,
  ) async {
    await runProgram(tester, _barProgram);
    expect(result()!['ok'], true, reason: '${result()!['output']}');
    expect(find.byKey(const ValueKey('chart-bar:North')), findsOneWidget);
    expect(find.text('9570.22'), findsOneWidget);
    expect(find.text('16012.41'), findsOneWidget);
    expect(find.text('Skipped 1 bad rows'), findsOneWidget);
    await unmount(tester);
  }, skip: skipWithoutMonty != false);

  testWidgets('a program draws a line chart with a gap', (tester) async {
    await runProgram(tester, _lineProgram);
    expect(result()!['ok'], true, reason: '${result()!['output']}');
    expect(find.byKey(const ValueKey('line-chart')), findsOneWidget);
    expect(find.text('North'), findsOneWidget);
    await unmount(tester);
  }, skip: skipWithoutMonty != false);

  testWidgets('an invalid chart is rejected with a reason', (tester) async {
    await runProgram(
      tester,
      'import ui\nui.show(ui.LineChart(["a", "b"], '
      '[{"label": "x", "values": [1]}]))',
    );
    expect(result()!['ok'], false);
    expect(result()!['output'], contains('one value per label'));
    await unmount(tester);
  }, skip: skipWithoutMonty != false);
}
