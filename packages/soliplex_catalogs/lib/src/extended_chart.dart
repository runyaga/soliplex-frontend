import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'chart_semantics.dart';
import 'chart_format.dart';
import 'chart_color.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

const _number = {'type': 'number'};
const _color = {'type': 'string', 'pattern': r'^#[0-9a-fA-F]{8}$'};
const Map<String, Object> _label = {'type': 'string', 'maxLength': 512};
const Map<String, Object> _id = {
  'type': 'string',
  'minLength': 1,
  'maxLength': 128,
};

Map<String, Object> _object(
  Map<String, Object> properties,
  List<String> required,
) => {
  'type': 'object',
  'additionalProperties': false,
  'properties': properties,
  'required': required,
};

Map<String, Object> _list(Object items, int max, {int min = 0}) => {
  'type': 'array',
  'items': items,
  'maxItems': max,
  'minItems': min,
};

final Map<String, Object> _scatterPoints = _list(
  _object(
    {
      'id': _id,
      'x': _number,
      'y': _number,
      'label': _label,
      'highlight': {'type': 'boolean'},
    },
    ['id', 'x', 'y'],
  ),
  5000,
);

/// Schemas for chart kinds introduced after bar, line and gauge.
final extendedChartSchemas = <String, Map<String, Object>>{
  'scatter': _spec(
    'scatter',
    {
      'y_reversed': {'type': 'boolean'},
      'series': _list(
        _object(
          {
            'id': _id,
            'label': _label,
            'color': _color,
            'points': _scatterPoints,
            'line': {'type': 'boolean'},
          },
          ['id', 'points'],
        ),
        16,
      ),
    },
    ['series'],
    axis: true,
  ),
  'pie': _spec(
    'pie',
    {
      'slices': _list(
        _object(
          {'id': _id, 'label': _label, 'value': _number, 'color': _color},
          ['id', 'label', 'value'],
        ),
        32,
      ),
    },
    ['slices'],
  ),
  'radar': _spec(
    'radar',
    {
      'axes': _list(
        _object({'id': _id, 'label': _label}, ['id', 'label']),
        12,
        min: 3,
      ),
      'series': _list(
        _object(
          {
            'id': _id,
            'label': _label,
            'color': _color,
            'values': _list(_number, 12),
          },
          ['id', 'values'],
        ),
        16,
      ),
    },
    ['axes', 'series'],
  ),
  'candlestick': _spec(
    'candlestick',
    {
      'candles': _list(
        _object(
          {
            'id': _id,
            for (final key in ['x', 'open', 'high', 'low', 'close'])
              key: _number,
          },
          ['id', 'x', 'open', 'high', 'low', 'close'],
        ),
        5000,
      ),
    },
    ['candles'],
    axis: true,
  ),
};

Map<String, Object> _spec(
  String kind,
  Map<String, Object> data,
  List<String> required, {
  bool axis = false,
}) => _object(
  {
    'kind': {'const': kind},
    'title': _label,
    if (axis) ...{'xlabel': _label, 'ylabel': _label},
    ...data,
  },
  ['kind', ...required],
);

typedef _Record = Map<Object?, Object?>;

List<_Record> _rows(Object? value) => (value! as List<Object?>).cast<_Record>();
double _value(_Record row, String key) => (row[key]! as num).toDouble();

