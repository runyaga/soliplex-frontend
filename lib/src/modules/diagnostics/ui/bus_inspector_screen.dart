import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show ThreadKey;

import '../bus_inspector.dart';
import '../models/json_tree_model.dart';
import '../snapshot_diff.dart';
import 'json_tree_view.dart';

class BusInspectorScreen extends StatefulWidget {
  const BusInspectorScreen({required this.inspector, super.key});

  final BusInspector inspector;

  @override
  State<BusInspectorScreen> createState() => _BusInspectorScreenState();
}

class _BusInspectorScreenState extends State<BusInspectorScreen> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.inspector,
      builder: (context, _) {
        // Compute one row per recorded event with its diff against the
        // most recent prior commit on the same thread. Doing this in
        // chronological order is O(n) per build; we render newest-first
        // afterwards.
        final rows = _buildRows(widget.inspector.events);
        final reversed = rows.reversed.toList();

        return Scaffold(
          appBar: AppBar(
            title: Text('Bus Events (${reversed.length})'),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: reversed.isEmpty
                    ? null
                    : () {
                        widget.inspector.clear();
                        setState(() => _selectedIndex = null);
                      },
                tooltip: 'Clear all events',
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              if (reversed.isEmpty) return _buildEmptyState(context);
              final isWide = constraints.maxWidth >= 600;
              if (isWide) return _buildMasterDetailLayout(context, reversed);
              return _buildListLayout(context, reversed);
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bubble_chart_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No bus events yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Send a message in any room to see state writes flow through.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListLayout(BuildContext context, List<_EventRow> rows) {
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _EventTile(
        row: rows[index],
        selected: _selectedIndex == index,
        onTap: () => _showDetailSheet(context, rows[index]),
      ),
    );
  }

  Widget _buildMasterDetailLayout(BuildContext context, List<_EventRow> rows) {
    final selected = _selectedIndex != null && _selectedIndex! < rows.length
        ? rows[_selectedIndex!]
        : null;
    return Row(
      children: [
        SizedBox(
          width: 360,
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) => _EventTile(
              row: rows[index],
              selected: _selectedIndex == index,
              onTap: () => setState(() => _selectedIndex = index),
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? _buildDetailPlaceholder(context)
              : _EventDetail(row: selected),
        ),
      ],
    );
  }

  Widget _buildDetailPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        'Select an event to inspect its diff.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Future<void> _showDetailSheet(BuildContext context, _EventRow row) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: _EventDetail(row: row),
        ),
      ),
    );
  }
}

/// Row data: each event paired with its diff against the most recent
/// prior commit on the same [ThreadKey].
class _EventRow {
  _EventRow({required this.event, required this.diff});

  final BusEvent event;
  final SnapshotDiff diff;
}

List<_EventRow> _buildRows(List<BusEvent> events) {
  final lastSnapshotPerThread = <ThreadKey, Map<String, dynamic>>{};
  final rows = <_EventRow>[];
  for (final event in events) {
    final prior = lastSnapshotPerThread[event.threadKey];
    rows.add(
        _EventRow(event: event, diff: diffSnapshots(prior, event.snapshot)));
    lastSnapshotPerThread[event.threadKey] = event.snapshot;
  }
  return rows;
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.row,
    required this.selected,
    required this.onTap,
  });

  final _EventRow row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      selected: selected,
      onTap: onTap,
      dense: true,
      leading: _TagChip(tag: row.event.tag),
      title: Row(
        children: [
          Text(
            _formatTime(row.event.timestamp),
            style:
                theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              row.diff.summary,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: row.diff.isEmpty
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        _firstChangedPath(row.diff) ?? _threadShort(row.event.threadKey),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _EventDetail extends StatefulWidget {
  const _EventDetail({required this.row});

  final _EventRow row;

  @override
  State<_EventDetail> createState() => _EventDetailState();
}

class _EventDetailState extends State<_EventDetail> {
  bool _showFullSnapshot = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diff = widget.row.diff;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TagChip(tag: widget.row.event.tag),
              const SizedBox(width: 12),
              Text(
                _formatTime(widget.row.event.timestamp),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontFamily: 'monospace'),
              ),
              const Spacer(),
              Text(
                diff.summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  color: diff.isEmpty
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            'thread: ${_threadFull(widget.row.event.threadKey)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
          const Divider(height: 24),
          if (diff.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No changes vs prior commit on this thread.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            _DiffList(diff: diff),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () =>
                setState(() => _showFullSnapshot = !_showFullSnapshot),
            icon: Icon(
              _showFullSnapshot ? Icons.expand_less : Icons.expand_more,
              size: 18,
            ),
            label: Text(_showFullSnapshot
                ? 'Hide full snapshot'
                : 'Show full snapshot'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: Alignment.centerLeft,
            ),
          ),
          if (_showFullSnapshot)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child:
                  JsonTreeView(nodes: buildJsonTree(widget.row.event.snapshot)),
            ),
        ],
      ),
    );
  }
}

