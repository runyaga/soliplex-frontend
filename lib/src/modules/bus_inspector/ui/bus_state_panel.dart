import 'package:flutter/material.dart';

import '../../diagnostics/models/json_tree_model.dart';
import '../../diagnostics/ui/json_tree_view.dart';

/// Renders the bus's current agent-state snapshot as an expandable
/// JSON tree. Reuses the existing `JsonTreeView` from the diagnostics
/// module so the look matches the network inspector's request-detail
/// pane.
class BusStatePanel extends StatelessWidget {
  const BusStatePanel({required this.state, super.key});

  /// The agent-state map to render. `null` means no events have been
  /// captured yet (empty state).
  final Map<String, dynamic>? state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s == null || s.isEmpty) {
      return _empty(context);
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: JsonTreeView(nodes: buildJsonTree(s)),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.data_object,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No bus state observed yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Run an agent that writes the bus to populate this view.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
