import 'dart:async';

import 'package:dart_monty/core.dart';
import 'package:soliplex_monty/src/bindings/schema_types.dart';
import 'package:soliplex_monty/src/bindings/schema_validator.dart';

/// Null [defaultValue] means required; `...` means optional without insertion.
/// This preserves catalog defaults and constructor staging behaviour.
class BindingParameter {
  const BindingParameter(
    this.name,
    this.schema,
    this.annotation, {
    required this.required,
    this.keywordOnly = false,
  });

  final String name;
  final Map<String, Object?> schema;
  final String annotation;
  final bool required;

  String? get defaultValue => required
      ? null
      : schema.containsKey('default')
      ? pythonValue(schema['default'])
      : '...';
  Object? get defaultDart => schema['default'];
  final bool keywordOnly;

  String declaration({bool required = false}) =>
      '$name: $annotation'
      '${!required && defaultValue != null ? ' = $defaultValue' : ''}';
}

typedef BindingBody = FutureOr<MontyValue> Function(Map<String, Object?> args);

/// One source of truth for a host function's Python and Dart boundary.
class FunctionBinding {
  FunctionBinding.fromSchema(this.definition, SchemaTypes types) {
    name = definition['name']! as String;
    doc = definition['description']! as String;
    final arguments = SchemaTypes.map(definition['parameters']);
    final props = SchemaTypes.map(arguments['properties']);
    final required = (arguments['required'] as List?)?.cast<String>() ?? [];
    final positional =
        (SchemaTypes.map(definition['x-python'])['positional'] as List?)
            ?.cast<String>() ??
        [];
    if (positional.toSet().length != positional.length ||
        positional.any((key) => !props.containsKey(key)) ||
        required.any((key) => !props.containsKey(key))) {
      throw StateError('Invalid host signature for $name');
    }
    final typePrefix = '${name[0].toUpperCase()}${name.substring(1)}';
    parameters = [
      for (final key in [
        ...positional,
        ...props.keys.where((key) => !positional.contains(key)),
      ])
        BindingParameter(
          key,
          SchemaTypes.map(props[key]),
          types.type(
            SchemaTypes.map(props[key]),
            '$typePrefix${SchemaTypes.identifier(key)}',
          ),
          required: required.contains(key),
          keywordOnly: !positional.contains(key),
        ),
    ];
    final returnSchema = definition.containsKey('x-returnSchema')
        ? SchemaTypes.map(definition['x-returnSchema'])
        : switch (definition['returnType']) {
            'void' => <String, Object?>{'type': 'null'},
            'any' => <String, Object?>{},
            final String type => <String, Object?>{'type': type},
            _ => throw StateError('Missing return schema for $name'),
          };
    returns = types.type(
      returnSchema,
      '${typePrefix}Result',
    );
    _arguments = JsonSchemaValidator(arguments, types.definitions);
    _returns = JsonSchemaValidator(returnSchema, types.definitions);
  }

  final Map<String, Object?> definition;
  late final String name;
  late final List<BindingParameter> parameters;
  late final String returns;
  late final String doc;
  late final JsonSchemaValidator _arguments;
  late final JsonSchemaValidator _returns;

  List<BindingParameter> get positional =>
      parameters.where((p) => !p.keywordOnly).toList();

  /// Generates overloads only when required arguments follow optional ones.
  /// The prefix overloads retain the historical positional order while also
  /// allowing omitted optional parameters in calls made with keywords.
  String get stub {
    final pos = positional;
    final needsOverloads =
        pos.indexWhere((p) => p.defaultValue != null) >= 0 &&
        pos.lastIndexWhere((p) => p.defaultValue == null) >
            pos.indexWhere((p) => p.defaultValue != null);
    String signature(int? prefix) {
      final parts = <String>[];
      var star = false;
      for (var i = 0; i < parameters.length; i++) {
        final parameter = parameters[i];
        if (!star &&
            (parameter.keywordOnly || (prefix != null && i >= prefix))) {
          parts.add('*');
          star = true;
        }
        parts.add(parameter.declaration(required: prefix != null && !star));
      }
      return 'def $name(${parts.join(', ')}) -> $returns: ...';
    }

    return '# $doc\n${needsOverloads ? [
            for (var i = 0; i <= pos.length; i++) '@overload\n${signature(i)}',
          ].join('\n') : signature(null)}\n';
  }

  Map<String, Object?> validate(
    List<MontyValue> args,
    Map<String, MontyValue> kwargs,
  ) {
    Never fail(String message) =>
        throw ExternalException('TypeError', '$name(): $message');
    final pos = positional;
    if (args.length > pos.length) {
      fail('takes at most ${pos.length} positional arguments');
    }
    final values = <String, Object?>{
      for (var i = 0; i < args.length; i++) pos[i].name: args[i].dartValue,
    };
    final names = parameters.map((p) => p.name).toSet();
    for (final MapEntry(:key, :value) in kwargs.entries) {
      if (!names.contains(key)) fail('unexpected keyword argument "$key"');
      if (values.containsKey(key)) fail('multiple values for argument "$key"');
      values[key] = value.dartValue;
    }
    for (final parameter in parameters) {
      if (!values.containsKey(parameter.name)) {
        if (parameter.defaultValue == null) {
          fail('missing required argument "${parameter.name}"');
        }
        if (parameter.defaultValue != '...') {
          values[parameter.name] = parameter.defaultDart;
        }
      }
    }
    final errors = _arguments.errors(values);
    if (errors.isNotEmpty) fail(errors.join('; '));
    return values;
  }

  MontyHostFunction host(BindingBody body) => MontyHostFunction(
    name,
    (args, kwargs) async {
      final result = await body(validate(args, kwargs));
      if (!_returns.accepts(result.dartValue)) {
        throw StateError(
          '$name returned a value outside $returns',
        );
      }
      return result;
    },
    docstring: stub,
  );
}

/// Fails on missing, extra, duplicated or differently declared host functions.
/// Called only inside assertions at registration; also callable by drift tests.
bool checkBindings(
  String moduleName,
  ExternalModule module,
  List<FunctionBinding> bindings, {
  Set<String> submodules = const {},
}) {
  final names = bindings.map((b) => b.name).toSet();
  final actual = module.attrs.keys.toSet().difference(submodules);
  final missing = names.difference(actual);
  final extra = actual.difference(names);
  if (names.length != bindings.length ||
      missing.isNotEmpty ||
      extra.isNotEmpty) {
    throw StateError(
      'Binding mismatch in $moduleName: missing $missing, extra $extra; '
      '${bindings.length} declarations for ${names.length} names.',
    );
  }
  for (final binding in bindings) {
    final host = module.attrs[binding.name];
    if (host is! MontyHostFunction ||
        host.name != binding.name ||
        host.docstring != binding.stub) {
      throw StateError('Binding mismatch in $moduleName.${binding.name}');
    }
  }
  for (final name in submodules) {
    if (module.attrs[name] is! ExternalModule) {
      throw StateError('Binding mismatch: missing module $moduleName.$name');
    }
  }
  return true;
}
