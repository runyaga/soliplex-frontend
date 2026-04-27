import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart'
    show RegisteredToolInfo, ToolInvocationEvent;

import '../../diagnostics/models/json_tree_model.dart';
import '../../diagnostics/ui/json_tree_view.dart';

/// Tools tab — switches between **Registered** (the `ClientTool`
/// definitions visible to each active session) and **Invocations**
/// (the chronological client-side `ToolRegistry.execute` log).
///
/// The two surfaces never compete for vertical space; a segmented
/// control at the top of the panel switches between them. Each view
/// uses the full panel area.
enum _ToolsView { registered, invocations }

class ToolLogPanel extends StatefulWidget {
  const ToolLogPanel({
    required this.events,
    required this.totalRecorded,
    required this.registeredByScope,
    super.key,
  });

  final List<ToolInvocationEvent> events;
  final int totalRecorded;

  /// Registered-tool snapshots for each session, keyed by scope. Each
  /// entry carries the AG-UI [Tool] definition plus its
  /// `source` attribution (`'resolver'` or `'extension:<namespace>'`).
  /// Updated whenever a session is built.
  final Map<String, List<RegisteredToolInfo>> registeredByScope;

  @override
  State<ToolLogPanel> createState() => _ToolLogPanelState();
}

class _ToolLogPanelState extends State<ToolLogPanel> {
  _ToolsView? _view;
  int? _selected;

  _ToolsView get _effectiveView {
    if (_view != null) return _view!;
    // Default: show invocations if any have happened, otherwise the
    // registered list so a session-spawn-only state is visible.
    return widget.events.isNotEmpty
        ? _ToolsView.invocations
        : _ToolsView.registered;
  }

  @override
  void didUpdateWidget(covariant ToolLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selected != null && _selected! >= widget.events.length) {
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.events.isEmpty && widget.registeredByScope.isEmpty) {
      return _empty(context);
    }
    return Column(
      children: [
        _ViewSwitcher(
          selected: _effectiveView,
          registeredCount: _totalRegistered,
          invocationsCount: widget.events.length,
          onChanged: (v) => setState(() {
            _view = v;
            if (v == _ToolsView.registered) _selected = null;
          }),
        ),
        Expanded(
          child: switch (_effectiveView) {
            _ToolsView.registered => _RegisteredView(
                registeredByScope: widget.registeredByScope,
              ),
            _ToolsView.invocations => _InvocationsView(
                events: widget.events,
                totalRecorded: widget.totalRecorded,
                selected: _selected,
                onSelect: (i) => setState(() => _selected = i),
              ),
          },
        ),
      ],
    );
  }

  int get _totalRegistered =>
      widget.registeredByScope.values.fold(0, (sum, t) => sum + t.length);

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
            'No client-side tools registered or invoked yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Spawn a session to populate the registered list.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher({
    required this.selected,
    required this.registeredCount,
    required this.invocationsCount,
    required this.onChanged,
  });

  final _ToolsView selected;
  final int registeredCount;
  final int invocationsCount;
  final ValueChanged<_ToolsView> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: SegmentedButton<_ToolsView>(
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: [
          ButtonSegment(
            value: _ToolsView.registered,
            icon: const Icon(Icons.extension_outlined, size: 16),
            label: Text('Registered ($registeredCount)'),
          ),
          ButtonSegment(
            value: _ToolsView.invocations,
            icon: const Icon(Icons.history, size: 16),
            label: Text('Invocations ($invocationsCount)'),
          ),
        ],
        selected: {selected},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

/// Master-detail-ish list of registered tools. Each row renders the
/// tool name and full description on its own line, no hover-only
/// information. Grouped by scope with a header for each session.
class _RegisteredView extends StatelessWidget {
  const _RegisteredView({required this.registeredByScope});

  final Map<String, List<RegisteredToolInfo>> registeredByScope;

  @override
  Widget build(BuildContext context) {
    if (registeredByScope.isEmpty) {
      return _empty(context);
    }
    final entries = registeredByScope.entries.toList();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        return _ScopeSection(scope: entry.key, tools: entry.value);
      },
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No registered tools yet — spawn a session in any thread.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ScopeSection extends StatelessWidget {
  const _ScopeSection({required this.scope, required this.tools});

  final String scope;
  final List<RegisteredToolInfo> tools;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Icon(
                Icons.layers_outlined,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  scope,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Text(
                '${tools.length} tool${tools.length == 1 ? '' : 's'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        for (final info in tools) _RegisteredToolRow(info: info),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// One registered tool — name + source chip on the title row,
/// description below, parameters JSON Schema in a collapsible
/// expansion. Always-visible content; no hover required.
class _RegisteredToolRow extends StatelessWidget {
  const _RegisteredToolRow({required this.info});

  final RegisteredToolInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tool = info.definition;
    final desc = tool.description.trim();
    final params = tool.parameters;
    final hasParams = params is Map<String, dynamic> &&
        params.isNotEmpty &&
        ((params['properties'] as Map?)?.isNotEmpty ?? false);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(48, 0, 16, 12),
          leading: Icon(
            Icons.build_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          title: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              SelectableText(
                tool.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
              _SourceBadge(source: info.source),
            ],
          ),
          subtitle: desc.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: SelectableText(
                    desc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
          children: [
            _ParamsBlock(params: params, hasContent: hasParams),
          ],
        ),
      ),
    );
  }
}

/// Small colored badge naming the registering extension or
/// `'resolver'`. Click target is just the tile (badge is decorative).
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isResolver = source == 'resolver';
    final isExtension = source.startsWith('extension:');
    final bg = isResolver
        ? theme.colorScheme.tertiaryContainer
        : isExtension
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.surfaceContainerHighest;
    final fg = isResolver
        ? theme.colorScheme.onTertiaryContainer
        : isExtension
            ? theme.colorScheme.onSecondaryContainer
            : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        source,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ParamsBlock extends StatelessWidget {
  const _ParamsBlock({required this.params, required this.hasContent});

  final Object? params;
  final bool hasContent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'PARAMETERS',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(4),
          ),
          child: hasContent && params is Map<String, dynamic>
              ? JsonTreeView(
                  nodes: buildJsonTree(params! as Map<String, dynamic>),
                )
              : Text(
                  '(no parameters — tool takes no arguments)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                    fontFamily: 'monospace',
                  ),
                ),
        ),
      ],
    );
  }
}

class _InvocationsView extends StatelessWidget {
  const _InvocationsView({
    required this.events,
    required this.totalRecorded,
    required this.selected,
    required this.onSelect,
  });

  final List<ToolInvocationEvent> events;
  final int totalRecorded;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return _empty(context);
    }
    final reversed = events.reversed.toList();
    final newestSeq = totalRecorded - 1;
    final oldestSeq = totalRecorded - events.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        final list = Column(
          children: [
            _ToolDirectionBanner(
              count: events.length,
              newestSeq: newestSeq,
              oldestSeq: oldestSeq,
            ),
            Expanded(
              child: ListView.builder(
                itemCount: reversed.length,
                itemBuilder: (context, i) => _ToolTile(
                  seq: newestSeq - i,
                  event: reversed[i],
                  selected: selected == i,
                  onTap: () => onSelect(i),
                ),
              ),
            ),
          ],
        );
        if (!isWide) return list;
        final detail = selected != null && selected! < reversed.length
            ? _ToolDetail(
                seq: newestSeq - selected!,
                event: reversed[selected!],
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No invocations yet — switch to Registered to see what '
          'tools the session has.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
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
