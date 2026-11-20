import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';

const _surfaceId = 'chart';

Map<String, Object?> _update(List<String> ids, List<int> values) => {
  'version': '1.0',
  'updateComponents': {
    'surfaceId': _surfaceId,
    'components': [
      {
        'id': 'root',
        'component': 'Chart',
        'description': 'Demo',
        'selection': <String>[],
        'spec': {
          'kind': 'bar',
          'points': [
            for (var i = 0; i < ids.length; i++)
              {'id': ids[i], 'label': ids[i], 'value': values[i]},
          ],
        },
      },
    ],
  },
};

MessageProcessor<ComponentImplementation> _chart() =>
    MessageProcessor<ComponentImplementation>(
      catalogs: [chartGraphicsCatalog()],
    )..processMessages([
      {
        'version': '1.0',
        'createSurface': {
          'surfaceId': _surfaceId,
          'catalogId': chartGraphicsCatalogId,
        },
      },
      _update(['north', 'south'], [2, 10]),
    ]);

Widget _view(
  MessageProcessor<ComponentImplementation> processor, {
  bool reduceMotion = false,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(
      body: A2uiSurface(surface: processor.model.allSurfaces.single),
    ),
  ),
);

void main() {
  testWidgets('animates value changes on the same ordered points', (
    tester,
  ) async {
    final processor = _chart();
    addTearDown(processor.dispose);
    await tester.pumpWidget(_view(processor));
    expect(tester.binding.transientCallbackCount, 0);
    final bars = find.byType(BarChart);
    final original = tester.state(bars.first);

    processor.processMessages([
      _update(['north', 'south'], [7, 10]),
    ]);
    await tester.pump();
    expect(tester.state(bars.first), same(original));
    expect(
      tester
          .widget<BarChart>(bars.first)
          .data
          .barGroups
          .single
          .barRods
          .single
          .toY,
      0.7,
    );
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);

    processor.processMessages([
      _update(['south', 'north'], [10, 7]),
    ]);
    await tester.pump();
    expect(tester.state(bars.first), isNot(same(original)));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('fresh mount and reduced motion paint without a tween', (
    tester,
  ) async {
    final processor = _chart();
    addTearDown(processor.dispose);
    processor.processMessages([
      _update(['north', 'south'], [7, 10]),
    ]);
    await tester.pumpWidget(_view(processor, reduceMotion: true));
    expect(tester.binding.transientCallbackCount, 0);

    processor.processMessages([
      _update(['north', 'south'], [4, 10]),
    ]);
    await tester.pump();
    final bar = tester.widget<BarChart>(find.byType(BarChart).first);
    expect(bar.duration, Duration.zero);
    expect(bar.data.barGroups.single.barRods.single.toY, 0.4);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('line values animate until a new surface mounts', (tester) async {
    Map<String, Object?> lineUpdate(int value) => {
      'version': '1.0',
      'updateComponents': {
        'surfaceId': _surfaceId,
        'components': [
          {
            'id': 'root',
            'component': 'Chart',
            'description': 'Line demo',
            'selection': <String>[],
            'spec': {
              'kind': 'line',
              'series': [
                {
                  'id': 'readiness',
                  'points': [
                    {'id': 'jan', 'label': 'Jan', 'value': value},
                    {'id': 'feb', 'label': 'Feb', 'value': 10},
                  ],
                },
              ],
            },
          },
        ],
      },
    };

    final original = _chart()..processMessages([lineUpdate(2)]);
    final restored = _chart()..processMessages([lineUpdate(7)]);
    addTearDown(original.dispose);
    addTearDown(restored.dispose);
    await tester.pumpWidget(_view(original));
    final line = find.byType(LineChart);
    final originalState = tester
        .state<ImplicitlyAnimatedWidgetState<LineChart>>(line);
    expect(originalState.animation.status, AnimationStatus.dismissed);

    original.processMessages([lineUpdate(7)]);
    await tester.pump();
    expect(tester.state(line), same(originalState));
    expect(originalState.animation.status, AnimationStatus.forward);

    await tester.pumpWidget(_view(restored));
    final restoredState = tester
        .state<ImplicitlyAnimatedWidgetState<LineChart>>(line);
    expect(restoredState, isNot(same(originalState)));
    expect(restoredState.animation.status, AnimationStatus.dismissed);
    expect(
      tester.widget<LineChart>(line).data.lineBarsData.single.spots.first.y,
      0.7,
    );
  });

  testWidgets('gauge fills animate across the target on the mounted scale', (
    tester,
  ) async {
    Map<String, Object?> gaugeUpdate(double value) => {
      'version': '1.0',
      'updateComponents': {
        'surfaceId': _surfaceId,
        'components': [
          {
            'id': 'root',
            'component': 'Chart',
            'description': 'Readiness gauge',
            'selection': <String>[],
            'spec': {
              'kind': 'gauge',
              'min_value': 0,
              'max_value': 100,
              'target': 80,
              'value': value,
            },
          },
        ],
      },
    };

    final processor = _chart()..processMessages([gaugeUpdate(76.59)]);
    addTearDown(processor.dispose);
    await tester.pumpWidget(_view(processor));
    final gauge = find.byType(GaugeChart);
    final state = tester.state<ImplicitlyAnimatedWidgetState<GaugeChart>>(
      gauge,
    );
    expect(state.animation.status, AnimationStatus.dismissed);

    processor.processMessages([gaugeUpdate(80.65)]);
    await tester.pump();
    expect(tester.state(gauge), same(state));
    expect(state.animation.status, AnimationStatus.forward);
    await tester.pumpAndSettle();
    expect(find.text('80.65'), findsOneWidget);
  });
}
