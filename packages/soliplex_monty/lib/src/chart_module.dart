import 'package:dart_monty/core.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';

/// Creates the Monty `chart` module. Builders return plain chart spec dicts.
ExternalModule chartModule() => ExternalModule({
  'bar': _builder('bar', 'points', color: true),
  'line': _builder('line', 'series'),
  'gauge': _builder('gauge', 'value'),
  'scatter': _builder('scatter', 'series'),
  'pie': _builder('pie', 'slices'),
  'radar': _builder('radar', 'series'),
  'candlestick': _builder('candlestick', 'candles'),
});

MontyHostFunction _builder(String kind, String dataKey, {bool color = false}) =>
    MontyHostFunction(kind, (positional, keywords) {
      final name = 'chart.$kind';
      final gauge = kind == 'gauge';
      final optional = {
        'title',
        if (gauge) 'unit',
        if (!gauge && kind != 'pie' && kind != 'radar') ...['xlabel', 'ylabel'],
        if (color) 'color',
      };
      final numeric = {
        if (gauge) ...['min_value', 'max_value', 'target'],
      };
      final dataKeys = [if (kind == 'radar') 'axes', dataKey];
      if (positional.length > dataKeys.length ||
          dataKeys.take(positional.length).any(keywords.containsKey)) {
        throw ExternalException(
          'TypeError',
          '$name expects ${dataKeys.join(', ')}.',
        );
      }
      final spec = <String, Object?>{
        'kind': kind,
        for (var i = 0; i < positional.length; i++)
          dataKeys[i]: positional[i].dartValue,
      };
      for (final MapEntry(:key, :value) in keywords.entries) {
        if (dataKeys.contains(key)) {
          spec[key] = value.dartValue;
        } else if (numeric.contains(key)) {
          if (key != 'target' || value.dartValue != null) {
            spec[key] = value.dartValue;
          }
        } else if (optional.contains(key)) {
          switch (value.dartValue) {
            case null:
              break;
            case final String text:
              spec[key] = text;
            default:
              throw ExternalException('TypeError', '$name: $key must be text.');
          }
        } else {
          throw ExternalException('TypeError', '$name has no $key argument.');
        }
      }
      try {
        validateStaticChartSpec(spec);
      } on FormatException catch (error) {
        throw ExternalException('ValueError', error.message);
      }
      return MontyValue.fromDart(spec);
    });
