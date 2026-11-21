import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'chart_semantics.dart';
import 'chart_color.dart';

import 'package:json_schema_builder/json_schema_builder.dart'
    hide ValidationResult;
import 'package:soliplex_catalogs/src/extended_chart.dart';
import 'package:soliplex_catalogs/src/gauge_chart.dart';
import 'package:soliplex_catalogs/src/line_chart.dart';
import 'package:soliplex_catalogs/src/surface_catalog.dart';

/// The graphics catalog with the typed, embeddable Chart component.
const chartGraphicsCatalogId = 'urn:soliplex:catalog:graphics:2';

const _maxPoints = 5000;
const int _maxSpecBytes = 1024 * 1024;
const _maxSafeInteger = 9007199254740991;

Map<String, Object> _string(int maxLength, {int minLength = 0}) => {
  'type': 'string',
  'minLength': minLength,
  'maxLength': maxLength,
};

const _rgba = <String, String>{
  'type': 'string',
  'pattern': r'^#[0-9a-fA-F]{8}$',
};

const int _maxSeries = 16;

final _pointListSchema = <String, Object>{
  'type': 'array',
  'maxItems': _maxPoints,
  'items': {
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'id': _string(128, minLength: 1),
      'label': _string(512),
      'value': {'type': 'number'},
    },
    'required': ['id', 'label', 'value'],
  },
};

final _chartCaptions = <String, Object>{
  'title': _string(512),
  'xlabel': _string(128),
  'ylabel': _string(128),
};

final _barSchema = <String, Object>{
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'kind': {'const': 'bar'},
    'points': _pointListSchema,
    'color': _rgba,
    ..._chartCaptions,
  },
  'required': ['kind', 'points'],
};

final _lineSchema = <String, Object>{
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'kind': {'const': 'line'},
    'series': {
      'type': 'array',
      'maxItems': _maxSeries,
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'id': _string(128, minLength: 1),
          'label': _string(512),
          'color': _rgba,
          'points': {
            ..._pointListSchema,
            'items': {
              ...(_pointListSchema['items']! as Map<String, Object>),
              'properties': {
                'id': _string(128, minLength: 1),
                'label': _string(512),
                'value': {
                  'type': ['number', 'null'],
                },
              },
            },
          },
        },
        'required': ['id', 'points'],
      },
    },
    ..._chartCaptions,
  },
  'required': ['kind', 'series'],
};

final _gaugeSchema = <String, Object>{
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'kind': {'const': 'gauge'},
    for (final key in ['value', 'min_value', 'max_value', 'target'])
      key: {'type': 'number'},
    'title': _string(512),
    'unit': _string(16),
  },
  'required': ['kind', 'value', 'min_value', 'max_value'],
};

/// Registers the embeddable charts and the existing graphics components.
CatalogImplementation chartGraphicsCatalog() => CatalogImplementation(
  id: chartGraphicsCatalogId,
  protocolVersion: A2uiProtocolVersion.v1_0,
  components: [
    ...chatGraphicsCatalog().components.values,
    ComponentImplementation(
      name: 'Chart',
      schema: Schema.fromMap({
        'type': 'object',
        'properties': {
          'spec': {
            'oneOf': [
              _barSchema,
              _lineSchema,
              _gaugeSchema,
              ...extendedChartSchemas.values,
            ],
          },
          'selection': {'type': 'array', 'maxItems': 0},
          'selected': CommonSchemasV1.dynamicString,
          'action': {r'$ref': r'common_types.json#/$defs/Action'},
          'weight': {'type': 'number'},
          'description': _string(512, minLength: 1),
          'height': {'type': 'number', 'minimum': 160, 'maximum': 1200},
        },
        'required': ['spec', 'selection', 'description'],
      }),
      builder: (context, node, props, buildChild) {
        final spec = props.value('spec');
        try {
          validateStaticChartSpec(spec);
        } on FormatException catch (error) {
          return Text('Invalid chart: ${error.message}');
        }
        final chart = spec! as Map<Object?, Object?>;
        final description = props.string('description')!;
        final height = props.number('height') ?? 280;
        final selected = props.writable('selected');
        final action = props.action('action');
        final chartView = KeyedSubtree(
          key: ValueKey(_chartIdentity(chart)),
          child: switch (chart['kind']) {
            'line' => StaticLineChart(
              spec: chart,
              description: description,
              height: height,
            ),
            'gauge' => StaticGaugeChart(
              spec: chart,
              description: description,
              height: height,
            ),
            'bar' => _BarChart(
              spec: chart,
              description: description,
              height: height,
              selected: props.string('selected'),
              onSelect: selected == null && action == null
                  ? null
                  : (label) {
                      selected?.set(label);
                      if (action != null) unawaited(action());
                    },
            ),
            _ => ExtendedChart(
              spec: chart,
              description: description,
              height: height,
            ),
          },
        );
        // Composed rows may give a child an unbounded width. Weighted columns
        // may constrain its height. Keep plots finite and scroll the chart when
        // the available height is smaller than its captions and plot.
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : 640.0;
            final content = chart['kind'] != 'bar' && width < 160
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: 160, child: chartView),
                  )
                : chartView;
            return SizedBox(
              width: width,
              child: SingleChildScrollView(primary: false, child: content),
            );
          },
        );
      },
    ),
  ],
);

