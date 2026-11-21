import 'package:dart_monty/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_monty/src/bindings/binding_spec.dart';
import 'package:soliplex_monty/src/bindings/host_bindings.dart';
import 'package:soliplex_monty/src/bindings/schema_types.dart';
import 'package:soliplex_monty/src/bindings/schema_validator.dart';

void main() {
  test('JSON schemas drive annotations and host value validation', () {
    final types = SchemaTypes(definitions: hostValueDefinitions);
    final cases = <(Map<String, Object?>, String, Object?, Object?)>[
      ({'type': 'string'}, 'str', 'text', 1),
      ({'type': 'number'}, 'float', 1.5, true),
      ({'type': 'integer'}, 'int', 2, true),
      ({'type': 'boolean'}, 'bool', false, 0),
      ({'type': 'null'}, 'None', null, ''),
      (
        {
          'enum': ['text', 'python'],
        },
        'Literal["text", "python"]',
        'text',
        'html',
      ),
      ({'const': true}, 'Literal[True]', true, false),
      (
        {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'list[str]',
        ['text'],
        [2],
      ),
      ({'type': 'array', 'maxItems': 0}, 'list[Never]', [], [1]),
      ({'type': 'object'}, 'dict[str, Any]', {'key': 1}, []),
      (
        {
          'type': ['number', 'null'],
        },
        'float | None',
        null,
        false,
      ),
      (
        {
          'anyOf': [
            {'type': 'string'},
            {'type': 'null'},
          ],
        },
        'str | None',
        null,
        1,
      ),
      (
        {
          'oneOf': [
            {'type': 'string'},
            {'type': 'boolean'},
          ],
        },
        'str | bool',
        true,
        1,
      ),
      ({r'$ref': r'#/$defs/Binding'}, 'Binding', '<ui:bind:1>', '/path'),
      ({r'$ref': r'#/$defs/EventHandle'}, 'EventHandle', '<ui:event:1>', {}),
      ({r'$ref': r'#/$defs/WindowId'}, 'str', 'window-1', 1),
    ];
    for (final (schema, annotation, valid, invalid) in cases) {
      expect(types.type(schema, 'Value'), annotation, reason: '$schema');
      final validator = JsonSchemaValidator(schema, hostValueDefinitions);
      expect(validator.accepts(valid), isTrue, reason: '$schema: $valid');
      expect(validator.accepts(invalid), isFalse, reason: '$schema: $invalid');
    }
  });

  test('nested objects retain required fields and schema constraints', () {
    const schema = <String, Object?>{
      'type': 'object',
      'properties': {
        'points': {
          'type': 'array',
          'minItems': 1,
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'pattern': '^point-'},
              'value': {'type': 'number', 'minimum': 0, 'maximum': 100},
            },
            'required': ['id', 'value'],
            'additionalProperties': false,
          },
        },
        'label': {'type': 'string', 'maxLength': 10},
      },
      'required': ['points'],
      'additionalProperties': false,
    };
    final types = SchemaTypes();
    expect(types.type(schema, 'Plot'), 'Plot');
    expect(types.declarations['Plot'], contains('"label": NotRequired[str]'));
    expect(types.declarations['PlotPointsItem'], contains('"value": float'));
    final validator = JsonSchemaValidator(schema, const {});
    expect(
      validator.accepts({
        'points': [
          {'id': 'point-a', 'value': 1},
        ],
      }),
      isTrue,
    );
    for (final invalid in [
      <String, Object?>{},
      {'points': <Object?>[]},
      {
        'points': [
          {'id': 'point-a'},
        ],
      },
      {
        'points': [
          {'id': 'wrong', 'value': 1},
        ],
      },
      {
        'points': [
          {'id': 'point-a', 'value': -1},
        ],
      },
      {
        'points': [
          {'id': 'point-a', 'value': 101},
        ],
      },
      {
        'points': [
          {'id': 'point-a', 'value': true},
        ],
      },
      {
        'points': [
          {'id': 'point-a', 'value': 1, 'typo': 0},
        ],
      },
      {
        'points': [
          {'id': 'point-a', 'value': 1},
        ],
        'typo': 0,
      },
    ]) {
      expect(validator.accepts(invalid), isFalse, reason: '$invalid');
    }
  });

  test('oneOf requires exactly one match while anyOf allows overlap', () {
    const alternatives = [
      {'type': 'number'},
      {'type': 'integer'},
    ];
    expect(
      JsonSchemaValidator({'oneOf': alternatives}, const {}).accepts(2),
      isFalse,
    );
    expect(
      JsonSchemaValidator({'anyOf': alternatives}, const {}).accepts(2),
      isTrue,
    );
  });

  test('decoded maps require string keys, including nested objects', () {
    final validator = JsonSchemaValidator({'type': 'object'}, const {});
    expect(validator.accepts(<Object?, Object?>{'key': 1}), isTrue);
    expect(validator.accepts(<Object?, Object?>{1: 'value'}), isFalse);
    expect(
      validator.accepts({
        'nested': <Object?, Object?>{1: true},
      }),
      isFalse,
    );
  });

  test('graphics dynamic strings accept both literal and binding tokens', () {
    final chart = moduleBindings['ui.graphics']!.functions.single;
    for (final selected in ['point-a', '<ui:bind:1>']) {
      expect(
        chart.validate(
          [
            MontyValue.fromDart({'kind': 'bar', 'points': <Object?>[]}),
            MontyValue.fromDart(<Object?>[]),
            const MontyString('Counts'),
          ],
          {'selected': MontyString(selected)},
        ),
        containsPair('selected', selected),
      );
    }
  });

  test(
    'a new function entry supplies its complete checked host boundary',
    () async {
      final module = ModuleBindings('ui.workbench');
      final binding = FunctionBinding.fromSchema({
        'name': 'probe',
        'description': 'Exercise an additional schema entry.',
        'parameters': {
          'type': 'object',
          'properties': {
            'value': {'type': 'integer'},
            'enabled': {'type': 'boolean', 'default': true},
            'label': {'type': 'string'},
            'metadata': {
              'type': 'object',
              'default': {'flag': false},
            },
          },
          'required': ['value'],
          'additionalProperties': false,
        },
        'returnType': 'string',
        'x-returnSchema': {r'$ref': r'#/$defs/Binding'},
        'x-python': {
          'positional': ['value'],
        },
      }, module.types);
      module.functions.add(binding);
      expect(module.stubs, contains('from ui import Binding'));
      expect(
        binding.stub,
        contains(
          'def probe(value: int, *, enabled: bool = True, label: str = ..., '
          'metadata: dict[str, Any] = {"flag": False}) -> Binding',
        ),
      );
      expect(binding.validate([const MontyInt(2)], {}), {
        'value': 2,
        'enabled': true,
        'metadata': {'flag': false},
      });
      for (final invalid in [
        () => binding.validate([const MontyInt(2), const MontyBool(true)], {}),
        () =>
            binding.validate([const MontyInt(2)], {'value': const MontyInt(3)}),
        () =>
            binding.validate([const MontyInt(2)], {'typo': const MontyInt(3)}),
        () => binding.validate([], {}),
        () => binding.validate([const MontyBool(true)], {}),
      ]) {
        expect(invalid, throwsA(isA<ExternalException>()));
      }
      final host = binding.host((args) => const MontyString('<ui:bind:2>'));
      expect((await host.fn([const MontyInt(2)], {})).dartValue, '<ui:bind:2>');
      await expectLater(
        binding.host((args) => const MontyString('invalid')).fn([
          const MontyInt(2),
        ], {}),
        throwsStateError,
      );
    },
  );
}
