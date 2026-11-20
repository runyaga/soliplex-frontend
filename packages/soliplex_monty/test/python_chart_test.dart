import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

import 'python_repl_test.dart' as repl;
import 'support/monty.dart';

const _calls = {
  'bar': 'chart.bar([{"id":"a","label":"A","value":80}], title="Counts")',
  'line':
      'chart.line([{"id":"counts","points":'
      '[{"id":"a","label":"A","value":80}]}], title="Counts")',
  'pie': 'chart.pie([{"id":"a","label":"A","value":80}], title="Counts")',
  'gauge': 'chart.gauge(80, min_value=0, max_value=100, title="Counts")',
  'scatter':
      'chart.scatter([{"id":"counts","points":'
      '[{"id":"a","x":1,"y":80}]}], title="Counts")',
  'radar':
      'chart.radar([{"id":"a","label":"A"},{"id":"b","label":"B"},'
      '{"id":"c","label":"C"}], [{"id":"counts","values":[80,60,40]}],'
      ' title="Counts")',
  'candlestick':
      'chart.candlestick([{"id":"a","x":1,"open":10,"high":20,"low":5,'
      '"close":15}], title="Counts")',
};

void main() {
  for (final entry in _calls.entries) {
    testWidgets(
      '${entry.key} chart remains inert until Run and reload is passive',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();

        final starter = MontyStarter();
        final label = RegExp('${entry.key} chart: Counts;');
        Widget app(Key key) => MaterialApp(
          theme: soliplexLightTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: PythonReplView(
                key: key,
                source:
                    'import chart\nimport ui\n'
                    'ui.show(ui.graphics.Chart(${entry.value}, [], "Counts"))',
                limits: const ReplLimits(),
                startRuntime: starter.call,
              ),
            ),
          ),
        );
        await tester.pumpWidget(app(const ValueKey('initial')));
        await tester.pumpAndSettle();
        expect(starter.starts, 0);
        expect(find.bySemanticsLabel(label), findsNothing);
        await repl.tapRun(tester);
        await repl.waitFor(
          tester,
          () => find.bySemanticsLabel(label).evaluate().isNotEmpty,
        );
        expect(starter.starts, 1);
        expect(find.textContaining('Invalid chart'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(app(const ValueKey('reload')));
        await tester.pumpAndSettle();
        expect(starter.starts, 1);
        expect(find.bySemanticsLabel(label), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(starter.close);
        semantics.dispose();
      },
      skip: skipWithoutMonty != false,
    );
  }
}
