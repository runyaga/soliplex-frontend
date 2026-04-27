import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent_widgets/src/narration_plugin.dart'
    show appendNarrationToBus, clearNarrationsOnBus;
import 'package:soliplex_client/soliplex_client.dart';

void main() {
  group('appendNarrationToBus', () {
    test('appends to empty state, creating /ui/narrations', () {
      final bus = StateBus();

      appendNarrationToBus(bus, actor: 'coordinator', text: 'first');

      final ui = bus.agentState.value['ui']! as Map<dynamic, dynamic>;
      final entries = ui['narrations']! as List;
      expect(entries, hasLength(1));
      final entry = entries.single as Map;
      expect(entry['actor'], 'coordinator');
      expect(entry['text'], 'first');
      bus.dispose();
    });

    test('appends to existing list, preserving order', () {
      final bus = StateBus(
        initialAgentState: {
          'ui': {
            'narrations': [
              {'actor': 'primary', 'text': 'one'},
            ],
          },
        },
      );

      appendNarrationToBus(bus, actor: 'field', text: 'two');

      final entries =
          (bus.agentState.value['ui']! as Map)['narrations']! as List;
      expect(entries, hasLength(2));
      expect((entries[0] as Map)['text'], 'one');
      expect((entries[1] as Map)['text'], 'two');
      bus.dispose();
    });

    test('preserves sibling /ui keys', () {
      final bus = StateBus(
        initialAgentState: {
          'ui': {
            'narrations': <dynamic>[],
            'hud': {'banner': 'standing by'},
          },
        },
      );

      appendNarrationToBus(bus, actor: 'coordinator', text: 'x');

      final ui = bus.agentState.value['ui']! as Map;
      expect(ui['hud'], equals({'banner': 'standing by'}));
      bus.dispose();
    });

    test('emits a write event tagged "narration.append"', () {
      final events = <BusWriteEvent>[];
      final bus = StateBus(observer: events.add);

      appendNarrationToBus(bus, actor: 'coordinator', text: 'hi');

      expect(events, hasLength(1));
      expect(events.single.tag, 'narration.append');
      expect(events.single.kind, BusWriteKind.update);
      bus.dispose();
    });
  });

  group('clearNarrationsOnBus', () {
    test('empties /ui/narrations', () {
      final bus = StateBus(
        initialAgentState: {
          'ui': {
            'narrations': [
              {'actor': 'primary', 'text': 'one'},
              {'actor': 'field', 'text': 'two'},
            ],
          },
        },
      );

      clearNarrationsOnBus(bus);

      final entries =
          (bus.agentState.value['ui']! as Map)['narrations']! as List;
      expect(entries, isEmpty);
      bus.dispose();
    });

    test('preserves sibling /ui keys', () {
      final bus = StateBus(
        initialAgentState: {
          'ui': {
            'narrations': [
              {'actor': 'primary', 'text': 'one'},
            ],
            'hud': {'banner': 'standing by'},
          },
        },
      );

      clearNarrationsOnBus(bus);

      final ui = bus.agentState.value['ui']! as Map;
      expect(ui['hud'], equals({'banner': 'standing by'}));
      bus.dispose();
    });

    test('is a no-op shape on empty state (creates empty list)', () {
      final bus = StateBus();

      clearNarrationsOnBus(bus);

      final ui = bus.agentState.value['ui']! as Map;
      expect(ui['narrations'], isEmpty);
      bus.dispose();
    });

    test('emits a write event tagged "narration.clear"', () {
      final events = <BusWriteEvent>[];
      final bus = StateBus(observer: events.add);

      clearNarrationsOnBus(bus);

      expect(events, hasLength(1));
      expect(events.single.tag, 'narration.clear');
      expect(events.single.kind, BusWriteKind.update);
      bus.dispose();
    });
  });
}
