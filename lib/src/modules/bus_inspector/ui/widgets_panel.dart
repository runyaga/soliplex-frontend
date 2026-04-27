import 'package:flutter/material.dart';
import 'package:soliplex_agent_widgets/soliplex_agent_widgets.dart';

/// Surfaces the client-side rendering catalogs that decide what an
/// agent's emitted text or `widgets` map will become on screen:
///
/// - **Markdown element builders** registered on the chat
///   `flutter_markdown_plus` renderer (`code`, `pre`, `latex`).
/// - **Code-fence languages** that the `pre` builder special-cases
///   (e.g. `svg` → live preview vs. default → highlighted source).
/// - **Widget catalog** entries — the dispatch table for AG-UI
///   `WidgetSpec` payloads (`InfoCard`, `StatChip`, plus any
///   builders layered via `WidgetCatalog.extending`).
///
/// Read-only debugging surface; nothing here mutates state.
class WidgetsPanel extends StatelessWidget {
  const WidgetsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = WidgetCatalog.standard();
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _SectionHeader(
          icon: Icons.format_quote_outlined,
          title: 'MARKDOWN ELEMENT BUILDERS',
          subtitle:
              'Registered on flutter_markdown_plus. The agent sends '
              'markdown; these intercept specific tags before they '
              'render.',
          count: _markdownBuilders.length,
        ),
        for (final entry in _markdownBuilders) _BuilderRow(entry: entry),
        const SizedBox(height: 16),
        _SectionHeader(
          icon: Icons.code,
          title: 'CODE-FENCE LANGUAGES',
          subtitle:
              'How fenced code blocks (```lang) are rendered. The '
              'fall-through (any other language) is syntax-highlighted '
              'via flutter_highlight.',
          count: _codeFenceLanguages.length,
        ),
        for (final entry in _codeFenceLanguages) _BuilderRow(entry: entry),
        const SizedBox(height: 16),
        _SectionHeader(
          icon: Icons.widgets_outlined,
          title: 'WIDGET CATALOG',
          subtitle:
              'AG-UI widget tree → Flutter widget dispatch table. '
              'Each entry takes a {"id", "name", "data"} spec and '
              'returns a Widget.',
          count: catalog.names.length,
        ),
        for (final name in catalog.names)
          _BuilderRow(entry: _widgetCatalogEntry(name)),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Documented entry shown in this panel. Hard-coded for v1; a
/// future refactor can derive these from declarative metadata on
/// the builder side.
class _BuilderEntry {
  const _BuilderEntry({
    required this.name,
    required this.description,
    this.format,
    this.source,
  });

  /// Display name (mono).
  final String name;

  /// Plain-English description of what this builder does.
  final String description;

  /// Optional per-builder format hint — typically a JSON shape or
  /// fenced syntax example.
  final String? format;

  /// Optional source hint — `pubspec` package or in-repo path that
  /// declares the builder. Helps developers find the implementation.
  final String? source;
}

const List<_BuilderEntry> _markdownBuilders = [
  _BuilderEntry(
    name: 'code',
    description:
        'Inline code spans. Renders inline backtick spans in the chat '
        'monospace style.',
    source:
        'lib/src/modules/room/ui/markdown/inline_code_builder.dart',
  ),
  _BuilderEntry(
    name: 'pre',
    description:
        'Fenced code blocks. Delegates to CodeBlockBuilder which '
        'dispatches on the fence language (see "Code-fence '
        'languages" below).',
    source:
        'lib/src/modules/room/ui/markdown/code_block_builder.dart',
  ),
  _BuilderEntry(
    name: 'latex',
    description:
        r'LaTeX math ($ ... $ inline and $$ ... $$ block, plus '
        'flutter_markdown_plus_latex syntaxes). Renders as math.',
    source: 'package:flutter_markdown_plus_latex',
  ),
];

const List<_BuilderEntry> _codeFenceLanguages = [
  _BuilderEntry(
    name: 'svg',
    description:
        'Live SVG preview with a toolbar to flip between rendered '
        'image and raw source, plus a copy button. Bounded to '
        '400px tall.',
    format: '```svg\\n<svg ...>...</svg>\\n```',
    source:
        'lib/src/modules/room/ui/markdown/code_block_builder.dart '
        '(_SvgCodeBlock)',
  ),
  _BuilderEntry(
    name: '(default)',
    description:
        'Any other fence language. Renders source as syntax-'
        'highlighted code (flutter_highlight, github/vs2015 '
        'theme) with a copy button.',
    format: '```<language>\\n<source>\\n```',
    source:
        'lib/src/modules/room/ui/markdown/code_block_builder.dart '
        '(_CodeBlock)',
  ),
];

_BuilderEntry _widgetCatalogEntry(String name) {
  switch (name) {
    case 'InfoCard':
      return const _BuilderEntry(
        name: 'InfoCard',
        description:
            'Material Card with a title and optional subtitle. Used '
            'for short status / overview panels.',
        format: '{"name": "InfoCard", "data": {"title": "...", '
            '"subtitle": "..."}}',
        source: 'packages/soliplex_agent_widgets/lib/src/widget_catalog.dart',
      );
    case 'StatChip':
      return const _BuilderEntry(
        name: 'StatChip',
        description:
            'Single Material Chip showing "label: value". Used for '
            'compact metric pills.',
        format: '{"name": "StatChip", "data": {"label": "...", '
            '"value": "..."}}',
        source: 'packages/soliplex_agent_widgets/lib/src/widget_catalog.dart',
      );
    default:
      return _BuilderEntry(
        name: name,
        description:
            'Custom builder added via WidgetCatalog.extending(...). '
            'No documented schema available here — see the registering '
            'flavor or plugin.',
      );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BuilderRow extends StatelessWidget {
  const _BuilderRow({required this.entry});

  final _BuilderEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            entry.name,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            entry.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (entry.format != null) ...[
            const SizedBox(height: 6),
            _LabeledBlock(label: 'FORMAT', body: entry.format!),
          ],
          if (entry.source != null) ...[
            const SizedBox(height: 6),
            _LabeledBlock(label: 'SOURCE', body: entry.source!),
          ],
        ],
      ),
    );
  }
}

class _LabeledBlock extends StatelessWidget {
  const _LabeledBlock({required this.label, required this.body});

  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