/// Validates structure, identity and numeric invariants before rendering.
void validateExtendedChart(Map<Object?, Object?> spec, String kind) {
  final schema = Schema.fromMap(extendedChartSchemas[kind]!);
  final errors = schema.validateSync(stringKeyedChart(spec));
  if (errors.isNotEmpty) {
    throw FormatException('Invalid $kind spec: ${errors.first}');
  }
  switch (kind) {
    case 'scatter':
      final series = _rows(spec['series']);
      _uniqueIds(series);
      var count = 0;
      for (final entry in series) {
        final points = _rows(entry['points']);
        _uniqueIds(points);
        count += points.length;
        for (final point in points) {
          _finite(point['x']);
          _finite(point['y']);
        }
      }
      if (count > 5000) {
        throw const FormatException('Scatter accepts at most 5000 points.');
      }
    case 'pie':
      final slices = _rows(spec['slices']);
      _uniqueIds(slices);
      for (final slice in slices) {
        if (_finite(slice['value']) < 0) {
          throw const FormatException('Pie slices must be nonnegative.');
        }
      }
    case 'radar':
      final axes = _rows(spec['axes']);
      final series = _rows(spec['series']);
      _uniqueIds(axes);
      _uniqueIds(series);
      for (final entry in series) {
        final values = entry['values']! as List<Object?>;
        if (values.length != axes.length) {
          throw const FormatException('Radar requires one value per axis.');
        }
        for (final item in values) {
          final value = _finite(item);
          if (value < 0 || value > 100) {
            throw const FormatException(
              'Radar values must use a shared 0–100 scale.',
            );
          }
        }
      }
    case 'candlestick':
      final candles = _rows(spec['candles']);
      _uniqueIds(candles);
      var previousX = double.negativeInfinity;
      for (final candle in candles) {
        final x = _finite(candle['x']);
        final open = _finite(candle['open']);
        final high = _finite(candle['high']);
        final low = _finite(candle['low']);
        final close = _finite(candle['close']);
        if (x <= previousX ||
            low > math.min(open, close) ||
            high < math.max(open, close)) {
          throw const FormatException(
            'Candles require increasing x and valid OHLC bounds.',
          );
        }
        previousX = x;
      }
  }
}

/// Copies a chart JSON tree, rejecting non-string object keys.
Object? stringKeyedChart(Object? value) {
  if (value is Map<Object?, Object?>) {
    final out = <String, Object?>{};
    for (final MapEntry(:key, value: entry) in value.entries) {
      if (key is! String) {
        throw const FormatException('Chart fields must have string keys.');
      }
      out[key] = stringKeyedChart(entry);
    }
    return out;
  }
  if (value is List<Object?>) return value.map(stringKeyedChart).toList();
  return value;
}

/// Whether a numeric chart value is exactly representable on every backend.
bool isSafeChartNumber(Object? value) =>
    value is num &&
    value.isFinite &&
    value >= -9007199254740991 &&
    value <= 9007199254740991;

double _finite(Object? item) {
  if (!isSafeChartNumber(item)) {
    throw const FormatException(
      'Expected a finite number in the JSON-safe range.',
    );
  }
  return (item! as num).toDouble();
}

void _uniqueIds(List<_Record> rows) {
  final ids = <Object?>{};
  for (final row in rows) {
    if (!ids.add(row['id'])) {
      throw FormatException('Duplicate ID: ${row['id']}.');
    }
  }
}

/// Identifies the items fl_chart will interpolate in list order.
String extendedChartIdentity(Map<Object?, Object?> spec) {
  List<Object?> ids(Object? rows) =>
      _rows(rows).map((row) => row['id']).toList();
  return jsonEncode([
    spec['kind'],
    switch (spec['kind']) {
      'pie' => ids(spec['slices']),
      'radar' => [ids(spec['axes']), ids(spec['series'])],
      'scatter' => [
        for (final series in _rows(spec['series']))
          [series['id'], ids(series['points'])],
      ],
      _ => ids(spec['candles']),
    },
  ]);
}

/// Draws a validated extended chart with fl_chart.
class ExtendedChart extends StatelessWidget {
  const ExtendedChart({
    required this.spec,
    required this.description,
    required this.height,
    super.key,
  });

