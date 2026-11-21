import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';

Map<String, Object?> _update(Map<String, Object?> spec) => {
  'version': '1.0',
  'updateComponents': {
    'surfaceId': 'chart',
    'components': [
      {
        'id': 'root',
        'component': 'Chart',
        'description': 'Demo',
        'selection': <String>[],
        'spec': spec,
      },
    ],
  },
};

MessageProcessor<ComponentImplementation> _surface(Map<String, Object?> spec) =>
    MessageProcessor<ComponentImplementation>(
      catalogs: [chartGraphicsCatalog()],
    )..processMessages([
      {
        'version': '1.0',
        'createSurface': {
          'surfaceId': 'chart',
          'catalogId': chartGraphicsCatalogId,
        },
      },
      _update(spec),
    ]);

Widget _view(
  MessageProcessor<ComponentImplementation> processor, {
  bool reduceMotion = false,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(
      body: SingleChildScrollView(
        child: A2uiSurface(surface: processor.model.allSurfaces.single),
      ),
    ),
  ),
);

/// One chart kind: a spec builder over (ids, value) and its fl_chart widget.
typedef _Kind = ({
  String name,
  Type widget,
  Map<String, Object?> Function(List<String> ids, double value) spec,
  Duration Function(Widget widget) duration,
});

final List<_Kind> _kinds = [
  (
    name: 'scatter',
    widget: ScatterChart,
    spec: (ids, value) => {
      'kind': 'scatter',
      'series': [
        {
          'id': 's',
          'points': [
            for (var i = 0; i < ids.length; i++)
              {'id': ids[i], 'x': i, 'y': value + i},
          ],
        },
      ],
    },
    duration: (widget) => (widget as ScatterChart).duration,
  ),
  (
    name: 'pie',
    widget: PieChart,
    spec: (ids, value) => {
      'kind': 'pie',
      'slices': [
        for (var i = 0; i < ids.length; i++)
          {'id': ids[i], 'label': ids[i], 'value': value + i},
      ],
    },
    duration: (widget) => (widget as PieChart).duration,
  ),
  (
    name: 'radar',
    widget: RadarChart,
    spec: (ids, value) => {
      'kind': 'radar',
      'axes': [
        for (final id in ['a', 'b', 'c']) {'id': id, 'label': id},
      ],
      'series': [
        for (final id in ids)
          {
            'id': id,
            'values': [value, 50, 50],
          },
      ],
    },
    duration: (widget) => (widget as RadarChart).duration,
  ),
  (
    name: 'candlestick',
    widget: CandlestickChart,
    spec: (ids, value) => {
      'kind': 'candlestick',
      'candles': [
        for (var i = 0; i < ids.length; i++)
          {
            'id': ids[i],
            'x': i,
            'open': value,
            'high': value + 5,
            'low': value - 5,
            'close': value + 1,
          },
      ],
    },
    duration: (widget) => (widget as CandlestickChart).duration,
  ),
  (
    name: 'gauge',
    widget: GaugeChart,
    spec: (ids, value) => {
      'kind': 'gauge',
      'min_value': 0,
      // The scale is the gauge's identity, so a new id list stands for a
      // new scale here.
      'max_value': ids.length == 2 ? 100 : 200,
      'value': value,
    },
    duration: (widget) => (widget as GaugeChart).duration,
  ),
];

void main() {
  for (final kind in _kinds) {
    group(kind.name, () {
      testWidgets('renders', (tester) async {
        final processor = _surface(kind.spec(['a', 'b'], 20));
        addTearDown(processor.dispose);
        await tester.pumpWidget(_view(processor));
        expect(find.byType(kind.widget), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('reduced motion paints without a tween', (tester) async {
        final processor = _surface(kind.spec(['a', 'b'], 20));
        addTearDown(processor.dispose);
        await tester.pumpWidget(_view(processor, reduceMotion: true));
        processor.processMessages([
          _update(kind.spec(['a', 'b'], 30)),
        ]);
        await tester.pump();
        final widget = tester.widget(find.byType(kind.widget));
        expect(kind.duration(widget), Duration.zero);
        expect(tester.binding.transientCallbackCount, 0);
      });

      testWidgets('keeps its state for new values, remounts for new ids', (
        tester,
      ) async {
        final processor = _surface(kind.spec(['a', 'b'], 20));
        addTearDown(processor.dispose);
        await tester.pumpWidget(_view(processor));
        final chart = find.byType(kind.widget);
        final original = tester.state(chart);

        processor.processMessages([
          _update(kind.spec(['a', 'b'], 30)),
        ]);
        await tester.pump();
        expect(tester.state(chart), same(original));
        await tester.pumpAndSettle();

        processor.processMessages([
          _update(kind.spec(['b', 'a', 'c'], 30)),
        ]);
        await tester.pump();
        expect(tester.state(chart), isNot(same(original)));
      });
    });
  }

  testWidgets('line remounts when its point ids change', (tester) async {
    Map<String, Object?> line(List<String> ids) => {
      'kind': 'line',
      'series': [
        {
          'id': 'readiness',
          'points': [
            for (final id in ids) {'id': id, 'label': id, 'value': 5},
          ],
        },
      ],
    };
    final processor = _surface(line(['jan', 'feb']));
    addTearDown(processor.dispose);
    await tester.pumpWidget(_view(processor));
    final chart = find.byType(LineChart);
    final original = tester.state(chart);
    processor.processMessages([
      _update(line(['feb', 'jan'])),
    ]);
    await tester.pump();
    expect(tester.state(chart), isNot(same(original)));
  });
}
