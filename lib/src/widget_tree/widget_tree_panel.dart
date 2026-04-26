import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import 'widget_catalog.dart';
import 'widget_spec.dart';

/// Renders a list of [WidgetSpec]s coming from a state-projection
/// signal.
///
/// The widget watches [specs] and lays each spec out vertically
/// using [catalog]. Empty list = empty panel (no chrome).
///
/// Scope for v1: a simple Column. The agent decides ordering;
/// future versions may carry layout hints in the spec data.
class WidgetTreePanel extends StatelessWidget {
  const WidgetTreePanel({
    super.key,
    required this.specs,
    required this.catalog,
    this.padding = const EdgeInsets.all(8),
    this.spacing = 8,
  });

  /// Read-only signal of the projected widget tree.
  final ReadonlySignal<List<WidgetSpec>> specs;

  /// Catalog used to dispatch each spec's `name` to a Flutter widget.
  final WidgetCatalog catalog;

  /// Outer padding around the column.
  final EdgeInsets padding;

  /// Vertical gap between widgets.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final list = specs.value;
      if (list.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0) SizedBox(height: spacing),
              catalog.build(list[i]),
            ],
          ],
        ),
      );
    });
  }
}
