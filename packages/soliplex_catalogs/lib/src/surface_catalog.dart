import 'dart:async';
import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:json_schema_builder/json_schema_builder.dart'
    hide ValidationResult;
import 'package:soliplex_catalogs/src/demo_components.dart';
import 'package:soliplex_design/soliplex_design.dart';

const chatGraphicsCatalogId = 'urn:soliplex:catalog:graphics:1';

/// Registers graphics shared by the room timeline and embedded chat.
CatalogImplementation chatGraphicsCatalog() => CatalogImplementation(
  id: chatGraphicsCatalogId,
  protocolVersion: A2uiProtocolVersion.v1_0,
  components: [
    ...demoComponents(),
    ComponentImplementation(
      name: 'BarChart',
      schema: Schema.object(
        properties: {
          'values': CommonSchemasV1.dynamicString,
          'selected': CommonSchemasV1.dynamicNumber,
          'axisMax': CommonSchemasV1.dynamicNumber,
          'onSelect': Schema.fromMap({
            r'$ref': r'common_types.json#/$defs/Action',
          }),
        },
        required: ['values', 'selected'],
      ),
      builder: (context, node, props, buildChild) {
        final encoded = props.string('values') ?? '[]';
        if (encoded.length > 16384) return const Text('Invalid chart data');
        final Object? raw;
        try {
          raw = jsonDecode(encoded);
        } on FormatException {
          return const Text('Invalid chart data');
        }
        if (raw is! List ||
            raw.isEmpty ||
            raw.length > 32 ||
            raw.any((v) => v is! num || !v.isFinite || v < 0 || v > 1000)) {
          return const Text('Invalid chart data');
        }
        final values = raw.cast<num>();
        final selection = props.number('selected') ?? -1;
        if (!selection.isFinite ||
            selection < -1 ||
            selection >= values.length ||
            selection != selection.truncateToDouble()) {
          return const Text('Invalid chart data');
        }
        final selected = selection.toInt();
        final max = props.number('axisMax') ?? 1000;
        if (!max.isFinite || max <= 0 || values.any((v) => v > max)) {
          return const Text('Invalid chart scale');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Scale: 0–$max'),
            SizedBox(
              height: 160,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < values.length; i++)
                    Expanded(
                      child: Semantics(
                        label: 'Select series ${i + 1}',
                        button: true,
                        child: InkWell(
                          onTap: () {
                            props.writable('selected')?.set(i);
                            unawaited(props.action('onSelect')?.call());
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: SoliplexSpacing.s2,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text('${values[i]}'),
                                Container(
                                  key: ValueKey('chart-bar-$i'),
                                  height: 100 * (values[i] / max).clamp(0, 1),
                                  color: i == selected
                                      ? Theme.of(context).colorScheme.tertiary
                                      : Theme.of(context).colorScheme.primary,
                                ),
                                Text('Series ${i + 1}'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: SoliplexSpacing.s3),
            Text(
              selected < 0 ? 'Select a bar' : 'Selected series ${selected + 1}',
            ),
            for (var i = 0; i < values.length; i++)
              if (selected < 0 || selected == i)
                Text('Series ${i + 1}: ${values[i]}'),
          ],
        );
      },
    ),
  ],
);
