@TestOn('vm')
library;

import 'dart:io';

import 'package:dart_monty/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_monty/src/bindings/binding_spec.dart';
import 'package:soliplex_monty/src/bindings/binding_stubs.g.dart';
import 'package:soliplex_monty/src/bindings/generated_source.dart';
import 'package:soliplex_monty/src/bindings/host_bindings.dart';
import 'package:soliplex_monty/src/chart_module.dart';
import 'package:soliplex_monty/src/python_ui.dart';

import 'support/showcase_checks.dart' show repositoryRoot;

String difference(String path, String old, String updated) {
  final before = old.split('\n');
  final after = updated.split('\n');
  var start = 0;
  while (start < before.length &&
      start < after.length &&
      before[start] == after[start]) {
    start++;
  }
  var endBefore = before.length;
  var endAfter = after.length;
  while (endBefore > start &&
      endAfter > start &&
      before[endBefore - 1] == after[endAfter - 1]) {
    endBefore--;
    endAfter--;
  }
  return '--- $path (committed)\n+++ $path (regenerated)\n'
      '@@ -${start + 1},${endBefore - start} '
      '+${start + 1},${endAfter - start} @@\n'
      '${before.sublist(start, endBefore).map((l) => '-$l').join('\n')}\n'
      '${after.sublist(start, endAfter).map((l) => '+$l').join('\n')}\n';
}

void main() {
  test('committed Dart and backend stubs regenerate byte for byte', () {
    final regenerated = {
      for (final entry in generateBindings().entries)
        entry.key: entry.value.stubs,
    };
    void compare(String path, String expected) {
      final actual = File(path).readAsStringSync();
      if (actual != expected) fail(difference(path, actual, expected));
    }

    compare(
      'lib/src/bindings/binding_stubs.g.dart',
      generatedDart(regenerated),
    );
    expect(generatedBindingStubs.keys, unorderedEquals(regenerated.keys));
    for (final entry in regenerated.entries) {
      expect(generatedBindingStubs[entry.key], entry.value);
      compare(
        '${repositoryRoot.path}/workbench/backend/'
        'soliplex_a2ui_workbench/src/soliplex_a2ui_workbench/'
        'binding_stubs/${entry.key}.pyi',
        entry.value,
      );
    }
  });

  test('every registered host attribute has exactly one implemented stub', () {
    final arena = PythonUiArena(workbenchEnabled: true);
    final ui = PythonUiArena.moduleFor(() => arena);
    final modules = {
      'ui': ui,
      'ui.workbench': ui.attrs['workbench']! as ExternalModule,
      'ui.graphics': ui.attrs['graphics']! as ExternalModule,
      'chart': chartModule(),
    };
    for (final MapEntry(:key, :value) in modules.entries) {
      expect(
        checkBindings(
          key,
          value,
          moduleBindings[key]!.functions,
          submodules: key == 'ui' ? {'graphics', 'workbench'} : {},
        ),
        isTrue,
      );
      // Overloads count as one function entry, as in Python's symbol table.
      final entries = RegExp(
        r'^def (\w+)\(',
        multiLine: true,
      ).allMatches(value.stubs!).map((m) => m[1]!).toSet();
      expect(
        entries,
        unorderedEquals(moduleBindings[key]!.functions.map((b) => b.name)),
      );
    }
  });

  test('debug self-check explains added, missing and retyped hosts', () {
    final module = chartModule();
    final bindings = moduleBindings['chart']!.functions;
    for (final attrs in [
      {...module.attrs}..remove('bar'),
      {...module.attrs, 'extra': const MontyNone()},
      {
        ...module.attrs,
        'bar': MontyHostFunction(
          'bar',
          (_, _) => const MontyNone(),
          docstring: 'different declaration',
        ),
      },
    ]) {
      expect(
        () => checkBindings('chart', ExternalModule(attrs), bindings),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Binding mismatch'),
          ),
        ),
      );
    }
    expect(
      () => checkBindings('chart', module, [...bindings, bindings.first]),
      throwsStateError,
    );
  });

  test(
    'shared validator checks defaults, names, duplicates and nested types',
    () async {
      final move = workbenchBindings.singleWhere(
        (b) => b.name == 'move_window',
      );
      expect(move.validate([const MontyString('window')], {}), {
        'window_id': 'window',
        'order': 0,
      });
      for (final call in [
        () => move.validate([], {}),
        () => move.validate(
          [const MontyString('w')],
          {'order': const MontyBool(true)},
        ),
        () => move.validate(
          [const MontyString('w')],
          {'window_id': const MontyString('x')},
        ),
        () => move.validate(
          [const MontyString('w')],
          {'typo': const MontyInt(1)},
        ),
      ]) {
        expect(call, throwsA(isA<ExternalException>()));
      }
      final bar = chartModule().attrs['bar']! as MontyHostFunction;
      await expectLater(
        bar.fn([
          MontyValue.fromDart([
            {'id': 'a', 'label': 'A', 'value': 'wrong'},
          ]),
        ], {}),
        throwsA(isA<ExternalException>()),
      );
    },
  );
}
