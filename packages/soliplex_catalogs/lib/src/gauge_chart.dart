import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'chart_semantics.dart';

/// Renders a single KPI and an optional target on a bounded scale.
class StaticGaugeChart extends StatelessWidget {
  const StaticGaugeChart({
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
    final value = spec['value']! as num;
    final min = spec['min_value']! as num;
    final max = spec['max_value']! as num;
    final target = spec['target'] as num?;
    final unit = spec['unit'] as String? ?? '';
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final low = min.toDouble();
    final span = max.toDouble() - low;
    double position(num item) => (item.toDouble() - low) / span;

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
                Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: SoliplexSpacing.s3),
              SizedBox(
                height: height,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: GaugeChart(
                        GaugeChartData(
                          rings: [
                            GaugeProgressRing(
                              value: position(value),
                              color: target != null && value < target
                                  ? colors.error
                                  : colors.primary,
                              backgroundColor: colors.surfaceContainerHighest,
                              width: 16,
                              strokeCap: StrokeCap.round,
                            ),
                          ],
                          markers: [
                            if (target != null)
                              GaugeMarker(
                                value: position(target),
                                painter: GaugeMarkerLinePainter(
                                  color: colors.onSurface,
                                  length: 18,
                                ),
                              ),
                          ],
                          touchData: GaugeTouchData(enabled: false),
                        ),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 150),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$value$unit',
                          style: theme.textTheme.headlineMedium,
                        ),
                        if (target != null) Text('Target $target$unit'),
                      ],
                    ),
                  ],
                ),
              ),
              Center(child: Text('Scale $min$unit to $max$unit')),
            ],
          ),
        ),
      ),
    );
  }
}
