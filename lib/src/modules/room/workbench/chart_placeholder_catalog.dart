import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:json_schema_builder/json_schema_builder.dart'
    hide ValidationResult;
import 'package:soliplex_design/soliplex_design.dart';

const graphicsCatalogId = 'urn:soliplex:catalog:graphics:2';

/// Readable chart data until a graphics renderer is supplied by the flavor.
CatalogImplementation chartPlaceholderCatalog() => CatalogImplementation(
      id: graphicsCatalogId,
      protocolVersion: A2uiProtocolVersion.v1_0,
      components: [
        ComponentImplementation(
          name: 'Chart',
          schema: Schema.object(
            properties: {'spec': CommonSchemasV1.dynamicValue},
            required: ['spec'],
          ),
          builder: (context, node, props, buildChild) {
            final spec = props.value('spec');
            final series = spec is Map ? spec['series'] : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${spec is Map ? spec['kind'] : ''} chart preview',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: SoliplexSpacing.s2),
                if (series is List)
                  for (final item in series.whereType<Map>()) ...[
                    Text('${item['label']}'),
                    if (item['points'] case final List points)
                      for (final point in points.whereType<Map>())
                        Text('${point['label']}: ${point['value']}'),
                  ],
              ],
            );
          },
        ),
      ],
    );
