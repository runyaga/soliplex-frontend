import 'package:flutter/material.dart';
// `State` is an AG-UI context class re-exported by soliplex_client; hide it
// here so Flutter's `State<W>` resolves cleanly.
import 'package:soliplex_client/soliplex_client.dart' hide State;

import '../../diagnostics/models/json_tree_model.dart';
import '../../diagnostics/ui/json_tree_view.dart';

/// Chronological list of every committed bus write, with a tap-to-
/// expand detail view showing the before/after state JSON.
class DeltaLogPanel extends StatefulWidget {
  const DeltaLogPanel({
    required this.events,
    required this.totalRecorded,
    super.key,
  });

  /// Write log in chronological order — typically
  /// [BusInspector.events]. The widget renders most-recent-first.
  final List<BusWriteEvent> events;

  /// Monotonic count of all events ever recorded by the inspector
  /// since `clear()` — typically [BusInspector.eventsTotal]. The
  /// most-recent event in [events] has absolute sequence
  /// `totalRecorded - 1`; the oldest visible has
  /// `totalRecorded - events.length`. Used to label tiles `#N`.
  final int totalRecorded;

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
    final newestSeq = widget.totalRecorded - 1;
    final oldestSeq = widget.totalRecorded - widget.events.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        final list = Column(
          children: [
            _DirectionBanner(
              count: widget.events.length,
              newestSeq: newestSeq,
              oldestSeq: oldestSeq,
            ),
            Expanded(
              child: ListView.builder(
                itemCount: reversed.length,
                itemBuilder: (context, i) => _DeltaTile(
                  seq: newestSeq - i,
                  event: reversed[i],
                  selected: _selected == i,
                  onTap: () => setState(() => _selected = i),
                ),
              ),
            ),
          ],
        );
        if (!isWide) return list;
        final detail = _selected != null && _selected! < reversed.length
            ? _DeltaDetail(
                seq: newestSeq - _selected!,
                event: reversed[_selected!],
              )
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
    required this.seq,
    required this.event,
    required this.selected,
    required this.onTap,
  });

  final int seq;
  final BusWriteEvent event;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tag = event.tag ?? '(untagged)';
    final isSnapshot = event.kind == BusWriteKind.snapshot;
    return ListTile(
      selected: selected,
      onTap: onTap,
      dense: true,
      leading: _KindBadge(isSnapshot: isSnapshot),
      title: Row(
        children: [
          // Monotonic per-inspector sequence number — required when
          // events fire faster than wall-clock resolution allows
          // (back-to-back agui events within the same millisecond).
          Text(
            '#$seq',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tag,
              style:
                  theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: event.scope == null
          ? null
          : Text(
              _shortScope(event.scope!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
    );
  }
}

/// Banner above the tile list explaining the order ("most recent
/// at TOP") plus the time-span the visible events cover. Required
/// because chronological vs reverse-chronological isn't intuitive
/// without a label.
class _DirectionBanner extends StatelessWidget {
  const _DirectionBanner({
    required this.count,
    required this.newestSeq,
    required this.oldestSeq,
  });

  final int count;
  final int newestSeq;
  final int oldestSeq;

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
            Icons.vertical_align_top,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            'NEWEST AT TOP',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            '#$newestSeq … #$oldestSeq · $count event'
            '${count == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact text badge for SNAP / DELTA. Replaces the camera/pin
/// icons that were unreadable at a glance.
class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.isSnapshot});

  final bool isSnapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = isSnapshot ? 'SNAP' : 'DELTA';
    final bg = isSnapshot
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.secondaryContainer;
    final fg = isSnapshot
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onSecondaryContainer;
    return Container(
      width: 50,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontFamily: 'monospace',
          letterSpacing: 0.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Shorten `serverId/roomId/threadId` into the last segment plus
/// a leading ellipsis, so list tiles don't get crushed by long
/// thread ids.
String _shortScope(String scope) {
  final lastSlash = scope.lastIndexOf('/');
  if (lastSlash < 0) return scope;
  final tail = scope.substring(lastSlash + 1);
  // Truncate UUID-like tails to 8 chars for readability.
  final truncatedTail = tail.length > 12 ? '${tail.substring(0, 8)}…' : tail;
  return 'thread:$truncatedTail';
}

class _DeltaDetail extends StatelessWidget {
  const _DeltaDetail({required this.seq, required this.event});

  final int seq;
  final BusWriteEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _KindBadge(
                    isSnapshot: event.kind == BusWriteKind.snapshot,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '#$seq',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      event.tag ?? '(untagged)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
              if (event.scope != null) ...[
                const SizedBox(height: 4),
                Text(
                  'scope: ${event.scope}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _SectionHeader(
                label: 'CHANGED',
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 4),
              _DiffPane(
                before: event.before,
                after: event.after,
                background: theme.colorScheme.surfaceContainerLow,
              ),
              const SizedBox(height: 16),
              _SectionHeader(
                label: 'AFTER',
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(height: 4),
              _jsonPane(event.after, theme.colorScheme.surfaceContainerLow),
              const SizedBox(height: 16),
              _SectionHeader(
                label: 'BEFORE',
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 4),
              _jsonPane(event.before, theme.colorScheme.surfaceContainerLow),
            ],
          ),
        ),
      ],
    );
  }

  Widget _jsonPane(Map<String, dynamic> map, Color background) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: map.isEmpty
          ? const Text(
              '(empty)',
              style: TextStyle(
                fontFamily: 'monospace',
                fontStyle: FontStyle.italic,
              ),
            )
          : JsonTreeView(nodes: buildJsonTree(map)),
    );
  }
}

