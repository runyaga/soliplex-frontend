import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

void main() {
  group('HostFunctionSchema.toJsonSchema', () {
    test('empty params -> object with empty properties, no required', () {
      const schema = HostFunctionSchema(name: 'noop');
      expect(
        schema.toJsonSchema(),
        equals(<String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{},
        }),
      );
    });

    test('omits "required" when no params are required', () {
      const schema = HostFunctionSchema(
        name: 'optional_only',
        params: [
          HostParam(
            name: 'q',
            type: HostParamType.string,
            isRequired: false,
          ),
        ],
      );
      final json = schema.toJsonSchema();
      expect(json.containsKey('required'), isFalse);
      expect(
        (json['properties']! as Map)['q'],
        equals({'type': 'string'}),
      );
    });

    test('lists required params in declaration order', () {
      const schema = HostFunctionSchema(
        name: 'multi',
        params: [
          HostParam(name: 'a', type: HostParamType.string),
          HostParam(
            name: 'b',
            type: HostParamType.integer,
            isRequired: false,
          ),
          HostParam(name: 'c', type: HostParamType.boolean),
        ],
      );
      expect(schema.toJsonSchema()['required'], equals(['a', 'c']));
    });

    test('description is included when non-empty', () {
      const schema = HostFunctionSchema(
        name: 'with_desc',
        params: [
          HostParam(
            name: 'p',
            type: HostParamType.string,
            description: 'a parameter',
          ),
        ],
      );
      final p = (schema.toJsonSchema()['properties']! as Map)['p']!
          as Map<String, Object?>;
      expect(p['description'], 'a parameter');
    });

    test('description is omitted when empty', () {
      const schema = HostFunctionSchema(
        name: 'no_desc',
        params: [HostParam(name: 'p', type: HostParamType.string)],
      );
      final p = (schema.toJsonSchema()['properties']! as Map)['p']!
          as Map<String, Object?>;
      expect(p.containsKey('description'), isFalse);
    });
  });

  group('HostParamType -> JSON Schema type mapping', () {
    Map<String, Object?> propertyFor(HostParamType type) {
      final schema = HostFunctionSchema(
        name: 't',
        params: [HostParam(name: 'p', type: type)],
      );
      return (schema.toJsonSchema()['properties']! as Map)['p']!
          as Map<String, Object?>;
    }

    test('string -> "string"', () {
      expect(propertyFor(HostParamType.string)['type'], 'string');
    });

    test('integer -> "integer"', () {
      expect(propertyFor(HostParamType.integer)['type'], 'integer');
    });

    test('number -> "number"', () {
      expect(propertyFor(HostParamType.number)['type'], 'number');
    });

    test('boolean -> "boolean"', () {
      expect(propertyFor(HostParamType.boolean)['type'], 'boolean');
    });

    test('list -> "array" (Dart-list / JSON-array)', () {
      expect(propertyFor(HostParamType.list)['type'], 'array');
    });

    test('map -> "object" (Dart-map / JSON-object)', () {
      expect(propertyFor(HostParamType.map)['type'], 'object');
    });

    test('any -> omits "type" key (unconstrained)', () {
      final p = propertyFor(HostParamType.any);
      expect(p.containsKey('type'), isFalse);
    });
  });
}
