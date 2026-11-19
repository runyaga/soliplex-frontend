import 'package:a2ui_core/a2ui_core.dart';
import 'package:json_schema_builder/json_schema_builder.dart'
    hide ValidationResult;

/// Catalog of the chart components the Python `ui` module adds.
const labChartCatalogId = 'urn:soliplex:catalog:lab-chart:1';

/// Positional order of the chart constructors in the Python `ui` module.
const labChartSignatures = <String, List<String>>{
  'BarChart': ['bars', 'title', 'action', 'weight'],
  'LineChart': ['labels', 'series', 'title', 'weight'],
};

/// Most bars one `BarChart` draws.
const maxChartBars = 32;

/// Most points and lines one `LineChart` draws.
const maxLinePoints = 500;
const maxLineSeries = 6;

/// Properties of the lab `BarChart`. Bar lengths scale to the largest value;
/// values have no fixed cap.
Schema barChartSchema() => Schema.object(
  properties: {
    'bars': Schema.fromMap({
      'type': 'array',
      'minItems': 1,
      'maxItems': maxChartBars,
      'items': {
        'type': 'object',
        'properties': {
          'label': {'type': 'string', 'maxLength': 60},
          'value': {'type': 'number'},
        },
        'required': ['label', 'value'],
        'additionalProperties': false,
      },
    }),
    'title': Schema.string(maxLength: 120),
    'selected': CommonSchemasV1.dynamicString,
    'action': Schema.fromMap({r'$ref': r'common_types.json#/$defs/Action'}),
    'weight': Schema.number(),
  },
  required: ['bars'],
);

/// Properties of the lab `LineChart`: one x label per point, and up to
/// [maxLineSeries] series whose `values` line up with `labels`. A null value
/// leaves a gap.
Schema lineChartSchema() => Schema.object(
  properties: {
    'labels': Schema.fromMap({
      'type': 'array',
      'minItems': 2,
      'maxItems': maxLinePoints,
      'items': {'type': 'string', 'maxLength': 60},
    }),
    'series': Schema.fromMap({
      'type': 'array',
      'minItems': 1,
      'maxItems': maxLineSeries,
      'items': {
        'type': 'object',
        'properties': {
          'label': {'type': 'string', 'maxLength': 60},
          'values': {'type': 'array', 'maxItems': maxLinePoints},
        },
        'required': ['label', 'values'],
        'additionalProperties': false,
      },
    }),
    'title': Schema.string(maxLength: 120),
    'weight': Schema.number(),
  },
  required: ['labels', 'series'],
);

/// `(label, value)` pairs from [raw], or null unless there are 1 to
/// [maxChartBars] bars and every value is a finite number of at least zero.
List<(String, double)>? chartBars(List<Object?> raw) {
  final bars = <(String, double)>[];
  for (final bar in raw) {
    if (bar case {
      'label': final String label,
      'value': final num value,
    } when value.isFinite && value >= 0) {
      bars.add((label, value.toDouble()));
    } else {
      return null;
    }
  }
  return bars.isEmpty || bars.length > maxChartBars ? null : bars;
}

/// One line of a `LineChart`; a null value is a gap.
typedef LineSeries = ({String label, List<double?> values});

/// The series in [raw], or null unless each has exactly [points] values
/// that are finite numbers or null, and at least one value is a number.
List<LineSeries>? lineSeries(List<Object?> raw, int points) {
  final series = <LineSeries>[];
  var any = false;
  for (final item in raw) {
    if (item case {
      'label': final String label,
      'values': final List<Object?> values,
    } when values.length == points) {
      final parsed = <double?>[];
      for (final v in values) {
        if (v == null) {
          parsed.add(null);
        } else if (v is num && v.isFinite) {
          parsed.add(v.toDouble());
          any = true;
        } else {
          return null;
        }
      }
      series.add((label: label, values: parsed));
    } else {
      return null;
    }
  }
  if (series.isEmpty || series.length > maxLineSeries || !any) return null;
  return series;
}

/// Why the chart [component] is invalid beyond its schema, or null.
String? chartComponentError(Map<String, Object?> component) {
  switch (component['component']) {
    case 'BarChart':
      final bars = component['bars'];
      if (bars is List && bars.isEmpty) {
        return 'BarChart got no bars. Check the column names, and that '
            'rows were not all skipped.';
      }
      if (bars is! List || chartBars(bars) == null) {
        return 'BarChart bars must be 1 to $maxChartBars '
            '{"label": str, "value": number >= 0} dicts.';
      }
    case 'LineChart':
      final labels = component['labels'];
      final series = component['series'];
      if (labels is! List ||
          labels.length < 2 ||
          series is! List ||
          series.isEmpty ||
          lineSeries(series, labels.length) == null) {
        return 'LineChart takes 2 to $maxLinePoints labels and 1 to '
            '$maxLineSeries {"label": str, "values": [number or None]} '
            'dicts, each with one value per label.';
      }
  }
  return null;
}
