import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/basic_catalog.dart';
import 'package:soliplex_catalogs/src/host_signatures.dart';
import 'package:soliplex_catalogs/src/static_chart.dart';

/// JSON Schema definitions for values crossing the Python host boundary.
/// Binding and event tokens are opaque in Python. Window IDs remain strings,
/// as required by the existing file/window API.
final hostValueDefinitions = <String, Object?>{
  'Binding': {
    'type': 'string',
    'pattern': r'^<ui:bind:',
    'x-python': {'opaque': 'Binding'},
  },
  'EventHandle': {
    'type': 'string',
    'pattern': r'^<ui:event:',
    'x-python': {'opaque': 'EventHandle'},
  },
  'WindowId': {
    'type': 'string',
    'description': 'An opaque workbench window ID.',
  },
  'FunctionCall': CommonSchemasV1.functionCall.value,
};

const _string = <String, Object?>{'type': 'string'};
const _none = <String, Object?>{'type': 'null'};
const _window = <String, Object?>{r'$ref': r'#/$defs/WindowId'};
const _optionalObject = <String, Object?>{
  'anyOf': [
    {'type': 'object'},
    _none,
  ],
  'default': null,
};

/// A2UI inline function definitions with two host extensions:
/// `x-returnSchema` refines the coarse A2UI `returnType`, and `x-python`
/// records positional order (all remaining parameters are keyword-only).
/// JSON Schema `required` and `default` distinguish required, inserted default,
/// and optional-without-insertion parameters. No Python annotation is authored.
const uiHostFunctionSchemas = <Map<String, Object?>>[
  {
    'name': 'bind',
    'description': 'Bind a property to a JSON Pointer in the data model.',
    'parameters': {
      'type': 'object',
      'properties': {'path': _string},
      'required': ['path'],
      'additionalProperties': false,
    },
    'returnType': 'string',
    'x-returnSchema': {r'$ref': r'#/$defs/Binding'},
    'x-python': {
      'positional': ['path'],
    },
  },
  {
    'name': 'Event',
    'description': 'Create a client event with an optional context dict.',
    'parameters': {
      'type': 'object',
      'properties': {'name': _string, 'context': _optionalObject},
      'required': ['name'],
      'additionalProperties': false,
    },
    'returnType': 'string',
    'x-returnSchema': {r'$ref': r'#/$defs/EventHandle'},
    'x-python': {
      'positional': ['name', 'context'],
    },
  },
  {
    'name': 'show',
    'description': 'Stage a component tree and optional data model.',
    'parameters': {
      'type': 'object',
      'properties': {'root': _string, 'data': _optionalObject},
      'required': ['root'],
      'additionalProperties': false,
    },
    'returnType': 'void',
    'x-python': {
      'positional': ['root', 'data'],
    },
  },
];

const workbenchHostFunctionSchemas = <Map<String, Object?>>[
  {
    'name': 'read_file',
    'description': 'Read a thread file as UTF-8 text.',
    'parameters': {
      'type': 'object',
      'properties': {'filename': _string},
      'required': ['filename'],
      'additionalProperties': false,
    },
    'returnType': 'string',
    'x-python': {
      'positional': ['filename'],
    },
  },
  {
    'name': 'write_file',
    'description': 'Write UTF-8 text to a thread file.',
    'parameters': {
      'type': 'object',
      'properties': {'filename': _string, 'text': _string},
      'required': ['filename', 'text'],
      'additionalProperties': false,
    },
    'returnType': 'void',
    'x-python': {
      'positional': ['filename', 'text'],
    },
  },
  {
    'name': 'open_window',
    'description': 'Stage a text or Python window; return its id.',
    'parameters': {
      'type': 'object',
      'properties': {
        'title': _string,
        'kind': {
          'enum': ['text', 'python'],
        },
        'content': _string,
      },
      'required': ['title', 'kind', 'content'],
      'additionalProperties': false,
    },
    'returnType': 'string',
    'x-returnSchema': _window,
    'x-python': {
      'positional': ['title', 'kind', 'content'],
    },
  },
  {
    'name': 'update_window',
    'description': 'Stage replacement window content.',
    'parameters': {
      'type': 'object',
      'properties': {'window_id': _window, 'content': _string},
      'required': ['window_id', 'content'],
      'additionalProperties': false,
    },
    'returnType': 'void',
    'x-python': {
      'positional': ['window_id', 'content'],
    },
  },
  {
    'name': 'move_window',
    'description': 'Stage a window move.',
    'parameters': {
      'type': 'object',
      'properties': {
        'window_id': _window,
        'order': {'type': 'integer', 'default': 0},
      },
      'required': ['window_id'],
      'additionalProperties': false,
    },
    'returnType': 'void',
    'x-python': {
      'positional': ['window_id', 'order'],
    },
  },
  {
    'name': 'close_window',
    'description': 'Stage closing a window.',
    'parameters': {
      'type': 'object',
      'properties': {'window_id': _window},
      'required': ['window_id'],
      'additionalProperties': false,
    },
    'returnType': 'void',
    'x-python': {
      'positional': ['window_id'],
    },
  },
];

