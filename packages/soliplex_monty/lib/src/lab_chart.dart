import 'dart:async';
import 'dart:math' as math;

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_monty/src/lab_chart_api.dart';

/// The lab `BarChart` and `LineChart` that Python builds with `ui`.
///
/// A bar tap writes the bar label to `selected` and dispatches `action`.
CatalogImplementation labChartCatalog() => CatalogImplementation(
  id: labChartCatalogId,
  protocolVersion: A2uiProtocolVersion.v1_0,
  components: [
    ComponentImplementation(
      name: 'BarChart',
      schema: barChartSchema(),
      builder: (context, node, props, buildChild) {
        final bars = chartBars(props.list('bars'));
        if (bars == null) return const Text('Invalid chart data');
        return _BarChartView(
          bars: bars,
          title: props.string('title'),
          selected: props.string('selected'),
          onTap: (label) {
            props.writable('selected')?.set(label);
            final action = props.action('action');
            if (action != null) unawaited(action());
          },
        );
      },
    ),
    ComponentImplementation(
      name: 'LineChart',
      schema: lineChartSchema(),
      builder: (context, node, props, buildChild) {
        final labels = [
          for (final l in props.list('labels'))
            if (l is String) l,
        ];
        final series = lineSeries(props.list('series'), labels.length);
        if (labels.length < 2 || series == null) {
          return const Text('Invalid chart data');
        }
        return LineChartView(
          labels: labels,
          series: series,
          title: props.string('title'),
        );
      },
    ),
  ],
);

class _BarChartView extends StatelessWidget {
  const _BarChartView({
    required this.bars,
    required this.onTap,
    this.title,
    this.selected,
  });

  final List<(String, double)> bars;
  final String? title;
  final String? selected;
  final void Function(String label) onTap;

  @override
  Widget build(BuildContext context) {
    final top = bars.map((b) => b.$2).fold<double>(0, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title case final title?)
          Text(title, style: Theme.of(context).textTheme.titleSmall),
        for (final (label, value) in bars)
          _BarRow(
            label: label,
            value: value,
            fraction: top == 0 ? 0 : value / top,
            selected: label == selected,
            onTap: () => onTap(label),
          ),
      ],
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.fraction,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double value;
  final double fraction;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Bar $label: ${chartNumber(value)}',
      button: true,
      child: InkWell(
        key: ValueKey('chart-bar:$label'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
          child: Row(
            children: [
              SizedBox(width: 140, child: Text(label)),
              Expanded(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction,
                  child: Container(
                    height: SoliplexSpacing.s4,
                    color: selected ? scheme.tertiary : scheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: SoliplexSpacing.s2),
              SizedBox(width: 90, child: Text(chartNumber(value))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lines over shared x labels, with a legend and min/max y labels.
class LineChartView extends StatelessWidget {
  const LineChartView({
    required this.labels,
    required this.series,
    super.key,
    this.title,
  });

  final List<String> labels;
  final List<LineSeries> series;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = [
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.error,
      scheme.inversePrimary,
      scheme.outline,
    ];
    final values = [
      for (final s in series)
        for (final v in s.values) ?v,
    ];
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final small = theme.textTheme.labelSmall;
    return Semantics(
      label:
          'Line chart${title == null ? '' : ' $title'}: '
          '${series.length} series over ${labels.length} points, '
          'from ${chartNumber(low)} to ${chartNumber(high)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title case final title?)
            Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: SoliplexSpacing.s2),
          SizedBox(
            height: 200,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 64,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(chartNumber(high), style: small),
                      Text(chartNumber(low), style: small),
                    ],
                  ),
                ),
                const SizedBox(width: SoliplexSpacing.s2),
                Expanded(
                  child: CustomPaint(
                    key: const ValueKey('line-chart'),
                    painter: _LinePainter(
                      series: series,
                      low: low,
                      high: high,
                      colors: colors,
                      grid: scheme.outlineVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 72),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(labels.first, style: small),
                if (labels.length > 2)
                  Text(labels[labels.length ~/ 2], style: small),
                Text(labels.last, style: small),
              ],
            ),
          ),
          const SizedBox(height: SoliplexSpacing.s2),
          Wrap(
            spacing: SoliplexSpacing.s3,
            children: [
              for (var i = 0; i < series.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: SoliplexSpacing.s3,
                      height: SoliplexSpacing.s1,
                      color: colors[i % colors.length],
                    ),
                    const SizedBox(width: SoliplexSpacing.s1),
                    Text(series[i].label, style: small),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.series,
    required this.low,
    required this.high,
    required this.colors,
    required this.grid,
  });

  final List<LineSeries> series;
  final double low;
  final double high;
  final List<Color> colors;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final span = high - low;
    for (var s = 0; s < series.length; s++) {
      final values = series[s].values;
      final n = values.length;
      final paint = Paint()
        ..color = colors[s % colors.length]
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path();
      var open = false;
      for (var i = 0; i < n; i++) {
        final v = values[i];
        if (v == null) {
          open = false;
          continue;
        }
        final x = n == 1 ? 0.0 : size.width * i / (n - 1);
        final y = span == 0
            ? size.height / 2
            : size.height * (1 - (v - low) / span);
        if (open) {
          path.lineTo(x, y);
        } else {
          path.moveTo(x, y);
          open = true;
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.series != series || old.low != low || old.high != high;
}

/// [value] without a trailing `.0`, or with two decimals.
String chartNumber(double value) => value == value.truncateToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);
