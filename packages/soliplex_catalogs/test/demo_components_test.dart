import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';

const _catalogId = 'urn:soliplex:sample-tests:1';

MessageProcessor<ComponentImplementation> _processor(
  String component,
  Map<String, Object?> data,
  Map<String, Object?> properties, {
  void Function(A2uiRendererAction)? onAction,
}) {
  final processor = MessageProcessor<ComponentImplementation>(
    catalogs: [
      CatalogImplementation(
        id: _catalogId,
        protocolVersion: A2uiProtocolVersion.v1_0,
        components: demoComponents(),
      ),
    ],
    validationConfig: ValidationConfig.strict,
  );
  if (onAction != null) processor.model.onAction.subscribe(onAction);
  processor.processMessages([
    {
      'version': '1.0',
      'createSurface': {'surfaceId': 'sample', 'catalogId': _catalogId},
    },
    {
      'version': '1.0',
      'updateDataModel': {'surfaceId': 'sample', 'path': '/', 'value': data},
    },
    {
      'version': '1.0',
      'updateComponents': {
        'surfaceId': 'sample',
        'components': [
          {'id': 'root', 'component': component, ...properties},
        ],
      },
    },
  ]);
  return processor;
}

Widget _view(MessageProcessor<ComponentImplementation> processor) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: A2uiSurface(surface: processor.model.allSurfaces.single),
        ),
      ),
    );

void main() {
  void narrow(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'sample comparison filters rows and reveals excerpts at width390',
    (tester) async {
      narrow(tester);
      final processor = _processor(
        'DocumentComparison',
        {'differencesOnly': false},
        {
          'differencesOnly': {'@path': '/differencesOnly'},
        },
      );
      addTearDown(processor.dispose);
      await tester.pumpWidget(_view(processor));
      await tester.pumpAndSettle();
      expect(find.text('Owner'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Owner'), findsNothing);
      expect(find.text('Review interval'), findsOneWidget);
      expect(
        processor.model.allSurfaces.single.dataModel.get('/differencesOnly'),
        isTrue,
      );
      await tester.tap(find.text('Read sample excerpts'));
      await tester.pumpAndSettle();
      expect(find.textContaining('SAMPLE A:'), findsOneWidget);
      expect(find.textContaining('SAMPLE B:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sample estimate emits current typed inputs without computing UI',
    (tester) async {
      narrow(tester);
      final actions = <A2uiRendererAction>[];
      final processor = _processor(
        'EstimateForm',
        {'units': 2, 'rate': 10, 'total': 20},
        {
          'units': {'@path': '/units'},
          'rate': {'@path': '/rate'},
          'total': {'@path': '/total'},
          'onCalculate': {
            'event': {
              'name': 'calculate_sample',
              'context': {
                'units': {'@path': '/units'},
                'rate': {'@path': '/rate'},
              },
            },
          },
        },
        onAction: actions.add,
      );
      addTearDown(processor.dispose);
      await tester.pumpWidget(_view(processor));
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider).first).onChanged!(8);
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider).last).onChanged!(25);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Calculate sample estimate'));
      await tester.pumpAndSettle();
      expect(actions.single.context, {'units': 8, 'rate': 25});
      expect(find.text(r'Last calculated total: $20.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sample workflow selects a node and resolves its action context',
    (tester) async {
      narrow(tester);
      final actions = <A2uiRendererAction>[];
      final processor = _processor(
        'FlowDiagram',
        {'selected': 0},
        {
          'selected': {'@path': '/selected'},
          'onSelect': {
            'event': {
              'name': 'select_sample_stage',
              'context': {
                'selected': {'@path': '/selected'},
              },
            },
          },
        },
        onAction: actions.add,
      );
      addTearDown(processor.dispose);
      await tester.pumpWidget(_view(processor));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_downward), findsNWidgets(3));
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text('Sample stage: Review'), findsOneWidget);
      expect(actions.single.context, {'selected': 2});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sample estimate refuses out-of-range values without overflow', (
    tester,
  ) async {
    narrow(tester);
    final processor = _processor(
      'EstimateForm',
      {'units': 21, 'rate': 10, 'total': 0},
      {
        'units': {'@path': '/units'},
        'rate': {'@path': '/rate'},
        'total': {'@path': '/total'},
        'onCalculate': {
          'event': {'name': 'calculate_sample'},
        },
      },
    );
    addTearDown(processor.dispose);
    await tester.pumpWidget(_view(processor));
    await tester.pumpAndSettle();
    expect(find.text('Invalid sample estimate'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
