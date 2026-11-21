import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';

void main() {
  test('host entries are pure JSON and preserve the A2UI function format', () {
    final modules = hostFunctionSchemas();
    expect(jsonDecode(jsonEncode(modules)), modules);
    expect(jsonDecode(jsonEncode(hostValueDefinitions)), hostValueDefinitions);
    for (final entry in modules.entries) {
      final catalog = Catalog.fromJson({
        'catalogId': 'urn:test:${entry.key}',
        'protocolVersion': '1.0',
        r'$defs': hostValueDefinitions,
        'functions': entry.value,
      });
      expect(catalog.functions.length, entry.value.length);
      for (final schema in entry.value) {
        final api = catalog.functions[schema['name']]!;
        expect(api.definition, schema);
        expect(api.argumentSchema.value, schema['parameters']);
        expect(api.returnType.jsonValue, schema['returnType']);
      }
    }
    // A bind function's argument object must not become a binding token.
    final bind = modules['ui']!.singleWhere((entry) => entry['name'] == 'bind');
    expect(bind['parameters'], uiHostFunctionSchemas.first['parameters']);
  });
}
