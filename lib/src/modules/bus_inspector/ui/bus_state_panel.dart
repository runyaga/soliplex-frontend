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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BusStateHeader(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: JsonTreeView(nodes: buildJsonTree(s)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BusStateHeader(),
        Expanded(child: _emptyBody(context, theme)),
      ],
    );
  }

  Widget _emptyBody(BuildContext context, ThemeData theme) {
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

/// Header strip clarifying that this tab shows the **bus** state — a
/// superset of AG-UI state. Underscore-prefixed keys (e.g. `_meta`)
/// are written by client-side extensions (execution tracker, future
/// projections) and never round-trip back to the backend.
class _BusStateHeader extends StatelessWidget {
  const _BusStateHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'BUS STATE — keys prefixed with _ are client-side only',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