class _DiffList extends StatelessWidget {
  const _DiffList({required this.diff});

  final SnapshotDiff diff;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in diff.added) _ChangeLine.added(c),
        for (final c in diff.removed) _ChangeLine.removed(c),
        for (final c in diff.replaced) _ChangeLine.replaced(c),
      ],
    );
  }
}

class _ChangeLine extends StatelessWidget {
  const _ChangeLine._({
    required this.path,
    required this.symbol,
    required this.color,
    required this.value,
  });

  factory _ChangeLine.added(AddedChange c) => _ChangeLine._(
        path: c.path,
        symbol: '+',
        color: Colors.green.shade700,
        value: _formatValue(c.value),
      );

  factory _ChangeLine.removed(RemovedChange c) => _ChangeLine._(
        path: c.path,
        symbol: '-',
        color: Colors.red.shade700,
        value: _formatValue(c.value),
      );

  factory _ChangeLine.replaced(ReplacedChange c) => _ChangeLine._(
        path: c.path,
        symbol: '~',
        color: Colors.amber.shade800,
        value: '${_formatValue(c.before)} → ${_formatValue(c.after)}',
      );

  final String path;
  final String symbol;
  final Color color;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText.rich(
        TextSpan(
          style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          children: [
            TextSpan(
              text: '$symbol ',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: path,
              style: TextStyle(color: theme.colorScheme.onSurface),
            ),
            const TextSpan(text: '  '),
            TextSpan(
              text: value,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag});

  final String? tag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayTag = tag ?? 'untagged';
    final bg = tag == null
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.secondaryContainer;
    final fg = tag == null
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        displayTag,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

String _formatTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  final s = t.second.toString().padLeft(2, '0');
  final ms = t.millisecond.toString().padLeft(3, '0');
  return '$h:$m:$s.$ms';
}

String _threadShort(ThreadKey key) {
  final tid = key.threadId;
  return tid.length <= 6 ? tid : tid.substring(tid.length - 6);
}

String _threadFull(ThreadKey key) =>
    '${key.serverId}/${key.roomId}/${key.threadId}';

String? _firstChangedPath(SnapshotDiff diff) {
  if (diff.added.isNotEmpty) return diff.added.first.path;
  if (diff.replaced.isNotEmpty) return diff.replaced.first.path;
  if (diff.removed.isNotEmpty) return diff.removed.first.path;
  return null;
}

String _formatValue(dynamic value) {
  if (value == null) return 'null';
  if (value is String) {
    // Truncate long strings for tile display.
    if (value.length > 60) return '"${value.substring(0, 57)}..."';
    return '"$value"';
  }
  if (value is num || value is bool) return value.toString();
  if (value is Map)
    return '{…} (${value.length} key${value.length == 1 ? '' : 's'})';
  if (value is List) return '[…] (${value.length})';
  return value.toString();
}
