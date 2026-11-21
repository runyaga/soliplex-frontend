import 'dart:math' as math;

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/basic_catalog.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_design/soliplex_design.dart';

final _specs = <String, Map<String, Object?>>{
  'line': {
    'series': [
      {
        'id': 'visits',
        'label': 'Visits',
        'points': [
          for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'])
            {'id': day, 'label': day, 'value': day.length + 1},
        ],
      },
    ],
  },
  'pie': {
    'slices': [
      {'id': 'rent', 'label': 'Rent', 'value': 40},
      {'id': 'food', 'label': 'Food', 'value': 35},
      {'id': 'travel', 'label': 'Travel', 'value': 25},
    ],
  },
  'scatter': {
    'xlabel': 'Hours',
    'ylabel': 'Yield',
    'series': [
      for (final name in ['Alpha', 'Beta'])
        {
          'id': name,
          'label': name,
          'points': [
            {'id': 'a', 'label': 'First', 'x': 1, 'y': 2},
            {'id': 'b', 'label': 'Last', 'x': 3, 'y': 4},
          ],
        },
    ],
  },
  'radar': {
    'axes': [
      for (final name in ['Speed', 'Quality', 'Cost'])
        {'id': name, 'label': name},
    ],
    'series': [
      {
        'id': 'alpha',
        'label': 'Alpha',
        'values': [20, 60, 80],
      },
      {
        'id': 'beta',
        'label': 'Beta',
        'values': [70, 40, 60],
      },
    ],
  },
  'candlestick': {
    'xlabel': 'Day',
    'ylabel': 'Price',
    'candles': [
      {'id': 'up', 'x': 1, 'open': 2, 'high': 5, 'low': 1, 'close': 4},
      {'id': 'down', 'x': 2, 'open': 4, 'high': 5, 'low': 1, 'close': 2},
    ],
  },
  'gauge': {
    'value': 65,
    'min_value': 0,
    'max_value': 100,
    'target': 80,
    'unit': '%',
  },
};

Future<ThemeData> _pump(
  WidgetTester tester,
  String kind,
  double width,
  bool dark,
) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final spec = <Object?, Object?>{
    'kind': kind,
    'title': '$kind demo',
    ..._specs[kind]!,
  };
  final theme = dark ? soliplexDarkTheme() : soliplexLightTheme();
  final processor = MessageProcessor<ComponentImplementation>(
    catalogs: [basicCatalog(), chartGraphicsCatalog()],
    validationConfig: ValidationConfig.strict,
  );
  addTearDown(processor.dispose);
  processor.processMessages([
    {
      'version': '1.0',
      'createSurface': {'surfaceId': 'chart', 'catalogId': BasicCatalog.v1_0Id},
    },
    {
      'version': '1.0',
      'updateComponents': {
        'surfaceId': 'chart',
        'components': [
          {
            'id': 'root',
            'component': 'Column',
            'children': ['card', 'button'],
          },
          {'id': 'card', 'component': 'Card', 'child': 'plot'},
          {
            'id': 'plot',
            'component': 'Chart',
            '@catalogId': chartGraphicsCatalogId,
            'spec': spec,
            'selection': <String>[],
            'description': 'demo',
          },
          {
            'id': 'button',
            'component': 'Button',
            'child': 'caption',
            'action': {
              'event': {'name': 'refresh'},
            },
          },
          {'id': 'caption', 'component': 'Text', 'text': 'Refresh'},
        ],
      },
    },
  ]);
  final chart = A2uiSurface(surface: processor.model.allSurfaces.single);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(child: chart),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(find.text('$kind demo'), findsOneWidget);
  expect(find.text('Refresh'), findsOneWidget);
  return theme;
}

