import 'package:a2ui_core/a2ui_core.dart';

import 'package:soliplex_monty/src/bindings/binding_spec.dart';

/// Converts catalog JSON schemas into Python types and Dart type checks.
/// A new asset catalog can use this without changing the module generator.
class SchemaTypes {
  final Map<String, String> declarations = {};

  PythonType get computed =>
      type(CommonSchemasV1.functionCall.value, 'FunctionCall');

  static String identifier(String value) => _identifier(value);

  PythonType type(Map<String, Object?> schema, String name) {
    if (schema[r'$ref'] case final String ref) {
      return switch (ref.split('/').last) {
        'DataBinding' => pyBinding,
        'FunctionCall' => computed,
        'DynamicString' => pyString | pyBinding | computed,
        'DynamicNumber' => pyNumber | pyBinding | computed,
        'DynamicBoolean' => pyBool | pyBinding | computed,
        'DynamicStringList' => pyString.list | pyBinding | computed,
        'Child' => pyString,
        'ComponentId' => pyString,
        'ChildList' => pyString.list,
        'Action' => pyEvent,
        _ => throw StateError('Unmapped schema reference $ref in $name'),
      };
    }
    if (schema.containsKey('const')) {
      return pythonLiteral([schema['const']]);
    }
    if (schema['enum'] case final List<Object?> values) {
      return pythonLiteral(values);
    }
    final alternatives = schema['oneOf'] ?? schema['anyOf'];
    if (alternatives is List) {
      return [
        for (var i = 0; i < alternatives.length; i++)
          type(map(alternatives[i]), '${name}Option$i'),
      ].reduce((a, b) => a | b);
    }
    if (schema['allOf'] case final List<Object?> parts) {
      // allOf also carries format/range constraints; they add no Python type.
      final typed = parts
          .map(map)
          .where(
            (s) => s.containsKey(r'$ref') || s.containsKey('type'),
          );
      if (typed.length == 1) return type(typed.single, name);
      return type(flatten(schema), name);
    }
    if (schema['type'] case final List<Object?> types) {
      return types
          .map((t) => type({...schema, 'type': t}, name))
          .reduce((a, b) => a | b);
    }
    switch (schema['type']) {
      case 'string':
        return pyString;
      case 'number':
        return pyNumber;
      case 'integer':
        return pyInt;
      case 'boolean':
        return pyBool;
      case 'null':
        return pyNone;
      case 'array':
        if (schema['maxItems'] == 0) {
          return PythonType('list[Never]', (v) => v is List && v.isEmpty);
        }
        return type(map(schema['items']), '${name}Item').list;
      case 'object':
        final props = map(schema['properties']);
        if (props.containsKey('@path') || props.containsKey('path')) {
          return pyBinding;
        }
        if (props.isEmpty) return pyDict;
        final required = (schema['required'] as List?)?.cast<String>() ?? [];
        final fields = {
          for (final MapEntry(:key, :value) in props.entries)
            key: type(map(value), '$name${_identifier(key)}'),
        };
        final declaration = StringBuffer('$name = TypedDict("$name", {\n');
        for (final MapEntry(:key, :value) in fields.entries) {
          final annotation = required.contains(key)
              ? value.annotation
              : 'NotRequired[${value.annotation}]';
          declaration.writeln('    ${pythonValue(key)}: $annotation,');
        }
        declaration.writeln('})');
        final text = declaration.toString();
        if (declarations.containsKey(name) && declarations[name] != text) {
          throw StateError('Conflicting schema type $name');
        }
        declarations[name] = text;
        return PythonType(name, (v) {
          if (v is! Map || !required.every(v.containsKey)) return false;
          if (schema['additionalProperties'] == false &&
              v.keys.any((k) => !fields.containsKey(k))) {
            return false;
          }
          return fields.entries.every(
            (e) => !v.containsKey(e.key) || e.value.accepts(v[e.key]),
          );
        });
      default:
        throw StateError('Unmapped schema in $name: $schema');
    }
  }

  static Map<String, Object?> map(Object? value) =>
      value == null ? {} : Map<String, Object?>.from(value as Map);

  /// Flattens component inheritance without losing required properties.
  static Map<String, Object?> flatten(Map<String, Object?> schema) {
    final properties = map(schema['properties']);
    final required = <Object?>[...?schema['required'] as List?];
    for (final part in schema['allOf'] as List? ?? []) {
      final flat = flatten(map(part));
      properties.addAll(map(flat['properties']));
      required.addAll(flat['required'] as List? ?? []);
    }
    return {
      ...schema,
      'allOf': null,
      'type': 'object',
      'properties': properties,
      'required': required,
    }..remove('allOf');
  }

  static String _identifier(String value) => value
      .replaceAll(RegExp('[^a-zA-Z0-9_]'), '_')
      .replaceFirstMapped(RegExp('[a-z]'), (m) => m[0]!.toUpperCase());
}
