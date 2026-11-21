import 'package:json_schema_builder/json_schema_builder.dart';

/// The same synchronous JSON Schema validator used by a2ui_core. Host schemas
/// use local definitions for token values, so validation never needs I/O.
class JsonSchemaValidator {
  JsonSchemaValidator(
    Map<String, Object?> schema,
    Map<String, Object?> definitions,
  ) : _schema = Schema.fromMap({...schema, r'$defs': definitions});

  final Schema _schema;

  List<String> errors(Object? value) {
    try {
      return _schema
          .validateSync(_jsonMaps(value))
          .map((error) => error.toErrorString())
          .toList();
    } on FormatException catch (error) {
      return [error.message];
    }
  }

  bool accepts(Object? value) => errors(value).isEmpty;
}

// Monty dicts can decode to Map<Object?, Object?>. The schema library expects
// string-keyed maps, so normalize their Dart type and reject non-JSON keys.
Object? _jsonMaps(Object? value) => switch (value) {
  Map() => <String, Object?>{
    for (final entry in value.entries)
      _jsonKey(entry.key): _jsonMaps(entry.value),
  },
  List() => value.map(_jsonMaps).toList(),
  _ => value,
};

String _jsonKey(Object? key) => key is String
    ? key
    : throw const FormatException('Object keys must be strings');
