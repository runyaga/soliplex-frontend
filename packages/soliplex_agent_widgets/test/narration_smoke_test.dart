// End-to-end smoke test for the reactive-bus redesign — narration path.
//
// Demonstrates that an LLM-style write to the per-thread StateBus
// flows through NarrationProjection → NarrationController._entries
// → typed `Narration` list, with no AgentSession or AgentRuntime
// mocking required. Run with:
//
//   flutter test packages/soliplex_agent_widgets/test/narration_smoke_test.dart
//
// Plan reference: docs/plans/reactive-bus-redesign.md (Phase 1 step 4b).

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent_widgets/soliplex_agent_widgets.dart';
import 'package:soliplex_client/soliplex_client.dart';

void main() {
  group('reactive-bus redesign smoke — narration', () {
    late StateBus bus;
    late NarrationController controller;
    late void Function() unwire;

    setUp(() {
      bus = StateBus();
      controller = NarrationController();
      // Wire the controller's stable `_entries` signal to a
      // NarrationProjection over the bus.
      final projection =
          bus.project<List<Narration>>(const NarrationProjection());
      controller.wireProjection(projection);
      unwire = controller.unwireProjection;
    });

    tearDown(() {
      unwire();
      controller.dispose();
      bus.dispose();
    });

    test('bus write → projection → controller signal', () {
      // Initial state: no narrations on the bus, controller is empty.
      expect(controller.entries.value, isEmpty);

      // Simulate what NarrationPlugin's `narrate_say` executor does
      // when the LLM calls it — a bus.update appending an entry
      // to /ui/narrations.
      bus.update((current) {
        return {
          'ui': {
            'narrations': [
              {'actor': 'coordinator', 'text': 'Mission begins.'},
            ],
          },
        };
      });

      // The controller's signal now contains a typed Narration.
      final entries = controller.entries.value;
      expect(entries, hasLength(1));
      expect(entries.first.actor, NarrationActor.coordinator);
      expect(entries.first.text, 'Mission begins.');
    });

    test('append-then-replace updates flow through reactively', () {
      // Two appends.
      bus.setAgentState({
        'ui': {
          'narrations': [
            {'actor': 'coordinator', 'text': 'First.'},
            {'actor': 'primary', 'text': 'Second.'},
          ],
        },
      });
      expect(controller.entries.value, hasLength(2));
      expect(controller.entries.value[0].actor, NarrationActor.coordinator);
      expect(controller.entries.value[1].actor, NarrationActor.primary);

      // Replace state — clear narrations.
      bus.setAgentState(const {
        'ui': <String, dynamic>{'narrations': []}
      });
      expect(controller.entries.value, isEmpty);
    });

    test('partial / unknown actor falls back gracefully', () {
      bus.setAgentState({
        'ui': {
          'narrations': [
            {'actor': 'who_knows', 'text': 'Garbage actor.'},
          ],
        },
      });
      // NarrationActor.parse falls back to `primary` for unknown
      // values — projection-side defensiveness against schema drift.
      expect(controller.entries.value, hasLength(1));
      expect(controller.entries.value.first.actor, NarrationActor.primary);
    });
  });
}
