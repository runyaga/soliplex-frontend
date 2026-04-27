import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show ToolInvocationEvent;

/// Chronological log of LLM tool invocations, with a tap-to-expand
/// detail showing args, return value, error, and duration.
///
/// Renders most-recent-first to match the network inspector's
/// convention.
class ToolLogPanel extends StatefulWidget {
  const ToolLogPanel({
    required this.events,
    required this.totalRecorded,
    super.key,
  });

  final List<ToolInvocationEvent> events;
  final int totalRecorded;

  @override
  State<ToolLogPanel> createState() => _ToolLogPanelState();
}

class _ToolLogPanelState extends State<ToolLogPanel> {
  int? _selected;

  @override
  void didUpdateWidget(covariant ToolLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
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
            _ToolDirectionBanner(
              count: widget.events.length,
              newestSeq: newestSeq,
              oldestSeq: oldestSeq,
            ),
            Expanded(
              child: ListView.builder(
                itemCount: reversed.length,
                itemBuilder: (context, i) => _ToolTile(
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
            ? _ToolDetail(
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
            Icons.code,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No LLM tool invocations captured yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.seq,
    required this.event,
    required this.selected,
    required this.onTap,
  });

  final int seq;
  final ToolInvocationEvent event;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = event.error != null;
    return ListTile(
      selected: selected,
      onTap: onTap,
      dense: true,
      leading: Icon(
        isError ? Icons.error_outline : Icons.check_circle_outline,
        size: 18,
        color: isError ? theme.colorScheme.error : null,
      ),
      title: Row(
        children: [
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
              event.toolName,
              style:
                  theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Text(
        '${event.duration.inMilliseconds}ms',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

/// Same shape as the delta-log direction banner; lives here to
/// avoid cross-panel coupling for now.
class _ToolDirectionBanner extends StatelessWidget {
  const _ToolDirectionBanner({
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
            '#$newestSeq … #$oldestSeq · $count call'
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

class _ToolDetail extends StatelessWidget {
  const _ToolDetail({required this.seq, required this.event});

  final int seq;
  final ToolInvocationEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = event.error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
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
                      event.toolName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'id ${event.toolCallId} · '
                '${event.duration.inMilliseconds}ms',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _section(
                context,
                'Arguments',
                event.arguments.isEmpty ? '(none)' : event.arguments,
              ),
              const SizedBox(height: 16),
              if (isError)
                _section(
                  context,
                  'Error',
                  '${event.error}',
                  color: theme.colorScheme.error,
                )
              else
                _section(
                  context,
                  'Result',
                  event.result?.isEmpty ?? true ? '(empty)' : event.result!,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(
    BuildContext context,
    String label,
    String content, {
    Color? color,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color ?? theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          content,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: color,
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
        'Select an invocation to inspect.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
