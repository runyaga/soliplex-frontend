/// Layer-C surface (Tier 1 Step 7): pump a real `NarrationPanel`,
/// drive a write through the `BusHarness`, assert the rendered text
/// appears on the canvas.
///
/// Sits between the package's existing `narration_smoke_test.dart`
/// (Layer-B-ish: bus + projection + controller, no widget pump) and a
/// future `integration_test/` (real device / browser binding). When
/// the team wants the formal integration-test pipeline, this file
/// graduates by:
///
/// 1. Moving to `integration_test/narration_panel_renders_test.dart`.
/// 2. Adding `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`.
/// 3. Adding the `integration_test` package as a dev_dependency.
///
/// The body of the test stays the same — `testWidgets` works in both
/// places.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/testing.dart' show BusHarness;
import 'package:soliplex_agent_widgets/soliplex_agent_widgets.dart';

void main() {
  // The narration panel reads the app-singleton `narrationController`,
  // so each test must reset it to a clean state.
  setUp(() {
    narrationController
      ..unwireProjection()
      ..clear();
  });

  testWidgets(
    'narrate_say writes the bus → projection → panel rebuild',
    (tester) async {
      final harness = BusHarness();
      try {
        // Wire the bus's narration projection into the singleton
        // controller. This is the same wiring `lib/src/flavors/`
        // performs at app boot.
        final projected = harness.bus.project(const NarrationProjection());
        narrationController.wireProjection(projected);
        addTearDown(() => narrationController.unwireProjection());

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: NarrationPanel())),
        );
        // Initial render: no entries.
        expect(
            find.textContaining('Hello bus', findRichText: true), findsNothing);

        // Drive a write through NarrationPlugin's host function path
        // (same code path Python and the bridge use).
        await harness.invokeHostFunction(
          NarrationPlugin(),
          name: 'narrate_say',
          args: const {'text': 'Hello bus', 'actor': 'coordinator'},
        );

        // Pump a frame so the signal-driven rebuild flushes.
        await tester.pumpAndSettle();

        // The panel should now contain the entry.
        expect(find.textContaining('Hello bus', findRichText: true),
            findsOneWidget);
      } finally {
        harness.dispose();
      }
    },
  );

  testWidgets(
    'narrate_clear empties the panel',
    (tester) async {
      final harness = BusHarness();
      try {
        final projected = harness.bus.project(const NarrationProjection());
        narrationController.wireProjection(projected);
        addTearDown(() => narrationController.unwireProjection());

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: NarrationPanel())),
        );

        // Seed two entries.
        await harness.invokeHostFunction(
          NarrationPlugin(),
          name: 'narrate_say',
          args: const {'text': 'first'},
        );
        await harness.invokeHostFunction(
          NarrationPlugin(),
          name: 'narrate_say',
          args: const {'text': 'second'},
        );
        await tester.pumpAndSettle();
        expect(
            find.textContaining('first', findRichText: true), findsOneWidget);
        expect(
            find.textContaining('second', findRichText: true), findsOneWidget);

        // Clear via the host-only function.
        await harness.invokeHostFunction(
          NarrationPlugin(),
          name: 'narrate_clear',
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('first', findRichText: true), findsNothing);
        expect(find.textContaining('second', findRichText: true), findsNothing);
      } finally {
        harness.dispose();
      }
    },
  );

  testWidgets(
    'LLM tool path renders identically to host-function path',
    (tester) async {
      final harness = BusHarness();
      try {
        final projected = harness.bus.project(const NarrationProjection());
        narrationController.wireProjection(projected);
        addTearDown(() => narrationController.unwireProjection());

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: NarrationPanel())),
        );

        // Tool path.
        await harness.invokeClientTool(
          NarrationPlugin(),
          name: 'narrate_say',
          args: const {'text': 'via tool', 'actor': 'field'},
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('via tool', findRichText: true),
            findsOneWidget);

        // Host function path adds another with the same shape.
        await harness.invokeHostFunction(
          NarrationPlugin(),
          name: 'narrate_say',
          args: const {'text': 'via host', 'actor': 'field'},
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('via tool', findRichText: true),
            findsOneWidget);
        expect(find.textContaining('via host', findRichText: true),
            findsOneWidget);
      } finally {
        harness.dispose();
      }
    },
  );
}
