import 'package:flutter/material.dart';

import 'widget_spec.dart';

/// Maps an agent-emitted widget [name] (e.g. `'InfoCard'`) to a
/// concrete Flutter widget.
///
/// Apps register builders via [WidgetCatalog.standard] (the default
/// set bundled with this package) or by composing with [extending]
/// to add custom widgets without re-implementing built-ins.
///
/// Builders receive the raw [WidgetSpec.data] map; they're
/// responsible for tolerant parsing — bad shapes should render a
/// placeholder, never throw.
typedef WidgetCatalogBuilder = Widget Function(WidgetSpec spec);

class WidgetCatalog {
  /// Construct from an explicit map. Most callers use [standard] or
  /// [extending] instead.
  const WidgetCatalog(this._builders);

  /// The default catalog shipped in-tree. Currently:
  /// - `InfoCard` — title + optional subtitle.
  /// - `StatChip` — single label/value chip (e.g. tonnage).
  ///
  /// Add new built-ins here as the demos grow; consumers can layer
  /// additional widgets via [extending].
  factory WidgetCatalog.standard() => WidgetCatalog(_standardBuilders);

  final Map<String, WidgetCatalogBuilder> _builders;

  /// True if [name] resolves to a registered builder.
  bool has(String name) => _builders.containsKey(name);

  /// Build the widget for [spec] or a placeholder if [name] is not
  /// in the catalog.
  Widget build(WidgetSpec spec) {
    final builder = _builders[spec.name];
    if (builder == null) return _UnknownWidget(name: spec.name);
    return KeyedSubtree(key: ValueKey('w:${spec.id}'), child: builder(spec));
  }

  /// Returns a new catalog that has [extras] layered on top of this
  /// one. Later wins on key collision so apps can override built-ins.
  WidgetCatalog extending(Map<String, WidgetCatalogBuilder> extras) {
    return WidgetCatalog({..._builders, ...extras});
  }
}

// ---- Built-in widgets ------------------------------------------------------

Map<String, WidgetCatalogBuilder> get _standardBuilders => {
      'InfoCard': (spec) => _InfoCard(
            title: _stringAt(spec.data, 'title') ?? 'Untitled',
            subtitle: _stringAt(spec.data, 'subtitle'),
          ),
      'StatChip': (spec) => _StatChip(
            label: _stringAt(spec.data, 'label') ?? '',
            value: _stringAt(spec.data, 'value') ?? '',
          ),
    };

String? _stringAt(Map<String, dynamic> data, String key) {
  final v = data[key];
  return v is String ? v : null;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
    );
  }
}

class _UnknownWidget extends StatelessWidget {
  const _UnknownWidget({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Loud banner instead of a quiet red label — silent failures
    // were a sharp edge per the architecture review. The user
    // should immediately see "the agent asked for a widget the
    // catalog doesn't know about."
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text.rich(
              TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
                children: [
                  const TextSpan(
                    text: 'Unknown widget ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: name,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  const TextSpan(
                    text: ' — not registered in WidgetCatalog',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
