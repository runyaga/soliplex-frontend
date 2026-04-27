import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/testing.dart';
import 'package:soliplex_agent_widgets/soliplex_agent_widgets.dart';

void main() {
  group('NarrationPlugin — LLM tool path (narrate_say)', () {
    test('writes /ui/narrations with the supplied actor and text', () async {
      final harness = BusHarness();
      try {
        final result = await harness.invokeClientTool(
          NarrationPlugin(),
          name: 'narrate_say',
          args: const {'text': 'hello', 'actor': 'coordinator'},
        );

        expect(result, 'ok');
        final entries = (harness.state['ui']! as Map)['narrations']! as List;
        expect(entries, hasLength(1));
        final entry = entries.single as Map;
        expect(entry['actor'], 'coordinator');
        expect(entry['text'], 'hello');
        expect(harness.writes.single.tag, 'narration.append');
      } finally {
        harness.dispose();
      }
    });

    test('empty text is rejected without writing the bus', () async {
      final harness = BusHarness();
      try {
        final result = await harness.invokeClientTool(
          NarrationPlugin(),
          name: 'narrate_say',
          args: const {'text': '   '},
        );

        expect(result, contains('empty text'));
        expect(harness.writes, isEmpty);
        expect(harness.state, isEmpty);
      } finally {
        harness.dispose();
      }
    });

    test('actor defaults to primary when omitted', () async {
      final harness = BusHarness();
      try {
        await harness.invokeClientTool(
          NarrationPlugin(),
          name: 'narrate_say',
          args: const {'text': 'no actor'},
        );

        final entry = ((harness.state['ui']! as Map)['narrations']! as List)
            .single as Map;
        expect(entry['actor'], 'primary');
      } finally {
        harness.dispose();
      }
    });

    test('actor aliases (hq, dispatch) parse to canonical buckets', () async {
      final harness = BusHarness();
      try {
        await harness.invokeClientTool(
          NarrationPlugin(),
          name: 'narrate_say',
          args: const {'text': 'a', 'actor': 'hq'},
        );
        await harness.invokeClientTool(
          NarrationPlugin(),
          name: 'narrate_say',
          args: const {'text': 'b', 'actor': 'dispatch'},
        );

        final entries = (harness.state['ui']! as Map)['narrations']! as List;
        // Both 'hq' and 'dispatch' map to coordinator.
        expect((entries[0] as Map)['actor'], 'coordinator');
        expect((entries[1] as Map)['actor'], 'coordinator');
      } finally {
        harness.dispose();
      }
    });
  });

  group('NarrationPlugin — host function path (narrate_say)', () {
    test('writes /ui/narrations identically to the LLM tool path', () async {
      final harness = BusHarness();
      try {
        final result = await harness.invokeHostFunction(
          NarrationPlugin(),
          name: 'narrate_say',
          args: const {'text': 'hello', 'actor': 'coordinator'},
        );

        expect(result, 'ok');
        final entry = ((harness.state['ui']! as Map)['narrations']! as List)
            .single as Map;
        expect(entry['actor'], 'coordinator');
        expect(entry['text'], 'hello');
        expect(harness.writes.single.tag, 'narration.append');
      } finally {
        harness.dispose();
      }
    });

    test('empty text rejected without writing', () async {
      final harness = BusHarness();
      try {
        final result = await harness.invokeHostFunction(
          NarrationPlugin(),
          name: 'narrate_say',
          args: const {'text': ''},
        );

        expect(result, contains('empty text'));
        expect(harness.writes, isEmpty);
      } finally {
        harness.dispose();
      }
    });
  });

  group('NarrationPlugin — narrate_clear (host-only)', () {
    test('empties /ui/narrations', () async {
      final harness = BusHarness(
        initialState: {
          'ui': {
            'narrations': [
              {'actor': 'primary', 'text': 'one'},
              {'actor': 'field', 'text': 'two'},
            ],
          },
        },
      );
      try {
        final result = await harness.invokeHostFunction(
          NarrationPlugin(),
          name: 'narrate_clear',
        );

        expect(result, isTrue);
        final entries = (harness.state['ui']! as Map)['narrations']! as List;
        expect(entries, isEmpty);
        expect(harness.writes.single.tag, 'narration.clear');
      } finally {
        harness.dispose();
      }
    });

    test('narrate_clear is not exposed as an LLM tool', () {
      // The plugin's `tools` list should not contain narrate_clear.
      // The LLM doesn't get to clear the log mid-conversation; only
      // Python scripts can.
      final plugin = NarrationPlugin();
      expect(
        plugin.tools.map((t) => t.definition.name),
        isNot(contains('narrate_clear')),
      );
      expect(
        plugin.hostFunctions.map((f) => f.schema.name),
        contains('narrate_clear'),
      );
    });
  });

  group('NarrationPlugin — same-args-same-bus invariant', () {
    test('LLM tool and host function produce identical bus state', () async {
      const args = {'text': 'shared', 'actor': 'field'};

      // Tool path.
      final viaTool = BusHarness();
      await viaTool.invokeClientTool(
        NarrationPlugin(),
        name: 'narrate_say',
        args: args,
      );
      final toolState = Map<String, dynamic>.from(viaTool.state);
      viaTool.dispose();

      // Host function path.
      final viaHost = BusHarness();
      await viaHost.invokeHostFunction(
        NarrationPlugin(),
        name: 'narrate_say',
        args: args,
      );
      final hostState = Map<String, dynamic>.from(viaHost.state);
      viaHost.dispose();

      expect(toolState, equals(hostState));
    });

    test('both paths emit the same write tag', () async {
      const args = {'text': 'x'};

      final viaTool = BusHarness();
      await viaTool.invokeClientTool(
        NarrationPlugin(),
        name: 'narrate_say',
        args: args,
      );
      final toolTag = viaTool.writes.single.tag;
      viaTool.dispose();

      final viaHost = BusHarness();
      await viaHost.invokeHostFunction(
        NarrationPlugin(),
        name: 'narrate_say',
        args: args,
      );
      final hostTag = viaHost.writes.single.tag;
      viaHost.dispose();

      expect(toolTag, 'narration.append');
      expect(toolTag, equals(hostTag));
    });
  });
}
