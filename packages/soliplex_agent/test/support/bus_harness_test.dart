import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/testing.dart';
import 'package:test/test.dart';

/// Minimal `SessionExtension` used to smoke-test the harness itself.
///
/// Declares one LLM tool and one host function, both writing the
/// same path with the same tag so a Layer-B test can assert path
/// parity. Mirrors the shape of `NarrationPlugin` / `MapPlugin`
/// without their domain types.
class _CounterPlugin extends SessionExtension {
  SessionContext? _ctx;

  @override
  String get namespace => 'counter';

  @override
  Future<void> onAttach(AgentSession session) async {}

  @override
  Future<void> onAttachWithContext(SessionContext ctx) async {
    _ctx = ctx;
    await onAttach(ctx.session);
  }

  @override
  void onDispose() {
    _ctx = null;
  }

  @override
  List<ClientTool> get tools => [
        ClientTool.simple(
          name: 'bump',
          description: 'increment counter',
          parameters: const {
            'type': 'object',
            'properties': {
              'by': {'type': 'integer'},
            },
          },
          executor: (toolCall, _) async {
            final ctx = _ctx;
            if (ctx == null) return 'bump: not attached';
            ctx.bus.update(
              (current) {
                final next = Map<String, dynamic>.from(current);
                final n = (next['n'] as int?) ?? 0;
                next['n'] = n + 1;
                return next;
              },
              tag: 'counter.bump',
            );
            return 'ok';
          },
        ),
      ];

  @override
  List<HostFunction> get hostFunctions => [
        HostFunction(
          schema: const HostFunctionSchema(name: 'bump'),
          handler: (args, ctx) async {
            ctx.bus.update(
              (current) {
                final next = Map<String, dynamic>.from(current);
                final n = (next['n'] as int?) ?? 0;
                next['n'] = n + 1;
                return next;
              },
              tag: 'counter.bump',
            );
            return null;
          },
        ),
      ];
}

void main() {
  group('BusHarness — basic surface', () {
    test('starts with empty state and no writes', () {
      final harness = BusHarness();
      expect(harness.state, isEmpty);
      expect(harness.writes, isEmpty);
      harness.dispose();
    });

    test('seeds state from constructor', () {
      final harness = BusHarness(initialState: const {'a': 1});
      expect(harness.state, equals({'a': 1}));
      // initialAgentState seed does not fire the observer.
      expect(harness.writes, isEmpty);
      harness.dispose();
    });

    test('captures every write in writes log', () {
      final harness = BusHarness()
        ..bus.setAgentState(const {'a': 1}, tag: 'first')
        ..bus.setAgentState(const {'a': 2});

      expect(harness.writes, hasLength(2));
      expect(harness.writes[0].tag, 'first');
      expect(harness.writes[1].tag, isNull);
      harness.dispose();
    });

    test('dispose is idempotent', () {
      // Second call must not throw.
      BusHarness()
        ..dispose()
        ..dispose();
    });
  });

  group('BusHarness — host function invocation', () {
    test('attaches plugin then runs the named host function', () async {
      final harness = BusHarness();

      await harness.invokeHostFunction(_CounterPlugin(), name: 'bump');

      expect(harness.state, equals({'n': 1}));
      expect(harness.writes, hasLength(1));
      expect(harness.writes.single.tag, 'counter.bump');
      harness.dispose();
    });

    test('throws ArgumentError for unknown host function name', () {
      final harness = BusHarness();
      expect(
        () => harness.invokeHostFunction(_CounterPlugin(), name: 'nope'),
        throwsA(isA<ArgumentError>()),
      );
      harness.dispose();
    });
  });

  group('BusHarness — client tool invocation', () {
    test('attaches plugin then runs the named tool with JSON args', () async {
      final harness = BusHarness();

      final result = await harness.invokeClientTool(
        _CounterPlugin(),
        name: 'bump',
        args: const {'by': 3},
      );

      expect(result, 'ok');
      expect(harness.state, equals({'n': 1}));
      expect(harness.writes.single.tag, 'counter.bump');
      harness.dispose();
    });

    test('throws ArgumentError for unknown tool name', () {
      final harness = BusHarness();
      expect(
        () => harness.invokeClientTool(_CounterPlugin(), name: 'missing'),
        throwsA(isA<ArgumentError>()),
      );
      harness.dispose();
    });
  });

  group('BusHarness — same-args-same-bus invariant smoke', () {
    test('LLM tool path and host function path produce identical state',
        () async {
      // Tool path
      final viaTool = BusHarness();
      await viaTool.invokeClientTool(_CounterPlugin(), name: 'bump');
      final toolState = Map<String, dynamic>.from(viaTool.state);
      viaTool.dispose();

      // Host function path
      final viaHost = BusHarness();
      await viaHost.invokeHostFunction(_CounterPlugin(), name: 'bump');
      final hostState = Map<String, dynamic>.from(viaHost.state);
      viaHost.dispose();

      expect(toolState, equals(hostState));
    });
  });

  group('BusHarness — session/runtime stubs', () {
    test('ctx exposes non-null session/runtime references', () {
      // Plugins like NarrationPlugin forward `ctx.session` to
      // `onAttach(session)` during attach. The references must be
      // non-null even though their methods throw.
      final harness = BusHarness();
      final ctx = harness.context();
      expect(ctx.session, isNotNull);
      expect(ctx.runtime, isNotNull);
      harness.dispose();
    });
  });
}
