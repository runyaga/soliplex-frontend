import 'package:dart_monty/dart_monty.dart' as dm;
import 'package:dart_monty/dart_monty_bridge.dart'
    show HostFunction, HostFunctionSchema;
import 'package:mocktail/mocktail.dart';
import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_monty_plugin/soliplex_monty_plugin.dart';
import 'package:test/test.dart';

class MockAgentSession extends Mock implements dm.AgentSession {}

class MockScriptEnvironment extends Mock implements ScriptEnvironment {}

void main() {
  // ---------------------------------------------------------------------------
  // ToolAcl
  // ---------------------------------------------------------------------------

  group('ToolAcl', () {
    late ToolAcl acl;

    setUp(() => acl = ToolAcl());

    test('empty by default — all tools allowed', () {
      expect(acl.list(), isEmpty);
      expect(acl.isAllowed('any_tool'), isTrue);
    });

    test('initial denied set is respected', () {
      final a = ToolAcl(denied: {'foo', 'bar'});
      expect(a.list(), ['bar', 'foo']); // sorted
      expect(a.isAllowed('foo'), isFalse);
      expect(a.isAllowed('bar'), isFalse);
      expect(a.isAllowed('baz'), isTrue);
    });

    group('deny', () {
      test('adds name to denied set', () {
        acl.deny('tool_a');
        expect(acl.list(), ['tool_a']);
        expect(acl.isAllowed('tool_a'), isFalse);
      });

      test('is idempotent — denying twice does not duplicate', () {
        acl.deny('tool_a');
        final snapBefore = acl.denied.value;
        acl.deny('tool_a');
        expect(acl.list(), ['tool_a']);
        // signal value identity unchanged on no-op
        expect(identical(acl.denied.value, snapBefore), isTrue);
      });

      test('does not affect other tools', () {
        acl.deny('tool_a');
        expect(acl.isAllowed('tool_b'), isTrue);
      });
    });

    group('allow', () {
      test('removes name from denied set', () {
        acl
          ..deny('tool_a')
          ..allow('tool_a');
        expect(acl.list(), isEmpty);
        expect(acl.isAllowed('tool_a'), isTrue);
      });

      test('is idempotent — allowing a non-denied tool is a no-op', () {
        final snapBefore = acl.denied.value;
        acl.allow('tool_a');
        expect(acl.list(), isEmpty);
        expect(identical(acl.denied.value, snapBefore), isTrue);
      });

      test('only removes the specified name', () {
        acl
          ..deny('tool_a')
          ..deny('tool_b')
          ..allow('tool_a');
        expect(acl.list(), ['tool_b']);
      });
    });

    group('reset', () {
      test('clears all denials', () {
        acl
          ..deny('tool_a')
          ..deny('tool_b')
          ..reset();
        expect(acl.list(), isEmpty);
        expect(acl.isAllowed('tool_a'), isTrue);
        expect(acl.isAllowed('tool_b'), isTrue);
      });

      test('is a no-op on empty ACL', () {
        acl.reset();
        expect(acl.list(), isEmpty);
      });
    });

    group('list', () {
      test('returns names in sorted order', () {
        acl
          ..deny('zeta')
          ..deny('alpha')
          ..deny('mu');
        expect(acl.list(), ['alpha', 'mu', 'zeta']);
      });

      test('returns a copy — mutations do not affect the ACL', () {
        acl.deny('tool_a');
        // Mutate the returned list; the ACL's internal state must not change.
        final listed = acl.list()..add('tool_b');
        expect(listed, ['tool_a', 'tool_b']); // copy was mutated
        expect(acl.list(), ['tool_a']); // original not contaminated
      });
    });

    group('signal reactivity', () {
      test('denied signal updates on deny', () {
        var callCount = 0;
        final dispose = effect(() {
          acl.denied.value; // subscribe
          callCount++;
        });
        final before = callCount;
        acl.deny('tool_a');
        expect(callCount, greaterThan(before));
        dispose();
      });

      test('denied signal updates on allow', () {
        acl.deny('tool_a');
        var callCount = 0;
        final dispose = effect(() {
          acl.denied.value;
          callCount++;
        });
        final before = callCount;
        acl.allow('tool_a');
        expect(callCount, greaterThan(before));
        dispose();
      });

      test('no signal update on idempotent deny', () {
        acl.deny('tool_a');
        var callCount = 0;
        final dispose = effect(() {
          acl.denied.value;
          callCount++;
        });
        final before = callCount;
        acl.deny('tool_a'); // no-op
        expect(callCount, equals(before));
        dispose();
      });
    });

    group('toString', () {
      test('shows "none denied" when empty', () {
        expect(acl.toString(), 'ToolAcl(none denied)');
      });

      test('shows sorted denied names', () {
        acl
          ..deny('zeta')
          ..deny('alpha');
        expect(acl.toString(), 'ToolAcl(denied: alpha, zeta)');
      });
    });
  });

  // ---------------------------------------------------------------------------
  // ToolFilteredEnvironment.acl
  // ---------------------------------------------------------------------------

  group('ToolFilteredEnvironment.acl', () {
    late ToolAcl acl;
    late MockScriptEnvironment inner;
    late ToolFilteredEnvironment filtered;

    ClientTool makeTool(String name) => ClientTool(
          definition: Tool(
            name: name,
            description: 'test',
            parameters: const <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{},
            },
          ),
          executor: (_, __) async => 'ok',
        );

    setUp(() {
      acl = ToolAcl();
      inner = MockScriptEnvironment();
      filtered = ToolFilteredEnvironment.acl(inner, acl);
      when(() => inner.tools).thenReturn([
        makeTool('tool_a'),
        makeTool('tool_b'),
        makeTool('tool_c'),
      ]);
      when(() => inner.scriptingState)
          .thenReturn(signal(ScriptingState.idle).readonly());
    });

    test('exposes all tools when ACL is empty', () {
      expect(
        filtered.tools.map((t) => t.definition.name),
        ['tool_a', 'tool_b', 'tool_c'],
      );
    });

    test('hides denied tool', () {
      acl.deny('tool_b');
      final names = filtered.tools.map((t) => t.definition.name);
      expect(names, containsAll(['tool_a', 'tool_c']));
      expect(names, isNot(contains('tool_b')));
    });

    test('reflects allow — tool returns after denial is lifted', () {
      acl.deny('tool_b');
      expect(
        filtered.tools.map((t) => t.definition.name),
        isNot(contains('tool_b')),
      );
      acl.allow('tool_b');
      expect(
        filtered.tools.map((t) => t.definition.name),
        contains('tool_b'),
      );
    });

    test('reset restores all tools', () {
      acl
        ..deny('tool_a')
        ..deny('tool_c')
        ..reset();
      expect(filtered.tools, hasLength(3));
    });

    test('re-evaluates predicate on every tools read', () {
      acl.deny('tool_a');
      expect(filtered.tools, hasLength(2));
      acl.deny('tool_b');
      expect(filtered.tools, hasLength(1));
      acl.reset();
      expect(filtered.tools, hasLength(3));
    });

    test('inner exposes the wrapped environment', () {
      expect(filtered.inner, same(inner));
    });
  });

  // ---------------------------------------------------------------------------
  // MontyScriptEnvironment + ToolAcl host function registration
  // ---------------------------------------------------------------------------

  group('MontyScriptEnvironment ACL host functions', () {
    late MockAgentSession session;
    late ToolAcl acl;
    final registered = <HostFunction>[];

    setUpAll(() {
      registerFallbackValue(
        HostFunction(
          schema: const HostFunctionSchema(name: '_fallback', description: ''),
          handler: (_) async => null,
        ),
      );
    });

    setUp(() {
      registered.clear();
      session = MockAgentSession();
      acl = ToolAcl();
      when(() => session.schemas).thenReturn([]);
      when(() => session.register(any())).thenAnswer((inv) {
        registered.add(inv.positionalArguments[0] as HostFunction);
      });
    });

    MontyScriptEnvironment buildEnv() =>
        MontyScriptEnvironment.forTest(session, toolAcl: acl);

    HostFunction fn(String name) =>
        registered.firstWhere((f) => f.schema.name == name);

    test('registers acl_list, acl_deny, acl_allow, acl_reset', () {
      buildEnv();
      final names = registered.map((f) => f.schema.name).toSet();
      expect(
        names,
        containsAll(['acl_list', 'acl_deny', 'acl_allow', 'acl_reset']),
      );
    });

    test('no ACL functions registered without toolAcl', () {
      MontyScriptEnvironment.forTest(session);
      final names = registered.map((f) => f.schema.name).toSet();
      expect(names, isNot(contains('acl_list')));
    });

    group('acl_list handler', () {
      test('returns "none" when no tools are denied', () async {
        buildEnv();
        final result = await fn('acl_list').handler({});
        expect(result, 'none');
      });

      test('returns sorted denied names', () async {
        acl
          ..deny('zeta')
          ..deny('alpha');
        buildEnv();
        final result = await fn('acl_list').handler({});
        expect(result, 'alpha, zeta');
      });
    });

    group('acl_deny handler', () {
      test('denies named tool', () async {
        buildEnv();
        await fn('acl_deny').handler({'tool_name': 'my_tool'});
        expect(acl.isAllowed('my_tool'), isFalse);
      });

      test('is idempotent', () async {
        buildEnv();
        await fn('acl_deny').handler({'tool_name': 'my_tool'});
        await fn('acl_deny').handler({'tool_name': 'my_tool'});
        expect(acl.list(), ['my_tool']);
      });

      test('returns "OK"', () async {
        buildEnv();
        final result = await fn('acl_deny').handler({'tool_name': 'my_tool'});
        expect(result, 'OK');
      });
    });

    group('acl_allow handler', () {
      test('re-allows a denied tool', () async {
        acl.deny('my_tool');
        buildEnv();
        await fn('acl_allow').handler({'tool_name': 'my_tool'});
        expect(acl.isAllowed('my_tool'), isTrue);
      });

      test('returns "OK"', () async {
        buildEnv();
        final result = await fn('acl_allow').handler({'tool_name': 'my_tool'});
        expect(result, 'OK');
      });
    });

    group('acl_reset handler', () {
      test('clears all denied tools', () async {
        acl
          ..deny('tool_a')
          ..deny('tool_b');
        buildEnv();
        await fn('acl_reset').handler({});
        expect(acl.list(), isEmpty);
      });

      test('returns "OK"', () async {
        buildEnv();
        final result = await fn('acl_reset').handler({});
        expect(result, 'OK');
      });
    });

    test('acl_list reflects mutations made after env construction', () async {
      buildEnv();
      expect(await fn('acl_list').handler({}), 'none');
      acl.deny('late_tool');
      expect(await fn('acl_list').handler({}), 'late_tool');
      acl.reset();
      expect(await fn('acl_list').handler({}), 'none');
    });
  });
}