/// Validates semantic bounds shared by the Express and Monty authoring routes.
void validateStaticChartSpec(Object? spec) {
  if (spec is! Map) throw const FormatException('Expected a chart spec.');
  switch (spec['kind']) {
    case 'bar':
      _pointLabels(spec['points']);
    case 'line':
      _validateLineSeries(spec['series']);
    case 'gauge':
      _validateGauge(spec);
    case final String kind when extendedChartSchemas.containsKey(kind):
      validateExtendedChart(spec.cast<Object?, Object?>(), kind);
    default:
      throw const FormatException('Unknown chart kind.');
  }
  if (utf8.encode(jsonEncode(spec)).length > _maxSpecBytes) {
    throw const FormatException('Chart spec exceeds 1 MiB.');
  }
}

void _validateGauge(Map<Object?, Object?> spec) {
  final min = spec['min_value'];
  final max = spec['max_value'];
  if (min is! num || max is! num) {
    throw const FormatException(
      'Gauge requires numeric min_value and max_value.',
    );
  }
  final span = max.toDouble() - min.toDouble();
  if (!span.isFinite || span <= 0) {
    throw const FormatException('Gauge requires finite min_value < max_value.');
  }
  for (final key in ['value', if (spec.containsKey('target')) 'target']) {
    final value = spec[key];
    if (value is! num || !value.isFinite || value < min || value > max) {
      throw FormatException(
        'Gauge $key must be between min_value and max_value.',
      );
    }
  }
}

List<String> _pointLabels(Object? points, {bool allowGaps = false}) {
  if (points is! List || points.length > _maxPoints) {
    throw const FormatException('Expected a list of at most 5000 points.');
  }
  final ids = <String>{};
  final labels = <String>[];
  for (final point in points) {
    if (point
        case {
          'id': final String id,
          'label': final String label,
          'value': final Object? value,
        }
        when id.isNotEmpty &&
            ((allowGaps && value == null) ||
                // Same bound as the server; dart2js cannot tell 1e100 from an int.
                (value is num &&
                    value.isFinite &&
                    value.abs() <= _maxSafeInteger))) {
      if (!ids.add(id)) throw FormatException('Duplicate point ID: $id.');
      labels.add(label);
    } else {
      throw const FormatException(
        'Points require IDs, labels and finite, JSON-safe numeric values.',
      );
    }
  }
  return labels;
}

void _validateLineSeries(Object? series) {
  if (series is! List || series.length > _maxSeries) {
    throw const FormatException('Expected a list of at most 16 line series.');
  }
  final ids = <String>{};
  List<String>? categories;
  var total = 0;
  for (final entry in series) {
    if (entry is! Map || entry['id'] is! String) {
      throw const FormatException('Each line series requires an ID.');
    }
    final id = entry['id']! as String;
    if (id.isEmpty || !ids.add(id)) {
      throw FormatException('Invalid or duplicate series ID: $id.');
    }
    final labels = _pointLabels(entry['points'], allowGaps: true);
    total += labels.length;
    if (total > _maxPoints) {
      throw const FormatException('A chart accepts at most 5000 points.');
    }
    categories ??= labels;
    if (!listEquals(categories, labels)) {
      throw const FormatException('Line series must have matching categories.');
    }
  }
}

// fl_chart interpolates by position. Changing a series or point order
// remounts the chart at its new values instead of interpolating different IDs.
String _chartIdentity(Map<Object?, Object?> spec) {
  if (extendedChartSchemas.containsKey(spec['kind'])) {
    return extendedChartIdentity(spec);
  }
  List<Object?> ids(Object? points) => [
    for (final point in points! as List<Object?>)
      (point! as Map<Object?, Object?>)['id'],
  ];
  return jsonEncode([
    spec['kind'],
    if (spec['kind'] == 'bar')
      ids(spec['points'])
    else if (spec['kind'] == 'gauge')
      [spec['min_value'], spec['max_value'], spec.containsKey('target')]
    else
      for (final item
          in (spec['series']! as List<Object?>).cast<Map<Object?, Object?>>())
        [
          item['id'],
          ids(item['points']),
          for (final point in item['points']! as List)
            (point as Map)['value'] == null,
        ],
  ]);
}

