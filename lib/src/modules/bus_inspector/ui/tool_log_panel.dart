import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show ToolInvocationEvent;

/// Chronological log of LLM tool invocations, with a tap-to-expand
/// detail showing args, return value, error, and duration.
///
/// Renders most-recent-first to match the network inspector's
/// convention.
class ToolLogPanel extends StatefulWidget {
  const ToolLogPanel({required this.events, super.key});

  final List<ToolInvocationEvent> events;

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        final list = ListView.builder(
          itemCount: reversed.length,
          itemBuilder: (context, i) => _ToolTile(
            event: reversed[i],
            selected: _selected == i,
            onTap: () => setState(() => _selected = i),
          ),
        );
        if (!isWide) return list;
        final detail = _selected != null && _selected! < reversed.length
            ? _ToolDetail(event: reversed[_selected!])
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
    required this.event,
    required this.selected,
    required this.onTap,
  });

  final ToolInvocationEvent event;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = event.startedAt.toLocal().toIso8601String().substring(11, 19);
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
      title: Text(
        event.toolName,
        style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$time · ${event.duration.inMilliseconds}ms',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ToolDetail extends StatelessWidget {
  const _ToolDetail({required this.event});

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
              Text(
                event.toolName,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'id ${event.toolCallId} · '
                '${event.duration.inMilliseconds}ms · '
                '${event.startedAt.toLocal().toIso8601String()}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
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
