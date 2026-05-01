import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show ThreadKey;

import '../bus_inspector.dart';
import '../models/json_tree_model.dart';
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
        final events = widget.inspector.events.reversed.toList();

        return Scaffold(
          appBar: AppBar(
            title: Text('Bus Events (${events.length})'),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: events.isEmpty
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
              if (events.isEmpty) return _buildEmptyState(context);
              final isWide = constraints.maxWidth >= 600;
              if (isWide) return _buildMasterDetailLayout(context, events);
              return _buildListLayout(context, events);
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

  Widget _buildListLayout(BuildContext context, List<BusEvent> events) {
    return ListView.separated(
      itemCount: events.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _BusEventTile(
        event: events[index],
        selected: _selectedIndex == index,
        onTap: () => _showDetailSheet(context, events[index]),
      ),
    );
  }

  Widget _buildMasterDetailLayout(
    BuildContext context,
    List<BusEvent> events,
  ) {
    final selected = _selectedIndex != null && _selectedIndex! < events.length
        ? events[_selectedIndex!]
        : null;
    return Row(
      children: [
        SizedBox(
          width: 360,
          child: ListView.separated(
            itemCount: events.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) => _BusEventTile(
              event: events[index],
              selected: _selectedIndex == index,
              onTap: () => setState(() => _selectedIndex = index),
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? _buildDetailPlaceholder(context)
              : _BusEventDetail(event: selected),
        ),
      ],
    );
  }

  Widget _buildDetailPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        'Select an event to inspect its snapshot.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Future<void> _showDetailSheet(BuildContext context, BusEvent event) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            controller: scrollController,
            child: _BusEventDetail(event: event),
          ),
        ),
      ),
    );
  }
}

class _BusEventTile extends StatelessWidget {
  const _BusEventTile({
    required this.event,
    required this.selected,
    required this.onTap,
  });

  final BusEvent event;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      selected: selected,
      onTap: onTap,
      dense: true,
      leading: _TagChip(tag: event.tag),
      title: Text(
        _formatTime(event.timestamp),
        style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
      ),
      subtitle: Text(
        '${_threadShort(event.threadKey)} · '
        '${event.snapshot.length} key${event.snapshot.length == 1 ? '' : 's'}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _BusEventDetail extends StatelessWidget {
  const _BusEventDetail({required this.event});

  final BusEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodes = buildJsonTree(event.snapshot);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TagChip(tag: event.tag),
              const SizedBox(width: 12),
              Text(
                _formatTime(event.timestamp),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontFamily: 'monospace'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            'thread: ${_threadFull(event.threadKey)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: SingleChildScrollView(child: JsonTreeView(nodes: nodes)),
          ),
        ],
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
