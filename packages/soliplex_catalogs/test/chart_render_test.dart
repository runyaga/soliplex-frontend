import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';

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
      {
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
      },
    ]);

Future<void> _mount(
  WidgetTester tester,
  MessageProcessor<ComponentImplementation> processor,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: A2uiSurface(surface: processor.model.allSurfaces.single),
      ),
    ),
  ),
);

void main() {
  dive();

  testWidgets('a margin just below zero keeps its sign and colour', (
    tester,
  ) async {
    final processor = _surface({
      'kind': 'bar',
      'points': [
        {'id': 'north', 'label': 'North', 'value': -0.001},
      ],
    });
    addTearDown(processor.dispose);
    await _mount(tester, processor);
    final text = tester.widget<Text>(find.text('-0.00'));
    final context = tester.element(find.text('-0.00'));
    expect(text.style?.color, Theme.of(context).colorScheme.error);
  });

  testWidgets('bar values show at most two decimals', (tester) async {
    final processor = _surface({
      'kind': 'bar',
      'points': [
        {'id': 'a', 'label': 'A', 'value': 0.6461920000000001},
        {'id': 'b', 'label': 'B', 'value': 12.5},
        {'id': 'c', 'label': 'C', 'value': 3},
      ],
    });
    addTearDown(processor.dispose);
    await _mount(tester, processor);
    expect(find.text('0.65'), findsOneWidget);
    expect(find.text('12.5'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
  testWidgets(
    'gauge formats display values without rounding its scale position',
    (tester) async {
      final spec = <String, Object?>{
        'kind': 'gauge',
        'min_value': -1.0,
        'max_value': 12.5,
        'value': -0.001,
        'target': 3.0,
      };
      final processor = _surface(spec);
      addTearDown(processor.dispose);
      await _mount(tester, processor);
      expect(find.text('-0.00'), findsOneWidget);
      expect(find.text('Target 3'), findsOneWidget);
      expect(find.text('Scale -1 to 12.5'), findsOneWidget);
      final ring =
          tester.widget<GaugeChart>(find.byType(GaugeChart)).data.rings.single
              as GaugeProgressRing;
      expect(ring.value, closeTo(0.999 / 13.5, 1e-12));
      expect(spec['value'], -0.001);
    },
  );
}

Map<String, Object?> _profile({bool reversed = true}) => {
  'kind': 'scatter',
  'title': 'Dive profile',
  'xlabel': 'Minutes',
  'ylabel': 'Depth (ft)',
  'y_reversed': reversed,
  'series': [
    {
      'id': 'profile',
      'line': true,
      'points': [
        {'id': 't0', 'x': 0, 'y': 0},
        {'id': 't1', 'x': 2, 'y': 60},
        {'id': 't2', 'x': 40, 'y': 60},
        {'id': 't3', 'x': 42, 'y': 0},
      ],
    },
    {
      'id': 'limit',
      'points': [
        {'id': 'ndl', 'x': 60, 'y': 60, 'highlight': true},
      ],
    },
  ],
};

void dive() {
  testWidgets('a line series draws a connected profile', (tester) async {
    final processor = _surface(_profile(reversed: false));
    addTearDown(processor.dispose);
    await _mount(tester, processor);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final bars = chart.data.lineBarsData;
    expect(bars.first.barWidth, greaterThan(0));
    expect(bars.first.spots.map((spot) => spot.y), [0, 60, 60, 0]);
    expect(bars.last.barWidth, 0);
  });

  testWidgets('connected scatter preserves the supplied point order', (
    tester,
  ) async {
    final spec = _profile(reversed: false);
    final series = spec['series']! as List;
    final points = (series.first as Map)['points']! as List;
    (points[2] as Map)['x'] = 1;
    final processor = _surface(spec);
    addTearDown(processor.dispose);
    await _mount(tester, processor);
    final bar = tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .lineBarsData
        .first;
    expect(bar.spots.map((p) => p.x), [0, 2, 1, 42]);
  });

  testWidgets('unconnected scatter reverses y and highlights its point', (
    tester,
  ) async {
    final spec = _profile();
    for (final series in spec['series']! as List) {
      (series as Map).remove('line');
    }
    final processor = _surface(spec);
    addTearDown(processor.dispose);
    await _mount(tester, processor);
    final chart = tester.widget<ScatterChart>(find.byType(ScatterChart));
    final spots = chart.data.scatterSpots;
    expect(spots[1].y, -60);
    expect(
      (spots.last.dotPainter as FlDotCirclePainter).radius,
      greaterThan((spots.first.dotPainter as FlDotCirclePainter).radius),
    );
    expect(find.text('-60'), findsNothing);
  });

  testWidgets('a reversed y axis puts larger values lower', (tester) async {
    final processor = _surface(_profile());
    addTearDown(processor.dispose);
    await _mount(tester, processor);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.first.spots[1].y, -60);
    expect(find.text('60'), findsWidgets);
    expect(find.text('-60'), findsNothing);
  });

  testWidgets('a highlighted point draws larger than the others', (
    tester,
  ) async {
    final processor = _surface(_profile());
    addTearDown(processor.dispose);
    await _mount(tester, processor);
    final bars = tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .lineBarsData;
    double radius(LineChartBarData bar, int index) =>
        (bar.dotData.getDotPainter(bar.spots[index], 0, bar, index)
                as FlDotCirclePainter)
            .radius;
    expect(radius(bars.last, 0), greaterThan(radius(bars.first, 0)));
  });

  test('scatter rejects a non-boolean line flag', () {
    final spec = _profile();
    ((spec['series']! as List).first as Map)['line'] = 'yes';
    expect(() => validateStaticChartSpec(spec), throwsFormatException);
  });
}