/// All host signatures, derived from the same schemas as the components.
/// Returned maps contain only JSON values and can also feed an inspector.
Map<String, List<Map<String, Object?>>> hostFunctionSchemas() {
  final ui = [...uiHostFunctionSchemas];
  final graphics = <Map<String, Object?>>[];
  final chart = <Map<String, Object?>>[];
  final basic = basicCatalog();
  for (final MapEntry(:key, :value) in basicSignatures.entries) {
    final schema = basic.components[key]!.schema.value;
    final options = _map(_map(_flatten(schema)['properties'])['options']);
    ui.add(
      _constructor(
        key,
        schema,
        value,
        adapters: {
          if (key == 'ChoicePicker')
            'options': {
              'anyOf': [
                {...options, 'title': 'ChoicePickerOptions'},
                {'type': 'array', 'items': _string},
              ],
            },
        },
      ),
    );
  }
  final chartSchema = chartGraphicsCatalog().components['Chart']!.schema.value;
  final chartProps = _map(chartSchema['properties']);
  final kinds = (_map(chartProps['spec'])['oneOf']! as List).map(_map).toList();
  for (final schema in kinds) {
    final props = _map(schema['properties']);
    final kind = _map(props['kind'])['const']! as String;
    final required = (schema['required']! as List).cast<String>();
    final data = switch (kind) {
      'bar' => ['points'],
      'gauge' => ['value'],
      'pie' => ['slices'],
      'radar' => ['axes', 'series'],
      'candlestick' => ['candles'],
      _ => ['series'],
    };
    chart.add({
      'name': kind,
      'description': 'Build a $kind chart spec.',
      'parameters': {
        'type': 'object',
        'properties': {
          for (final key in [
            ...data,
            ...props.keys.where((k) => k != 'kind' && !data.contains(k)),
          ])
            key: required.contains(key)
                ? props[key]
                : {
                    'anyOf': [
                      {
                        ..._map(props[key]),
                        'title': '${_identifier(kind)}${_identifier(key)}',
                      },
                      _none,
                    ],
                    'default': null,
                  },
        },
        'required': required.where((key) => key != 'kind').toList(),
        'additionalProperties': false,
      },
      'returnType': 'object',
      'x-returnSchema': {...schema, 'title': '${_identifier(kind)}Spec'},
      'x-python': {'positional': data},
    });
  }
  graphics.add(_constructor('Chart', chartSchema, graphicsSignature));

  // Compatibility constructors lower to the registered graphics catalog.
  // Their data layout differs from chart.*: ids are assigned during lowering.
  final bar = kinds.firstWhere(
    (s) => _map(_map(s['properties'])['kind'])['const'] == 'bar',
  );
  final point = _map(_map(_map(bar['properties'])['points'])['items']);
  final barProps = _map(point['properties'])..remove('id');
  final bars = {
    'type': 'array',
    'items': {
      ...point,
      'properties': barProps,
      'required': ['label', 'value'],
    },
  };
  final compatibility = {
    'BarChart': {
      'bars': bars,
      'title': {'type': 'string'},
      'action': {r'$ref': r'common_types.json#/$defs/Action'},
      'weight': {'type': 'number'},
    },
    'LineChart': {
      'labels': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'series': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'label': {'type': 'string'},
            'values': {
              'type': 'array',
              'items': {
                'type': ['number', 'null'],
              },
            },
          },
          'required': ['label', 'values'],
          'additionalProperties': false,
        },
      },
      'title': {'type': 'string'},
      'weight': {'type': 'number'},
    },
  };
  for (final MapEntry(:key, :value) in compatibility.entries) {
    ui.add(
      _constructor(key, {
        'type': 'object',
        'properties': value,
        'required': key == 'BarChart' ? ['bars'] : ['labels', 'series'],
      }, uiChartSignatures[key]!),
    );
  }
  return {
    for (final entry in {
      'ui': ui,
      'ui.workbench': workbenchHostFunctionSchemas,
      'chart': chart,
      'ui.graphics': graphics,
    }.entries)
      entry.key: [for (final schema in entry.value) _hostValues(schema)],
  };
}

