import 'package:flutter/material.dart';
// `State` is an AG-UI context class re-exported by soliplex_client; hide it
// here so Flutter's `State<W>` resolves cleanly.
import 'package:soliplex_client/soliplex_client.dart' hide State;

import '../../diagnostics/models/json_tree_model.dart';
import '../../diagnostics/ui/json_tree_view.dart';

/// Chronological list of every committed bus write, with a tap-to-
/// expand detail view showing the before/after state JSON.
class DeltaLogPanel extends StatefulWidget {
  const DeltaLogPanel({required this.events, super.key});

  /// Write log in chronological order — typically
  /// [BusInspector.events]. The widget renders most-recent-first.
  final List<BusWriteEvent> events;

  @override
  State<DeltaLogPanel> createState() => _DeltaLogPanelState();
}

class _DeltaLogPanelState extends State<DeltaLogPanel> {
  int? _selected;

  @override
  void didUpdateWidget(covariant DeltaLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Selected index is into the reversed list; if events shrink (e.g.
    // user cleared) drop the selection.
    if (_selected != null && _selected! >= widget.events.length) {
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.events.isEmpty) {
      return _empty(context);
    }
    final reversed = widget.events.reversed.toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        final list = ListView.builder(
          itemCount: reversed.length,
          itemBuilder: (context, i) => _DeltaTile(
            event: reversed[i],
            selected: _selected == i,
            onTap: () => setState(() => _selected = i),
          ),
        );
        if (!isWide) return list;
        final detail = _selected != null && _selected! < reversed.length
            ? _DeltaDetail(event: reversed[_selected!])
            : const _DetailEmpty();
        return Row(
          children: [
            SizedBox(width: 320, child: list),
            const VerticalDivider(width: 1),
            Expanded(child: detail),
          ],
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No bus writes captured yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeltaTile extends StatelessWidget {
  const _DeltaTile({
    required this.event,
    required this.selected,
    required this.onTap,
  });

  final BusWriteEvent event;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tag = event.tag ?? '(untagged)';
    final time = event.timestamp.toLocal().toIso8601String().substring(11, 19);
    return ListTile(
      selected: selected,
      onTap: onTap,
      dense: true,
      leading: Icon(
        event.kind == BusWriteKind.snapshot
            ? Icons.photo_camera_outlined
            : Icons.edit_outlined,
        size: 18,
      ),
      title: Text(
        tag,
        style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$time · ${event.kind.name}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _DeltaDetail extends StatelessWidget {
  const _DeltaDetail({required this.event});

  final BusWriteEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Text(
                  event.tag ?? '(untagged)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${event.kind.name} · '
                  '${event.timestamp.toLocal().toIso8601String()}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const TabBar(
            tabs: [Tab(text: 'After'), Tab(text: 'Before')],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _jsonPane(event.after),
                _jsonPane(event.before),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _jsonPane(Map<String, dynamic> map) {
    if (map.isEmpty) return const Center(child: Text('(empty)'));
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: JsonTreeView(nodes: buildJsonTree(map)),
      ),
    );
  }
}

class _DetailEmpty extends StatelessWidget {
  const _DetailEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        'Select an event to inspect.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
