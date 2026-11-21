import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/basic_catalog.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_design/soliplex_design.dart';

void main() {
  for (final dark in [false, true]) {
    for (final width in [220.0, 720.0]) {
      for (final layout in ['Column', 'Row']) {
        testWidgets('embedded $layout at $width dark=$dark selects a bar', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          final processor = MessageProcessor<ComponentImplementation>(
            catalogs: [basicCatalog(), chartGraphicsCatalog()],
            validationConfig: ValidationConfig.strict,
          );
          addTearDown(processor.dispose);
          final errors = <Object>[];
          processor.model.onError.subscribe(errors.add);
          processor.processMessages([
            {
              'version': '1.0',
              'createSurface': {
                'surfaceId': 'embedded',
                'catalogId': BasicCatalog.v1_0Id,
              },
            },
            {
              'version': '1.0',
              'updateComponents': {
                'surfaceId': 'embedded',
                'components': [
                  {
                    'id': 'root',
                    'component': layout,
                    'align': 'start',
                    'children': ['card', 'button'],
                  },
                  {'id': 'card', 'component': 'Card', 'child': 'chart'},
                  {
                    'id': 'chart',
                    'component': 'Chart',
                    '@catalogId': chartGraphicsCatalogId,
                    'selection': <String>[],
                    'selected': {'@path': '/selected'},
                    'action': {
                      'event': {
                        'name': 'choose',
                        'context': {
                          'label': {'@path': '/selected'},
                          'extra': 'kept',
                        },
                      },
                    },
                    'description': 'Regions',
                    'spec': {
                      'kind': 'bar',
                      'title': 'Regions',
                      'points': [
                        {'id': 'n', 'label': 'North', 'value': 80},
                        {'id': 's', 'label': 'South', 'value': 76},
                      ],
                    },
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
          expect(errors, isEmpty);
          final actions = <Map<String, Object?>>[];
          processor.model.onAction.subscribe((a) => actions.add(a.toJson()));
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? soliplexDarkTheme() : soliplexLightTheme(),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: SingleChildScrollView(
                      child: A2uiSurface(
                        surface: processor.model.allSurfaces.single,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Refresh'), findsOneWidget);
          expect(
            find.bySemanticsLabel('bar chart: Regions; North: 80, South: 76'),
            findsOneWidget,
          );
          final north = find.bySemanticsLabel('Bar North: 80');
          expect(north, findsOneWidget);
          expect(
            tester
                .getSemantics(north)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue,
          );
          await tester.tap(find.byKey(const ValueKey('chart-bar:North')));
          await tester.pumpAndSettle();
          expect(
            processor.model.allSurfaces.single.dataModel.get('/selected'),
            'North',
          );
          expect(actions.single['name'], 'choose');
          expect(actions.single['context'], {
            'label': 'North',
            'extra': 'kept',
          });
          final bars = find.byType(BarChart);
          expect(bars, findsNWidgets(2));
          for (final bar in bars.evaluate()) {
            expect(tester.getSize(find.byWidget(bar.widget)).isFinite, isTrue);
          }
          semantics.dispose();
        });
      }
    }
  }

  testWidgets('line gaps survive validation and reach fl_chart', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final spec = {
      'kind': 'line',
      'title': 'Weekly visits',
      'series': [
        for (var i = 0; i < 6; i++)
          {
            'id': 'series$i',
            'label': 'Visits $i',
            'points': [
              {'id': 'm', 'label': 'Mon', 'value': 2},
              {'id': 't', 'label': 'Tue', 'value': null},
              {'id': 'w', 'label': 'Wed', 'value': -4},
            ],
          },
      ],
    };
    expect(() => validateStaticChartSpec(spec), returnsNormally);
    final processor = MessageProcessor<ComponentImplementation>(
      catalogs: [chartGraphicsCatalog()],
      validationConfig: ValidationConfig.strict,
    );
    addTearDown(processor.dispose);
    final errors = <Object>[];
    processor.model.onError.subscribe(errors.add);
    processor.processMessages([
      {
        'version': '1.0',
        'createSurface': {
          'surfaceId': 'line',
          'catalogId': chartGraphicsCatalogId,
        },
      },
      {
        'version': '1.0',
        'updateComponents': {
          'surfaceId': 'line',
          'components': [
            {
              'id': 'root',
              'component': 'Chart',
              'spec': spec,
              'selection': <String>[],
              'description': 'Weekly visits',
            },
          ],
        },
      },
    ]);
    expect(errors, isEmpty);
    await tester.pumpWidget(
      MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(
          body: A2uiSurface(surface: processor.model.allSurfaces.single),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final lines = tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .lineBarsData;
    expect(
      find.bySemanticsLabel(
        'Line chart Weekly visits: 6 series over 3 points, from -4 to 2',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        RegExp(
          'line chart: Weekly visits; Visits 0, Mon: 2, Tue: gap, Wed: -4',
        ),
      ),
      findsOneWidget,
    );
    expect(lines, hasLength(6));
    for (final line in lines) {
      expect(line.spots[1], FlSpot.nullSpot);
      expect(line.spots[2].y, -1);
    }
    expect(tester.takeException(), isNull);
    expect(
      () => validateStaticChartSpec({
        'kind': 'bar',
        'points': [
          {'id': 'a', 'label': 'A', 'value': null},
        ],
      }),
      throwsFormatException,
    );
    semantics.dispose();
  });
}