Map<String, Object?> _constructor(
  String name,
  Map<String, Object?> schema,
  List<String> order, {
  Map<String, Map<String, Object?>> adapters = const {},
}) {
  final flat = _flatten(schema);
  final props = _map(flat['properties'])..remove('component');
  final required = (flat['required']! as List).cast<String>();
  return {
    'name': name,
    'description': 'Construct a $name component handle.',
    'parameters': {
      'type': 'object',
      'properties': {
        for (final key in [
          ...order,
          ...props.keys.where(
            (key) =>
                !order.contains(key) && RegExp(r'^[a-zA-Z_]\w*$').hasMatch(key),
          ),
          'id',
        ])
          key: key == 'id' ? _string : adapters[key] ?? props[key],
      },
      'required': required.where(props.containsKey).toList(),
      'additionalProperties': false,
    },
    'returnType': 'string',
    'x-python': {'positional': order},
  };
}

// Adapt A2UI wire values to the existing Python convenience API once, so the
// annotation mapper and JSON Schema validator consume identical host schemas.
Map<String, Object?> _hostValues(Map<String, Object?> schema) {
  if (schema[r'$ref'] case final String ref) {
    final name = ref.split('/').last;
    final replacement = switch (name) {
      'DataBinding' => {r'$ref': r'#/$defs/Binding'},
      'Action' => {r'$ref': r'#/$defs/EventHandle'},
      'FunctionCall' => {r'$ref': r'#/$defs/FunctionCall'},
      'DynamicString' => {
        'anyOf': [
          _string,
          {r'$ref': r'#/$defs/Binding'},
          {r'$ref': r'#/$defs/FunctionCall'},
        ],
      },
      'DynamicNumber' => {
        'anyOf': [
          {'type': 'number'},
          {r'$ref': r'#/$defs/Binding'},
          {r'$ref': r'#/$defs/FunctionCall'},
        ],
      },
      'DynamicBoolean' => {
        'anyOf': [
          {'type': 'boolean'},
          {r'$ref': r'#/$defs/Binding'},
          {r'$ref': r'#/$defs/FunctionCall'},
        ],
      },
      'DynamicStringList' => {
        'anyOf': [
          {'type': 'array', 'items': _string},
          {r'$ref': r'#/$defs/Binding'},
          {r'$ref': r'#/$defs/FunctionCall'},
        ],
      },
      'Child' || 'ComponentId' => _string,
      'ChildList' => {'type': 'array', 'items': _string},
      _ => {r'$ref': ref},
    };
    return {
      ...replacement,
      ..._hostValues({...schema}..remove(r'$ref')),
    };
  }
  final props = _map(schema['properties']);
  if (props.containsKey('@path')) {
    // Wire binding objects become arena tokens at the Python boundary.
    if (schema['type'] == 'object') return {r'$ref': r'#/$defs/Binding'};
  }
  return {
    for (final MapEntry(:key, :value) in schema.entries)
      // A wire binding object becomes a string token, which also matches a
      // literal string alternative. Keep the host union inclusive in that case.
      (key == 'oneOf' && value is List && value.any(_isWireBinding)
          ? 'anyOf'
          : key): switch (value) {
        Map() => _hostValues(_map(value)),
        List() => [
          for (final item in value)
            item is Map ? _hostValues(_map(item)) : item,
        ],
        _ => value,
      },
  };
}

bool _isWireBinding(Object? value) {
  if (value is! Map) return false;
  final schema = _map(value);
  return _map(schema['properties']).containsKey('@path') ||
      (schema[r'$ref'] is String &&
          (schema[r'$ref']! as String).endsWith('/DataBinding'));
}

Map<String, Object?> _map(Object? value) =>
    value == null ? {} : Map<String, Object?>.from(value as Map);

Map<String, Object?> _flatten(Map<String, Object?> schema) {
  final properties = _map(schema['properties']);
  final required = <Object?>[...?schema['required'] as List?];
  for (final part in schema['allOf'] as List? ?? []) {
    final flat = _flatten(_map(part));
    properties.addAll(_map(flat['properties']));
    required.addAll(flat['required'] as List? ?? []);
  }
  return {
    ...schema,
    'type': 'object',
    'properties': properties,
    'required': required,
  }..remove('allOf');
}

String _identifier(String value) => value
    .replaceAll(RegExp('[^a-zA-Z0-9_]'), '_')
    .replaceFirstMapped(RegExp('[a-z]'), (m) => m[0]!.toUpperCase());