  final Map<Object?, Object?> spec;
  final String description;
  final double height;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 150);
    final theme = Theme.of(context);
    final (plot, entries) = switch (spec['kind']) {
      'scatter' => _scatter(duration, theme.colorScheme),
      'pie' => _pie(duration, theme.colorScheme),
      'radar' => _radar(duration, theme),
      _ => _candles(duration, theme.colorScheme),
    };
    return Semantics(
      container: true,
      label: chartSemanticsLabel(spec, description),
      image: true,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(context.radii.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (spec['title'] case final String title)
                Text(title, style: theme.textTheme.titleMedium),
              if (spec['ylabel'] case final String label)
                Text(label, style: theme.textTheme.bodySmall),
              const SizedBox(height: SoliplexSpacing.s3),
              if (plot == null)
                const Text('No data')
              else ...[
                SizedBox(height: height, child: plot),
                if (spec['xlabel'] case final String label)
                  Center(child: Text(label, style: theme.textTheme.bodySmall)),
              ],
              if (entries.isNotEmpty)
                Wrap(
                  spacing: SoliplexSpacing.s4,
                  runSpacing: SoliplexSpacing.s2,
                  children: [
                    for (final (label, color) in entries)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 9, color: color),
                          const SizedBox(width: SoliplexSpacing.s2),
                          Flexible(
                            child: Text(
                              label,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  (Widget?, List<(String, Color)>) _scatter(
    Duration duration,
    ColorScheme colors,
  ) {
    final series = _rows(spec['series']);
    // fl_chart draws larger values higher, so a reversed axis plots -y and
    // labels each tick with its negation.
    final sign = spec['y_reversed'] == true ? -1.0 : 1.0;
    final points = [
      for (final entry in series)
        [
          for (final row in _rows(entry['points']))
            (_value(row, 'x'), sign * _value(row, 'y'), row['highlight']),
        ],
    ];
    if (points.every((list) => list.isEmpty)) return (null, []);
    final (minX, maxX) = _extent(points.expand((l) => l.map((p) => p.$1)));
    final (minY, maxY) = _extent(points.expand((l) => l.map((p) => p.$2)));
    final titles = sign < 0
        ? _titles.copyWith(
            leftTitles: AxisTitles(
              sideTitles: _titles.leftTitles.sideTitles.copyWith(
                getTitlesWidget: _reversedAxisLabel,
              ),
            ),
          )
        : _titles;
    FlDotCirclePainter dot(int index, {required bool highlight}) =>
        FlDotCirclePainter(
          color: _seriesColor(series[index], index, colors),
          radius: highlight ? 7 : 4,
          strokeWidth: highlight ? 2 : 0,
          strokeColor: highlight ? colors.onSurface : Colors.transparent,
        );
    if (!series.any((entry) => entry['line'] == true)) {
      return (
        ScatterChart(
          ScatterChartData(
            scatterSpots: [
              for (var i = 0; i < series.length; i++)
                for (final (x, y, highlight) in points[i])
                  ScatterSpot(
                    x,
                    y,
                    dotPainter: dot(i, highlight: highlight == true),
                  ),
            ],
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            titlesData: titles,
            borderData: FlBorderData(show: false),
            scatterTouchData: ScatterTouchData(enabled: false),
          ),
          duration: duration,
        ),
        _legend(series, colors),
      );
    }
    return (
      LineChart(
        LineChartData(
          lineBarsData: [
            for (var i = 0; i < series.length; i++)
              LineChartBarData(
                spots: [for (final (x, y, _) in points[i]) FlSpot(x, y)],
                color: _seriesColor(series[i], i, colors),
                barWidth: series[i]['line'] == true ? 2.5 : 0,
                dotData: FlDotData(
                  getDotPainter: (spot, _, _, index) =>
                      dot(i, highlight: points[i][index].$3 == true),
                ),
              ),
          ],
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          titlesData: titles,
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
        ),
        duration: duration,
      ),
      _legend(series, colors),
    );
  }

  (Widget?, List<(String, Color)>) _pie(Duration duration, ColorScheme colors) {
    final slices = _rows(spec['slices']);
    if (!slices.any((slice) => _value(slice, 'value') > 0)) return (null, []);
    return (
      LayoutBuilder(
        builder: (context, constraints) {
          final radius =
              math.min(constraints.maxWidth, constraints.maxHeight) / 2;
          return PieChart(
            PieChartData(
              sections: [
                for (var i = 0; i < slices.length; i++)
                  PieChartSectionData(
                    value: _value(slices[i], 'value'),
                    color: _seriesColor(slices[i], i, colors),
                    showTitle: false,
                    radius: radius * 0.52,
                  ),
              ],
              centerSpaceRadius: radius * 0.48,
              pieTouchData: PieTouchData(enabled: false),
            ),
            duration: duration,
          );
        },
      ),
      [
        for (var i = 0; i < slices.length; i++)
          (
            "${slices[i]['label']} · ${slices[i]['value']}",
            _seriesColor(slices[i], i, colors),
          ),
      ],
    );
  }

  (Widget?, List<(String, Color)>) _radar(Duration duration, ThemeData theme) {
    final colors = theme.colorScheme;
    final axes = _rows(spec['axes']);
    final series = _rows(spec['series']);
    if (series.isEmpty) return (null, []);
    return (
      RadarChart(
        RadarChartData(
          isMinValueAtCenter: true,
          tickCount: 4,
          titleTextStyle: theme.textTheme.labelSmall,
          getTitle: (index, angle) =>
              RadarChartTitle(text: axes[index]['label']! as String),
          radarTouchData: RadarTouchData(enabled: false),
          dataSets: [
            // A transparent series fixes the scale at 0–100.
            RadarDataSet(
              dataEntries: [
                for (var i = 0; i < axes.length; i++)
                  RadarEntry(value: i == 0 ? 0 : 100),
              ],
              fillColor: Colors.transparent,
              borderColor: Colors.transparent,
              entryRadius: 0,
            ),
            for (var i = 0; i < series.length; i++)
              RadarDataSet(
                dataEntries: [
                  for (final value
                      in (series[i]['values']! as List<Object?>).cast<num>())
                    RadarEntry(value: value.toDouble()),
                ],
                fillColor: _seriesColor(
                  series[i],
                  i,
                  colors,
                ).withValues(alpha: 0.16),
                borderColor: _seriesColor(series[i], i, colors),
              ),
          ],
        ),
        duration: duration,
      ),
      _legend(series, colors),
    );
  }

  (Widget?, List<(String, Color)>) _candles(
    Duration duration,
    ColorScheme colors,
  ) {
    final candles = _rows(spec['candles']);
    if (candles.isEmpty) return (null, []);
    final (minX, maxX) = _extent(candles.map((row) => _value(row, 'x')));
    final (minY, maxY) = _extent([
      for (final row in candles) ...[_value(row, 'low'), _value(row, 'high')],
    ]);
    return (
      CandlestickChart(
        CandlestickChartData(
          candlestickSpots: [
            for (final row in candles)
              CandlestickSpot(
                x: _value(row, 'x'),
                open: _value(row, 'open'),
                high: _value(row, 'high'),
                low: _value(row, 'low'),
                close: _value(row, 'close'),
              ),
          ],
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          titlesData: _titles,
          borderData: FlBorderData(show: false),
          candlestickTouchData: CandlestickTouchData(enabled: false),
          candlestickPainter: DefaultCandlestickPainter(
            candlestickStyleProvider: (spot, _) {
              final color = spot.close >= spot.open
                  ? colors.primary
                  : colors.error;
              return CandlestickStyle(
                lineColor: color,
                lineWidth: 1.4,
                bodyStrokeColor: color,
                bodyStrokeWidth: 0,
                bodyFillColor: color,
                bodyWidth: candles.length <= 16 ? 9 : 3,
                bodyRadius: 2,
              );
            },
          ),
        ),
        duration: duration,
      ),
      [],
    );
  }
}

const _titles = FlTitlesData(
  topTitles: AxisTitles(),
  rightTitles: AxisTitles(),
  leftTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: 48,
      minIncluded: false,
      maxIncluded: false,
      getTitlesWidget: _axisLabel,
    ),
  ),
  bottomTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: 28,
      minIncluded: false,
      maxIncluded: false,
      getTitlesWidget: _axisLabel,
    ),
  ),
);

Widget _axisLabel(double value, TitleMeta meta) => SideTitleWidget(
  meta: meta,
  fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
  child: Builder(
    builder: (context) => Text(
      meta.formattedValue,
      style: Theme.of(context).textTheme.labelSmall,
    ),
  ),
);

Widget _reversedAxisLabel(double value, TitleMeta meta) => SideTitleWidget(
  meta: meta,
  fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
  child: Builder(
    builder: (context) => Text(
      chartNumberText(-value),
      style: Theme.of(context).textTheme.labelSmall,
    ),
  ),
);

(double, double) _extent(Iterable<double> values) {
  final low = values.reduce(math.min);
  final high = values.reduce(math.max);
  final padding = high == low
      ? math.max(1, low.abs() * 0.1).toDouble()
      : (high - low) * 0.08;
  return (low - padding, high + padding);
}

List<(String, Color)> _legend(List<_Record> series, ColorScheme colors) => [
  for (var i = 0; i < series.length; i++)
    (
      (series[i]['label'] ?? series[i]['id'])! as String,
      _seriesColor(series[i], i, colors),
    ),
];

Color _seriesColor(_Record row, int index, ColorScheme scheme) =>
    chartColor(row['color'], index, scheme);
