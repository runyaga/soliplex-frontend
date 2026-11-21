import 'dart:async';
import 'dart:convert';

import 'package:dart_monty/core.dart';

/// A Python annotation and the matching check on a decoded host value.
class PythonType {
  const PythonType(this.annotation, this.accepts);

  final String annotation;
  final bool Function(Object?) accepts;

  PythonType operator |(PythonType other) => PythonType(
    '$annotation | ${other.annotation}',
    (value) => accepts(value) || other.accepts(value),
  );

  PythonType get list => PythonType(
    'list[$annotation]',
    (value) => value is List && value.every(accepts),
  );
}

final pyString = PythonType('str', (v) => v is String);
final pyNumber = PythonType('float', (v) => v is num);
final pyInt = PythonType('int', (v) => v is int);
final pyBool = PythonType('bool', (v) => v is bool);
final pyNone = PythonType('None', (v) => v == null);
final pyDict = PythonType(
  'dict[str, Any]',
  (v) => v is Map && v.keys.every((k) => k is String),
);
final pyBinding = PythonType(
  'Binding',
  (v) => v is String && v.startsWith('<ui:bind:'),
);
final pyEvent = PythonType(
  'EventHandle',
  (v) => v is String && v.startsWith('<ui:event:'),
);

PythonType pythonLiteral(List<Object?> values) => PythonType(
  'Literal[${values.map(pythonValue).join(', ')}]',
  values.contains,
);

String pythonValue(Object? value) => switch (value) {
  null => 'None',
  true => 'True',
  false => 'False',
  _ => jsonEncode(value),
};

/// Null [defaultValue] means required; `...` means optional without insertion.
/// This preserves catalog defaults and constructor staging behaviour.
class BindingParameter {
  const BindingParameter(
    this.name,
    this.type, {
    this.defaultValue,
    this.defaultDart,
    this.keywordOnly = false,
  });

  final String name;
  final PythonType type;
  final String? defaultValue;
  final Object? defaultDart;
  final bool keywordOnly;

  String declaration({bool required = false}) =>
      '$name: ${type.annotation}'
      '${!required && defaultValue != null ? ' = $defaultValue' : ''}';
}

typedef BindingBody = FutureOr<MontyValue> Function(Map<String, Object?> args);

/// One source of truth for a host function's Python and Dart boundary.
class FunctionBinding {
  const FunctionBinding(this.name, this.parameters, this.returns, this.doc);

  final String name;
  final List<BindingParameter> parameters;
  final PythonType returns;
  final String doc;

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
      return 'def $name(${parts.join(', ')}) -> ${returns.annotation}: ...';
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
      } else if (!parameter.type.accepts(values[parameter.name])) {
        fail('"${parameter.name}" must be ${parameter.type.annotation}');
      }
    }
    return values;
  }

  MontyHostFunction host(BindingBody body) => MontyHostFunction(
    name,
    (args, kwargs) async {
      final result = await body(validate(args, kwargs));
      if (!returns.accepts(result.dartValue)) {
        throw StateError(
          '$name returned a value outside ${returns.annotation}',
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
