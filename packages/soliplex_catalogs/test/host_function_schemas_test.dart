import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';

void main() {
  test('scatter extensions reach Python as JSON Schema boolean entries', () {
    final modules = hostFunctionSchemas();
    final scatter = modules['chart']!.singleWhere(
      (s) => s['name'] == 'scatter',
    );
    final parameters = scatter['parameters']! as Map;
    final props = parameters['properties']! as Map;
    final reversed = (props['y_reversed']! as Map)['anyOf']! as List;
    expect((reversed.first as Map)['type'], 'boolean');
    final series =
        (((props['series']! as Map)['items']! as Map)['properties']! as Map);
    expect(series['line'], {'type': 'boolean'});
    final point =
        (((series['points']! as Map)['items']! as Map)['properties']! as Map);
    expect(point['highlight'], {'type': 'boolean'});
  });

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
