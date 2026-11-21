// No Monty worker: these checks also run on Chrome's JavaScript integers.
import 'package:dart_monty/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

final _modules = Expando<ExternalModule>();

Future<Object?> call(
  PythonUiArena arena,
  String name, [
  List<Object?> args = const [],
]) async {
  final module = _modules[arena] ??= PythonUiArena.moduleFor(() => arena);
  final fn = module.attrs[name]! as MontyHostFunction;
  return (await fn.fn([
    for (final arg in args) MontyValue.fromDart(arg),
  ], {})).dartValue;
}

Future<String> raised(Future<Object?> Function() body) async {
  try {
    await body();
  } on ExternalException catch (error) {
    return '${error.excType}: ${error.message}';
  }
  fail('no ExternalException');
}

Future<Object?> sharedTree(PythonUiArena arena, int levels) async {
  var node = await call(arena, 'Text', ['leaf']);
  for (var i = 0; i < levels; i++) {
    node = await call(arena, 'Column', [
      [node, node],
    ]);
  }
  return node;
}

Future<void> showMany(PythonUiArena arena, int count) async {
  final children = <Object?>[];
  for (var i = 0; i < count; i++) {
    children.add(await call(arena, 'Text', ['$i']));
  }
  final root = await call(arena, 'List', [children]);
  await call(arena, 'show', [root]);
}

void main() {
  test('default limit rejects 65,535 renders from 16 components', () async {
    final arena = PythonUiArena();
    final node = await sharedTree(arena, 15);
    expect(
      await raised(() => call(arena, 'show', [node])),
      'ValueError: Surface renders 65535 components, exceeding the limit of '
      '20000. Show fewer rows (page or filter the data).',
    );
    expect(arena.staged, isNull);
  });

  test('unshown components do not consume the rendered limit', () async {
    final arena = PythonUiArena();
    for (var i = 0; i < 20001; i++) {
      await call(arena, 'Text', ['$i']);
    }
    final root = await call(arena, 'Text', ['shown']);
    await call(arena, 'show', [root]);
    expect(arena.staged!.components, hasLength(1));
  });

  test('default capacity accepts exactly 20,000 rendered components', () async {
    final arena = PythonUiArena();
    await showMany(arena, 19999);
    expect(arena.staged!.rendered, 20000);
  });

  test('default capacity rejects 20,001 rendered components', () async {
    final arena = PythonUiArena();
    expect(
      await raised(() async => showMany(arena, 20000)),
      contains(
        'Surface renders 20001 components, exceeding the limit of 20000',
      ),
    );
  });

  test('a configurable limit accepts its exact boundary', () async {
    final arena = PythonUiArena(maxNodes: 1000, warnNodes: null);
    await showMany(arena, 999);
    expect(arena.staged!.rendered, 1000);
    expect(arena.warnings, isEmpty);
  });

  test('a subtree shared by two parents counts twice', () async {
    final arena = PythonUiArena(maxNodes: 9, warnNodes: null);
    final subtree = await sharedTree(arena, 1);
    final left = await call(arena, 'Card', [subtree]);
    final right = await call(arena, 'Column', [
      [subtree],
    ]);
    final root = await call(arena, 'Row', [
      [left, right],
    ]);
    await call(arena, 'show', [root]);
    expect(arena.staged!.components, hasLength(5));
    expect(arena.staged!.rendered, 9);
  });

  test('a repeated child counts each reference', () async {
    final arena = PythonUiArena(maxNodes: 10);
    final text = await call(arena, 'Text', ['again']);
    final root = await call(arena, 'Column', [
      [for (var i = 0; i < 10; i++) text],
    ]);
    expect(await raised(() => call(arena, 'show', [root])), contains('11'));
  });

  test('an unshown exponentially shared tree does not count', () async {
    final arena = PythonUiArena(maxNodes: 10, warnNodes: null);
    await sharedTree(arena, 40);
    await showMany(arena, 1);
    expect(arena.staged!.rendered, 2);
  });

  test('null limits allow more than the old construction ceiling', () async {
    final arena = PythonUiArena(maxNodes: null, warnNodes: null);
    await showMany(arena, 20000);
    expect(arena.staged!.rendered, 20001);
    final root = await sharedTree(arena, 15);
    await call(arena, 'show', [root]);
    expect(arena.staged!.rendered, 65535);
    expect(arena.warnings, isEmpty);
  });

  test('construction stops at ten times the configured limit', () async {
    final arena = PythonUiArena(maxNodes: 1);
    for (var i = 0; i < 10; i++) {
      await call(arena, 'Text', ['$i']);
    }
    expect(
      await raised(() => call(arena, 'Text', ['too many'])),
      'ValueError: Construction stopped at 10 components '
      '(ten times the node limit of 1).',
    );
  });

  test('warning threshold is strict and warnings are unmodifiable', () async {
    final arena = PythonUiArena(maxNodes: 4, warnNodes: 2);
    await showMany(arena, 1);
    expect(arena.warnings, isEmpty);
    await showMany(arena, 2);
    expect(arena.staged!.rendered, 3);
    expect(arena.warnings, [
      'Surface renders 3 components (warning at 2). Page or filter long lists.',
    ]);
    expect(() => arena.warnings.add('changed'), throwsUnsupportedError);
  });

  test('default warning is 15,000 and does not reject the surface', () async {
    final arena = PythonUiArena();
    await showMany(arena, 15000);
    expect(arena.staged!.rendered, 15001);
    expect(arena.warnings.single, contains('warning at 15000'));
  });

  test('null maximum still permits a warning threshold', () async {
    final arena = PythonUiArena(maxNodes: null, warnNodes: 2);
    await showMany(arena, 2);
    expect(arena.warnings, hasLength(1));
  });

  test(
    'a rejected show preserves the last surface and adds no warning',
    () async {
      final arena = PythonUiArena(maxNodes: 2, warnNodes: 1);
      final root = await call(arena, 'Text', ['kept']);
      await call(arena, 'show', [root]);
      final kept = arena.staged;
      expect(
        await raised(() async => showMany(arena, 2)),
        contains('limit of 2'),
      );
      expect(arena.staged, same(kept));
      expect(arena.warnings, isEmpty);
    },
  );

  test('rendered count saturates at one billion on VM and dart2js', () async {
    final arena = PythonUiArena(maxNodes: null, warnNodes: null);
    final root = await sharedTree(arena, 60);
    await call(arena, 'show', [root]);
    expect(arena.staged!.components, hasLength(61));
    expect(arena.staged!.rendered, 1000000000);
  });

  test('the largest valid limit still rejects a saturated count', () async {
    final arena = PythonUiArena(maxNodes: 999999999, warnNodes: null);
    final root = await sharedTree(arena, 60);
    expect(
      await raised(() => call(arena, 'show', [root])),
      contains(
        'Surface renders 1000000000 components, exceeding the limit of '
        '999999999',
      ),
    );
  });

  for (final invalid in [-1, 0, 1000000000, 1000000001]) {
    test('rejects maxNodes $invalid', () {
      expect(() => PythonUiArena(maxNodes: invalid), throwsArgumentError);
    });
    test('rejects warnNodes $invalid', () {
      expect(() => PythonUiArena(warnNodes: invalid), throwsArgumentError);
    });
  }

  test('accepts both valid configuration endpoints', () {
    expect(PythonUiArena(maxNodes: 1, warnNodes: 999999999), isNotNull);
    expect(PythonUiArena(maxNodes: 999999999, warnNodes: 1), isNotNull);
  });
}