double _contrast(Color color, Color background) {
  final a = Color.alphaBlend(color, background).computeLuminance();
  final b = background.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

void main() {
  for (final dark in [false, true]) {
    for (final width in [220.0, 720.0]) {
      testWidgets('line includes endpoint labels at $width dark=$dark', (
        tester,
      ) async {
        await _pump(tester, 'line', width, dark);
        expect(find.text('Mon'), findsOneWidget);
        expect(find.text('Fri'), findsOneWidget);
      });
      testWidgets('pie stays inside its plot at $width dark=$dark', (
        tester,
      ) async {
        await _pump(tester, 'pie', width, dark);
        final data = tester.widget<PieChart>(find.byType(PieChart)).data;
        final size = tester.getSize(find.byType(PieChart));
        final radius =
            data.centerSpaceRadius +
            data.sections.map((s) => s.radius).reduce(math.max);
        expect(
          radius * 2,
          lessThanOrEqualTo(math.min(size.width, size.height)),
        );
      });
      for (final kind in ['pie', 'scatter', 'radar', 'candlestick', 'gauge']) {
        testWidgets(
          '$kind paints visible data and labels at $width dark=$dark',
          (tester) async {
            final semantics = tester.ensureSemantics();
            try {
              final theme = await _pump(tester, kind, width, dark);
              final background = theme.colorScheme.surfaceContainerLow;
              final colors = <Color>[];
              switch (kind) {
                case 'pie':
                  final data = tester
                      .widget<PieChart>(find.byType(PieChart))
                      .data;
                  expect(data.sections, hasLength(3));
                  colors.addAll(data.sections.map((s) => s.color));
                  for (final name in ['Rent', 'Food', 'Travel']) {
                    final label = find.textContaining('$name ·');
                    expect(label, findsOneWidget);
                    final text = tester.widget<Text>(label);
                    final color =
                        text.style?.color ?? theme.colorScheme.onSurface;
                    expect(
                      _contrast(color, background),
                      greaterThanOrEqualTo(4.5),
                    );
                  }
                case 'scatter':
                  final data = tester
                      .widget<ScatterChart>(find.byType(ScatterChart))
                      .data;
                  expect(data.scatterSpots, hasLength(4));
                  colors.addAll(
                    data.scatterSpots.map(
                      (s) => (s.dotPainter as FlDotCirclePainter).color,
                    ),
                  );
                  for (final name in ['Alpha', 'Beta', 'Hours', 'Yield']) {
                    expect(find.text(name), findsOneWidget);
                  }
                  expect(
                    find.bySemanticsLabel(RegExp('First: 2.*Last: 4')),
                    findsOneWidget,
                  );
                case 'radar':
                  final data = tester
                      .widget<RadarChart>(find.byType(RadarChart))
                      .data;
                  expect(data.dataSets, hasLength(3));
                  colors.addAll(
                    data.dataSets.skip(1).map((s) => s.borderColor),
                  );
                  for (final name in ['Alpha', 'Beta']) {
                    expect(find.text(name), findsOneWidget);
                  }
                  for (var i = 0; i < 3; i++) {
                    expect(
                      data.getTitle!(i, 0).text,
                      ['Speed', 'Quality', 'Cost'][i],
                    );
                  }
                case 'candlestick':
                  final data = tester
                      .widget<CandlestickChart>(find.byType(CandlestickChart))
                      .data;
                  expect(data.candlestickSpots, hasLength(2));
                  final painter =
                      data.candlestickPainter as DefaultCandlestickPainter;
                  for (var i = 0; i < data.candlestickSpots.length; i++) {
                    colors.add(
                      painter
                          .candlestickStyleProvider(data.candlestickSpots[i], i)
                          .bodyFillColor,
                    );
                  }
                  for (final name in ['Day', 'Price']) {
                    expect(find.text(name), findsOneWidget);
                  }
                  expect(
                    find.bySemanticsLabel(RegExp('up: 4.*down: 2')),
                    findsOneWidget,
                  );
                case 'gauge':
                  final data = tester
                      .widget<GaugeChart>(find.byType(GaugeChart))
                      .data;
                  colors.add((data.rings.single as GaugeProgressRing).color);
                  expect(find.text('65%'), findsOneWidget);
                  expect(find.text('Target 80%'), findsOneWidget);
                  expect(find.text('Scale 0% to 100%'), findsOneWidget);
              }
              for (final color in colors) {
                expect(_contrast(color, background), greaterThanOrEqualTo(3));
              }
              expect(colors, isNotEmpty);
              expect(tester.takeException(), isNull);
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }
  }
}
