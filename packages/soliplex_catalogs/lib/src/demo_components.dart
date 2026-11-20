import 'dart:async';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:json_schema_builder/json_schema_builder.dart'
    hide ValidationResult;
import 'package:soliplex_design/soliplex_design.dart';

/// Native sample components for deterministic offline demonstrations.
List<ComponentImplementation> demoComponents() => [
  ComponentImplementation(
    name: 'DocumentComparison',
    schema: Schema.object(
      properties: {'differencesOnly': CommonSchemasV1.dynamicBoolean},
      required: ['differencesOnly'],
    ),
    builder: (context, node, props, buildChild) {
      final differencesOnly = props.boolean('differencesOnly') ?? false;
      const rows = [
        ('Review interval', '30 days', '14 days', true),
        ('Owner', 'Operations', 'Operations', false),
        ('Approval', 'Team lead', 'Team lead + reviewer', true),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SampleLabel('SAMPLE DOCUMENTS · A compared with B'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Differences only'),
            value: differencesOnly,
            onChanged: (value) => props.writable('differencesOnly')?.set(value),
          ),
          for (final row in rows)
            if (!differencesOnly || row.$4)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(SoliplexSpacing.s3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.$1,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: SoliplexSpacing.s2),
                      Text('A: ${row.$2}'),
                      Text('B: ${row.$3}'),
                      Text(row.$4 ? 'Changed' : 'Same in both samples'),
                    ],
                  ),
                ),
              ),
          const ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Read sample excerpts'),
            children: [
              Padding(
                padding: EdgeInsets.all(SoliplexSpacing.s3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SAMPLE A: Operations reviews every 30 days. '
                      'A team lead approves changes.',
                    ),
                    SizedBox(height: SoliplexSpacing.s2),
                    Text(
                      'SAMPLE B: Operations reviews every 14 days. '
                      'A team lead and reviewer approve changes.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    },
  ),
  ComponentImplementation(
    name: 'EstimateForm',
    schema: Schema.object(
      properties: {
        'units': CommonSchemasV1.dynamicNumber,
        'rate': CommonSchemasV1.dynamicNumber,
        'total': CommonSchemasV1.dynamicNumber,
        'onCalculate': _actionSchema(),
      },
      required: ['units', 'rate', 'total', 'onCalculate'],
    ),
    builder: (context, node, props, buildChild) {
      final units = props.number('units') ?? 1;
      final rate = props.number('rate') ?? 0;
      final total = props.number('total') ?? 0;
      if (!_bounded(units, 1, 20) ||
          units != units.truncateToDouble() ||
          !_bounded(rate, 1, 100) ||
          rate != rate.truncateToDouble() ||
          !_bounded(total, 0, 2000)) {
        return const Text('Invalid sample estimate');
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SampleLabel('SAMPLE ESTIMATE · deterministic calculation'),
          const SizedBox(height: SoliplexSpacing.s3),
          Text('Units: ${units.toInt()}'),
          Slider(
            label: '${units.toInt()}',
            value: units,
            min: 1,
            max: 20,
            divisions: 19,
            onChanged: (value) => props.writable('units')?.set(value.round()),
          ),
          Text('Rate per unit: \$${rate.toStringAsFixed(0)}'),
          Slider(
            label: rate.toStringAsFixed(0),
            value: rate,
            min: 1,
            max: 100,
            divisions: 99,
            onChanged: (value) => props.writable('rate')?.set(value.round()),
          ),
          FilledButton.icon(
            onPressed: () => unawaited(props.action('onCalculate')?.call()),
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Calculate sample estimate'),
          ),
          const SizedBox(height: SoliplexSpacing.s3),
          Text(
            'Last calculated total: \$${total.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text('Sample values only. Adjust the inputs, then calculate.'),
        ],
      );
    },
  ),
  ComponentImplementation(
    name: 'FlowDiagram',
    schema: Schema.object(
      properties: {
        'selected': CommonSchemasV1.dynamicNumber,
        'onSelect': _actionSchema(),
      },
      required: ['selected', 'onSelect'],
    ),
    builder: (context, node, props, buildChild) {
      final selected = props.number('selected') ?? 0;
      if (!_bounded(selected, 0, 3) ||
          selected != selected.truncateToDouble()) {
        return const Text('Invalid sample workflow selection');
      }
      const stages = [
        ('Collect', 'Gather the sample documents and source references.'),
        ('Compare', 'An approved recipe compares the sample fields.'),
        ('Review', 'A person reviews the sample differences and excerpts.'),
        ('Publish', 'Publish the approved sample result to the conversation.'),
      ];
      final colors = Theme.of(context).colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SampleLabel('SAMPLE WORKFLOW · tap a stage'),
          const SizedBox(height: SoliplexSpacing.s3),
          for (var i = 0; i < stages.length; i++) ...[
            if (i > 0)
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: SoliplexSpacing.s4),
                  child: Icon(Icons.arrow_downward, size: 24),
                ),
              ),
            Semantics(
              button: true,
              selected: selected == i,
              child: Material(
                color: selected == i
                    ? colors.primaryContainer
                    : colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(context.radii.sm),
                child: InkWell(
                  borderRadius: BorderRadius.circular(context.radii.sm),
                  onTap: () {
                    props.writable('selected')?.set(i);
                    unawaited(props.action('onSelect')?.call());
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(SoliplexSpacing.s3),
                    child: Row(
                      children: [
                        CircleAvatar(radius: 16, child: Text('${i + 1}')),
                        const SizedBox(width: SoliplexSpacing.s3),
                        Expanded(child: Text(stages[i].$1)),
                        if (selected == i)
                          const Icon(Icons.check_circle_outline),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: SoliplexSpacing.s3),
          Text(
            'Sample stage: ${stages[selected.toInt()].$1}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(stages[selected.toInt()].$2),
        ],
      );
    },
  ),
];

Schema _actionSchema() =>
    Schema.fromMap({r'$ref': r'common_types.json#/$defs/Action'});

bool _bounded(double value, double min, double max) =>
    value.isFinite && value >= min && value <= max;

class _SampleLabel extends StatelessWidget {
  const _SampleLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.labelMedium);
}
