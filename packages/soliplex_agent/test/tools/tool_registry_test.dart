import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

import '../helpers/fake_tool_execution_context.dart';

/// Inline test tool — no demo tool shipped in the package.
ClientTool _testTool({
  String name = 'test_tool',
  String description = 'A test tool',
  ToolExecutor? executor,
}) {
  return ClientTool(
    definition: Tool(name: name, description: description),
    executor: executor ?? (_, __) async => 'test result',
  );
}

void main() {
  final ctx = FakeToolExecutionContext();

  group('ToolRegistry', () {
    test('register adds tool to registry', () {
      const registry = ToolRegistry();
      final updated = registry.register(_testTool());

      expect(updated.contains('test_tool'), isTrue);
      expect(updated.length, 1);
    });

    test('register returns new registry (immutable)', () {
      const registry = ToolRegistry();
      final updated = registry.register(_testTool());

      expect(registry.isEmpty, isTrue);
      expect(updated.isEmpty, isFalse);
    });

    test('lookup returns tool by name', () {
      final registry = const ToolRegistry().register(_testTool());

      final tool = registry.lookup('test_tool');

      expect(tool.definition.name, 'test_tool');
    });

    test('lookup throws StateError for unknown tool', () {
      const registry = ToolRegistry();

      expect(() => registry.lookup('nonexistent'), throwsA(isA<StateError>()));
    });

    test('execute runs the tool executor', () async {
      final registry = const ToolRegistry().register(
        _testTool(executor: (_, __) async => 'hello from tool'),
      );
      const toolCall = ToolCallInfo(id: 'tc-1', name: 'test_tool');

      final result = await registry.execute(toolCall, ctx);

      expect(result, 'hello from tool');
    });

    test('execute with failing executor propagates exception', () async {
      final registry = const ToolRegistry().register(
        _testTool(executor: (_, __) async => throw Exception('boom')),
      );
      const toolCall = ToolCallInfo(id: 'tc-1', name: 'test_tool');

      expect(() => registry.execute(toolCall, ctx), throwsA(isA<Exception>()));
    });

    test('toolDefinitions returns ag_ui Tool list', () {
      final registry = const ToolRegistry()
          .register(_testTool(name: 'tool_a', description: 'A'))
          .register(_testTool(name: 'tool_b', description: 'B'));

      final definitions = registry.toolDefinitions;

      expect(definitions, hasLength(2));
      expect(definitions.map((t) => t.name), containsAll(['tool_a', 'tool_b']));
    });

    group('unregister', () {
      test('removes canonical tool', () {
        final registry = const ToolRegistry()
            .register(_testTool(name: 'a'))
            .register(_testTool(name: 'b'));

        final updated = registry.unregister('a');

        expect(updated.contains('a'), isFalse);
        expect(updated.contains('b'), isTrue);
        expect(updated.length, 1);
      });

      test('removes alias without removing canonical tool', () {
        final registry = const ToolRegistry()
            .register(_testTool(name: 'canonical'))
            .alias('short', 'canonical');

        final updated = registry.unregister('short');

        expect(updated.contains('short'), isFalse);
        expect(updated.contains('canonical'), isTrue);
      });

      test('removes canonical tool and its aliases', () {
        final registry = const ToolRegistry()
            .register(_testTool(name: 'canonical'))
            .alias('short', 'canonical');

        final updated = registry.unregister('canonical');

        expect(updated.contains('canonical'), isFalse);
        expect(updated.contains('short'), isFalse);
        expect(updated.isEmpty, isTrue);
      });

      test('returns new registry (immutable)', () {
        final registry = const ToolRegistry().register(_testTool(name: 'a'));

        final updated = registry.unregister('a');

        expect(registry.contains('a'), isTrue);
        expect(updated.contains('a'), isFalse);
      });

      test('no-op for unknown name', () {
        final registry = const ToolRegistry().register(_testTool(name: 'a'));

        final updated = registry.unregister('nonexistent');

        expect(updated.length, 1);
        expect(updated.contains('a'), isTrue);
      });
    });

    test('execute passes context to executor', () async {
      ToolExecutionContext? receivedCtx;
      final registry = const ToolRegistry().register(
        _testTool(
          executor: (toolCall, context) async {
            receivedCtx = context;
            return 'ok';
          },
        ),
      );
      const toolCall = ToolCallInfo(id: 'tc-1', name: 'test_tool');

      await registry.execute(toolCall, ctx);

      expect(receivedCtx, same(ctx));
    });
  });

  group('ToolRegistry observer', () {
    test('fires after successful execute with name + args + result', () async {
      final calls = <ToolInvocationEvent>[];
      final registry = const ToolRegistry()
          .register(_testTool(executor: (_, __) async => 'rv'))
          .withObserver(calls.add);

      final result = await registry.execute(
        const ToolCallInfo(
          id: 'call-1',
          name: 'test_tool',
          arguments: '{"a":1}',
        ),
        ctx,
      );

      expect(result, 'rv');
      expect(calls, hasLength(1));
      expect(calls.single.toolName, 'test_tool');
      expect(calls.single.toolCallId, 'call-1');
      expect(calls.single.arguments, '{"a":1}');
      expect(calls.single.result, 'rv');
      expect(calls.single.error, isNull);
      expect(calls.single.duration, isA<Duration>());
    });

    test('fires after executor throws and re-throws the error', () async {
      final calls = <ToolInvocationEvent>[];
      final registry = const ToolRegistry()
          .register(
            _testTool(
              executor: (_, __) async => throw StateError('boom'),
            ),
          )
          .withObserver(calls.add);

      await expectLater(
        () => registry.execute(
          const ToolCallInfo(id: 'call-2', name: 'test_tool'),
          ctx,
        ),
        throwsA(isA<StateError>()),
      );

      expect(calls, hasLength(1));
      expect(calls.single.error, isA<StateError>());
      expect(calls.single.result, isNull);
    });

    test('observer is preserved across register / alias / unregister',
        () async {
      final calls = <ToolInvocationEvent>[];
      final registry = const ToolRegistry()
          .withObserver(calls.add)
          .register(_testTool(name: 'first'))
          .alias('shortname', 'first')
          .register(_testTool(name: 'second'));

      await registry.execute(
        const ToolCallInfo(id: 'c', name: 'shortname'),
        ctx,
      );

      expect(calls, hasLength(1));
      expect(calls.single.toolName, 'first');
    });

    test('withObserver(null) removes the observer', () async {
      final calls = <ToolInvocationEvent>[];
      final registry = const ToolRegistry()
          .register(_testTool())
          .withObserver(calls.add)
          .withObserver(null);

      await registry.execute(
        const ToolCallInfo(id: 'c', name: 'test_tool'),
        ctx,
      );

      expect(calls, isEmpty);
    });
  });
}
