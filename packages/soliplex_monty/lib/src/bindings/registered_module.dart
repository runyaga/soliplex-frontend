import 'package:dart_monty/core.dart';

import 'package:soliplex_monty/src/bindings/binding_spec.dart';
import 'package:soliplex_monty/src/bindings/binding_stubs.g.dart';
import 'package:soliplex_monty/src/bindings/host_bindings.dart';

/// Attaches committed stubs and shared validation to the real implementations.
ExternalModule registerBindings(String name, ExternalModule implementation) {
  assert(() {
    final expected = moduleBindings[name]!;
    if (generatedBindingStubs[name] != expected.stubs) {
      throw StateError('Binding mismatch in $name: regenerate committed stubs');
    }
    for (final entry in implementation.attrs.entries) {
      final host = entry.value;
      if (host is MontyHostFunction && host.name != entry.key) {
        throw StateError(
          'Binding mismatch in $name.${entry.key}: '
          'implementation is named ${host.name}',
        );
      }
    }
    return true;
  }(), 'Generated stubs must match registered declarations');
  final bindings = moduleBindings[name]!.functions;
  final byName = {for (final b in bindings) b.name: b};
  final module = ExternalModule({
    for (final MapEntry(:key, :value) in implementation.attrs.entries)
      key: value is MontyHostFunction && byName.containsKey(key)
          ? _host(name, byName[key]!, value)
          : value,
  }, stubs: generatedBindingStubs[name]);
  assert(
    checkBindings(
      name,
      module,
      bindings,
      submodules: name == 'ui' ? {'graphics', 'workbench'} : {},
    ),
    'Registered host bindings must match their specs',
  );
  return module;
}

MontyHostFunction _host(
  String module,
  FunctionBinding binding,
  MontyHostFunction implementation,
) {
  // Basic/compatibility constructors keep arena validation and lowering, including
  // the timing of catalog errors. Their checked boundary is the Python stub.
  if (module == 'ui' && !uiFunctions.any((b) => b.name == binding.name)) {
    return MontyHostFunction(
      binding.name,
      implementation.fn,
      docstring: binding.stub,
    );
  }
  return binding.host(
    (args) => implementation.fn([], {
      for (final entry in args.entries)
        entry.key: MontyValue.fromDart(entry.value),
    }),
  );
}
