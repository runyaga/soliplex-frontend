import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'chart_semantics.dart';

/// Renders a validated static line spec using the HHG fl_chart approach.
class StaticLineChart extends StatelessWidget {
  const StaticLineChart({
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
    final series = (spec['series']! as List).cast<Map<Object?, Object?>>();
    final points = [
      for (final item in series)
        (item['points']! as List).cast<Map<Object?, Object?>>(),
    ];
    final categories = [
      for (final point in points.firstOrNull ?? const <Map<Object?, Object?>>[])
        point['label']! as String,
    ];
    final palette = [
      for (var i = 0; i < series.length; i++)
        _color(series[i]['color'], i, Theme.of(context).colorScheme),
    ];
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      container: true,
      label: chartSemanticsLabel(spec, description),
      image: true,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(context.radii.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (spec['title'] case final String title)
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (spec['ylabel'] case final String caption)
                Text(caption, style: theme.textTheme.bodySmall),
              const SizedBox(height: SoliplexSpacing.s3),
              if (categories.isEmpty)
                const Text('No data')
              else ...[
                Wrap(
                  spacing: SoliplexSpacing.s4,
                  runSpacing: SoliplexSpacing.s2,
                  children: [
                    for (var i = 0; i < series.length; i++)
                      _Legend(
                        color: palette[i],
                        label:
                            (series[i]['label'] ?? series[i]['id'])! as String,
                      ),
                  ],
                ),
                const SizedBox(height: SoliplexSpacing.s4),
                SizedBox(
                  height: height,
                  child: LayoutBuilder(
                    builder: (context, constraints) => _plot(
                      context,
                      points,
                      categories,
                      palette,
                      constraints.maxWidth,
                    ),
                  ),
                ),
                if (spec['xlabel'] case final String caption)
                  Center(
                    child: Text(caption, style: theme.textTheme.bodySmall),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _plot(
    BuildContext context,
    List<List<Map<Object?, Object?>>> points,
    List<String> categories,
    List<Color> palette,
    double width,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final labelStyle = theme.textTheme.labelSmall;
    var magnitude = 1.0;
    var hasNegative = false;
    var hasPositive = false;
    for (final series in points) {
      for (final point in series) {
        final value = (point['value']! as num).toDouble();
        magnitude = math.max(magnitude, value.abs());
        hasNegative |= value < 0;
        hasPositive |= value > 0;
      }
    }
    final interval = math.max(
      1,
      (categories.length / math.max(2, width ~/ 50)).ceil(),
    );
    return LineChart(
      LineChartData(
        minX: categories.length == 1 ? -0.5 : 0,
        maxX: categories.length == 1 ? 0.5 : categories.length - 1,
        minY: hasNegative ? -1.05 : 0,
        maxY: hasPositive || !hasNegative ? 1.05 : 0,
        lineTouchData: const LineTouchData(enabled: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: 0.5,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: colors.outlineVariant, strokeWidth: 1),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(y: 0, color: colors.outline, dashArray: [5, 4]),
          ],
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: 0.5,
              minIncluded: false,
              maxIncluded: false,
              getTitlesWidget: (value, _) =>
                  Text(_tick(value * magnitude), style: labelStyle),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: interval.toDouble(),
              minIncluded: categories.length > 1,
              maxIncluded: false,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i != value || i < 0 || i >= categories.length) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 48),
                    child: Text(
                      categories[i],
                      style: labelStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          for (var i = 0; i < points.length; i++)
            LineChartBarData(
              spots: [
                for (var j = 0; j < points[i].length; j++)
                  FlSpot(
                    j.toDouble(),
                    (points[i][j]['value']! as num) / magnitude,
                  ),
              ],
              color: palette[i],
              barWidth: 2.5,
              dotData: FlDotData(show: categories.length <= 12),
              dashArray: i.isOdd ? [6, 4] : null,
            ),
        ],
      ),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 150),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.circle, size: 9, color: color),
      const SizedBox(width: SoliplexSpacing.s2),
      Flexible(
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
    ],
  );
}

Color _color(Object? value, int index, ColorScheme scheme) {
  if (value case final String rgba) {
    return Color(
      (int.parse(rgba.substring(7), radix: 16) << 24) |
          int.parse(rgba.substring(1, 7), radix: 16),
    );
  }
  final palette = [
    scheme.primary,
    scheme.secondary,
    scheme.tertiary,
    scheme.outline,
  ];
  return palette[index % palette.length];
}

String _tick(double value) {
  if (value.abs() >= 10000) return value.toStringAsExponential(0);
  return value == value.truncateToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}
