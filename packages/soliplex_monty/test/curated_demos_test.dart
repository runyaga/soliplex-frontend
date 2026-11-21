@TestOn('vm')
library;

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/basic_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_monty/src/python_ui.dart';

import 'support/monty.dart';
import 'support/showcase_checks.dart';

void main() {
  for (final name in showcaseNames) {
    testWidgets(
      '$name checks, runs, handles events and renders in real Monty',
      (tester) async {
        tester.view
          ..physicalSize = const Size(1200, 3000)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final surfaces = <StagedSurface>[];
        await tester.runAsync(
          () => checkShowcase(name, onSurface: surfaces.add),
        );
        var charts = 0;
        for (final staged in surfaces) {
          final chartNodes = staged.components.where(
            (node) => node['component'] == 'Chart',
          );
          final processor = MessageProcessor<ComponentImplementation>(
            catalogs: [basicCatalog(), chartGraphicsCatalog()],
            validationConfig: ValidationConfig.strict,
          );
          try {
            processor.processMessages(staged.messages('demo'));
            await tester.pumpWidget(
              MaterialApp(
                theme: soliplexLightTheme(),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: A2uiSurface(
                      key: ObjectKey(processor),
                      surface: processor.model.allSurfaces.single,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            for (final node in chartNodes) {
              charts++;
              expect(staged.components.first['component'], isNot('Chart'));
              final kind = (node['spec']! as Map)['kind'];
              final plot = kind == 'line' ? 'LineChart' : 'BarChart';
              expect(
                find.byWidgetPredicate((w) => w.runtimeType.toString() == plot),
                findsWidgets,
              );
            }
            expect(find.textContaining('Invalid chart'), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          } finally {
            processor.dispose();
          }
        }
        if ([
          'incident_flight_recorder',
          'survey_results',
          'sales_pipeline',
          'hot_patch',
          'reproducer',
          'healing_pipeline',
          'monty_gui',
        ].contains(name)) {
          expect(
            charts,
            greaterThan(0),
            reason: '$name must render its charts',
          );
        }
      },
      skip: skipWithoutMonty != false,
    );
  }
}
