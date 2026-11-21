import 'package:dart_monty/core.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';

import 'package:soliplex_monty/src/bindings/registered_module.dart';

/// Creates the Monty `chart` module. Builders return plain chart spec dicts.
ExternalModule chartModule() => registerBindings(
  'chart',
  ExternalModule({
    'bar': _builder('bar'),
    'line': _builder('line'),
    'gauge': _builder('gauge'),
    'scatter': _builder('scatter'),
    'pie': _builder('pie'),
    'radar': _builder('radar'),
    'candlestick': _builder('candlestick'),
  }),
);

MontyHostFunction _builder(String kind) =>
    MontyHostFunction(kind, (positional, keywords) {
      final args = {
        for (final entry in keywords.entries) entry.key: entry.value.dartValue,
      };
      final spec = <String, Object?>{
        'kind': kind,
        for (final entry in args.entries)
          if (entry.value != null) entry.key: entry.value,
      };
      try {
        validateStaticChartSpec(spec);
      } on FormatException catch (error) {
        throw ExternalException('ValueError', error.message);
      }
      return MontyValue.fromDart(spec);
    });
