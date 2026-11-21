import 'dart:convert';

/// Maps JSON Schema to Python annotations. Validation uses the same schemas,
/// through json_schema_builder, without attaching Dart predicates to types.
class SchemaTypes {
  SchemaTypes({this.definitions = const {}});

  final Map<String, Object?> definitions;
  final Map<String, String> declarations = {};
  final Set<String> handles = {};

  static String identifier(String value) => value
      .replaceAll(RegExp('[^a-zA-Z0-9_]'), '_')
      .replaceFirstMapped(RegExp('[a-z]'), (m) => m[0]!.toUpperCase());

  String type(Map<String, Object?> schema, String suggestedName) {
    final name = schema['title'] as String? ?? suggestedName;
    if (schema[r'$ref'] case final String ref) {
      if (!ref.startsWith(r'#/$defs/')) {
        throw StateError('Unmapped schema reference $ref in $name');
      }
      final key = ref.substring(8).replaceAll('~1', '/').replaceAll('~0', '~');
      final target = definitions[key];
      if (target is! Map) {
        throw StateError('Unmapped schema reference $ref in $name');
      }
      return type(map(target), key);
    }
    if (map(schema['x-python'])['opaque'] case final String handle) {
      handles.add(handle);
      return handle;
    }
    if (schema.containsKey('const')) {
      return 'Literal[${pythonValue(schema['const'])}]';
    }
    if (schema['enum'] case final List<Object?> values) {
      return 'Literal[${values.map(pythonValue).join(', ')}]';
    }
    final alternatives = schema['oneOf'] ?? schema['anyOf'];
    if (alternatives is List) {
      return [
        for (var i = 0; i < alternatives.length; i++)
          type(map(alternatives[i]), '${name}Option$i'),
      ].join(' | ');
    }
    if (schema['allOf'] case final List<Object?> parts) {
      final typed = parts
          .map(map)
          .where(
            (s) =>
                s.containsKey(r'$ref') ||
                s.containsKey('type') ||
                s.containsKey('anyOf') ||
                s.containsKey('oneOf'),
          );
      if (typed.length == 1) return type(typed.single, name);
      throw StateError('Cannot represent intersection in $name: $schema');
    }
    if (schema['type'] case final List<Object?> types) {
      return types.map((t) => type({...schema, 'type': t}, name)).join(' | ');
    }
    switch (schema['type']) {
      case 'string':
        return 'str';
      case 'number':
        return 'float';
      case 'integer':
        return 'int';
      case 'boolean':
        return 'bool';
      case 'null':
        return 'None';
      case 'array':
        if (schema['maxItems'] == 0) return 'list[Never]';
        return 'list[${type(map(schema['items']), '${name}Item')}]';
      case 'object':
        final props = map(schema['properties']);
        if (props.isEmpty) return 'dict[str, Any]';
        final required = (schema['required'] as List?)?.cast<String>() ?? [];
        final fields = {
          for (final MapEntry(:key, :value) in props.entries)
            key: type(map(value), '$name${identifier(key)}'),
        };
        final declaration = StringBuffer('$name = TypedDict("$name", {\n');
        for (final MapEntry(:key, :value) in fields.entries) {
          final annotation = required.contains(key)
              ? value
              : 'NotRequired[$value]';
          declaration.writeln('    ${pythonValue(key)}: $annotation,');
        }
        declaration.writeln('})');
        final text = declaration.toString();
        if (declarations.containsKey(name) && declarations[name] != text) {
          throw StateError('Conflicting schema type $name');
        }
        declarations[name] = text;
        return name;
      default:
        if (schema.isEmpty) return 'Any';
        throw StateError('Unmapped schema in $name: $schema');
    }
  }

  static Map<String, Object?> map(Object? value) =>
      value == null ? {} : Map<String, Object?>.from(value as Map);
}

String pythonValue(Object? value) => switch (value) {
  null => 'None',
  true => 'True',
  false => 'False',
  List() => '[${value.map(pythonValue).join(', ')}]',
  Map() => '{${value.entries.map(_pythonEntry).join(', ')}}',
  _ => jsonEncode(value),
};

String _pythonEntry(MapEntry<Object?, Object?> entry) =>
    '${pythonValue(entry.key)}: ${pythonValue(entry.value)}';