class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.spec,
    required this.description,
    required this.height,
    this.selected,
    this.onSelect,
  });

  final String? selected;
  final ValueChanged<String>? onSelect;
  final Map<Object?, Object?> spec;
  final String description;
  final double height;

  @override
  Widget build(BuildContext context) {
    final points = (spec['points']! as List).cast<Map<Object?, Object?>>();
    final colors = Theme.of(context).colorScheme;
    final color = chartColor(spec['color'], 0, colors);
    final textTheme = Theme.of(context).textTheme;
    var low = 0.0;
    var high = 0.0;
    for (final point in points) {
      final value = (point['value']! as num).toDouble();
      low = math.min(low, value);
      high = math.max(high, value);
    }
    // Normalize before subtracting so even very large finite values fit.
    final magnitude = math.max(math.max(-low, high), 1);
    final diverges = low < 0 && high > 0;
    final start = diverges ? -1.0 : low / magnitude;
    final end = diverges || low == high ? 1.0 : high / magnitude;

    // The subtitle repeats nothing: Python charts default description to title.
    final caption = (spec['xlabel'] ?? spec['ylabel'] ?? description) as String;
    final subtitle = caption == spec['title'] ? null : caption;
    return Semantics(
      container: true,
      label: chartSemanticsLabel(spec, description),
      image: onSelect == null,
      explicitChildNodes: onSelect != null,
      excludeSemantics: onSelect == null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(context.radii.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (spec['title'] case final String title)
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (subtitle != null) ...[
                const SizedBox(height: SoliplexSpacing.s1),
                Text(
                  subtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: SoliplexSpacing.s3),
              if (points.isEmpty)
                const Text('No data')
              else
                SizedBox(
                  height: math.min(height, points.length * 59),
                  child: ListView.builder(
                    primary: false,
                    itemExtent: 59,
                    itemCount: points.length,
                    itemBuilder: (context, index) {
                      final point = points[index];
                      final value = point['value']! as num;
                      final negative = value < 0;
                      final label = point['label']! as String;
                      final barColor = label == selected
                          ? colors.tertiary
                          : negative
                          ? colors.error
                          : color;
                      final row = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  point['label']! as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.labelLarge,
                                ),
                              ),
                              const SizedBox(width: SoliplexSpacing.s2),
                              Flexible(
                                child: Text(
                                  value > 0 && diverges
                                      ? '+${chartNumber(value)}'
                                      : chartNumber(value),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.labelLarge?.copyWith(
                                    color: negative
                                        ? colors.error
                                        : colors.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: SoliplexSpacing.s2),
                          SizedBox(
                            height: 20,
                            // Adapted from HHG's fl_chart bar preview.
                            child: BarChart(
                              BarChartData(
                                minY: start,
                                maxY: end,
                                rotationQuarterTurns: 1,
                                titlesData: const FlTitlesData(show: false),
                                gridData: const FlGridData(show: false),
                                borderData: FlBorderData(show: false),
                                barTouchData: const BarTouchData(
                                  enabled: false,
                                ),
                                extraLinesData: ExtraLinesData(
                                  horizontalLines: [
                                    HorizontalLine(y: 0, color: colors.outline),
                                  ],
                                ),
                                barGroups: [
                                  BarChartGroupData(
                                    x: 0,
                                    barRods: [
                                      BarChartRodData(
                                        toY: value.toDouble() / magnitude,
                                        color: barColor,
                                        width: 14,
                                        borderRadius: BorderRadius.circular(
                                          context.radii.sm,
                                        ),
                                        backDrawRodData:
                                            BackgroundBarChartRodData(
                                              show: true,
                                              fromY: start,
                                              toY: end,
                                              color: colors
                                                  .surfaceContainerHighest,
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 150),
                            ),
                          ),
                        ],
                      );
                      if (onSelect == null) return row;
                      return Semantics(
                        container: true,
                        label: 'Bar $label: ${chartNumber(value)}',
                        button: true,
                        selected: label == selected,
                        excludeSemantics: true,
                        onTap: () => onSelect!(label),
                        child: InkWell(
                          key: ValueKey('chart-bar:$label'),
                          onTap: () => onSelect!(label),
                          child: row,
                        ),
                      );
                    },
                  ),
                ),
              if (diverges && !points.any((point) => point['value'] == 0))
                Center(
                  child: Text(
                    '0',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