/// Renders the JSON Patch diff between [before] and [after] as a
/// list of color-coded ops. Each op shows: a colored badge for the
/// op kind (`add` / `replace` / `remove` / `move` / `copy` / `test`),
/// the JSON Pointer path, and (for ops that carry one) the value.
///
/// Uses `package:json_patch` via the soliplex `diffJsonPatch` helper
/// so the result is RFC-6902 wire-aligned with what AG-UI server-side
/// state-delta events carry.
class _DiffPane extends StatelessWidget {
  const _DiffPane({
    required this.before,
    required this.after,
    required this.background,
  });

  final Map<String, dynamic> before;
  final Map<String, dynamic> after;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final ops = diffJsonPatch(before, after);
    if (ops.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          '(no changes — observer may have fired on an identity-only '
          'write)',
          style: TextStyle(
            fontFamily: 'monospace',
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final op in ops) _DiffOpRow(op: op),
        ],
      ),
    );
  }
}

class _DiffOpRow extends StatelessWidget {
  const _DiffOpRow({required this.op});

  final Map<String, dynamic> op;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = (op['op'] as String?) ?? '?';
    final path = (op['path'] as String?) ?? '?';
    final value = op['value'];
    final from = op['from'] as String?;

    final colors = _colorsForOp(kind, theme);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
            decoration: BoxDecoration(
              color: colors.$1,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              kind.toUpperCase(),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.$2,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              [
                path,
                if (from != null) 'from $from',
                if (value != null) '= ${_summarize(value)}',
              ].join('  '),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _colorsForOp(String kind, ThemeData theme) {
    switch (kind) {
      case 'add':
        return (
          theme.colorScheme.tertiaryContainer,
          theme.colorScheme.onTertiaryContainer,
        );
      case 'remove':
        return (
          theme.colorScheme.errorContainer,
          theme.colorScheme.onErrorContainer,
        );
      case 'replace':
        return (
          theme.colorScheme.primaryContainer,
          theme.colorScheme.onPrimaryContainer,
        );
      case 'move':
      case 'copy':
        return (
          theme.colorScheme.secondaryContainer,
          theme.colorScheme.onSecondaryContainer,
        );
      default:
        return (
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant,
        );
    }
  }

  String _summarize(Object? value) {
    if (value is String) return '"$value"';
    if (value is num || value is bool || value == null) return '$value';
    if (value is Map) {
      return '{…} (${value.length} key${value.length == 1 ? '' : 's'})';
    }
    if (value is List) {
      return '[…] (${value.length} item${value.length == 1 ? '' : 's'})';
    }
    return '$value';
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(width: 4, height: 14, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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
