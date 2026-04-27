import 'package:flutter/material.dart';

import '../bus_inspector.dart';
import 'bus_state_panel.dart';
import 'delta_log_panel.dart';
import 'tool_log_panel.dart';
import 'widgets_panel.dart';

/// Tabbed scaffold mirroring `NetworkInspectorScreen`'s ergonomics.
///
/// Three tabs:
///
/// - **State** — the bus's current agent-state snapshot rendered as
///   an expandable JSON tree (most recent write's `after` map).
/// - **Delta log** — chronological list of every committed bus write
///   with tap-to-expand before/after detail. List renders most-recent
///   at the TOP; the panel header reminds you of that.
/// - **Tools** — chronological list of every LLM tool invocation
///   with tap-to-expand args / result / error / duration detail.
///
/// The **clear** action wipes both event logs.
///
/// The whole inspector is wrapped in a `SelectionArea` so every
/// `Text` / `RichText` / `JsonTreeView` node is copyable — required
/// dev affordance.
class BusInspectorScreen extends StatelessWidget {
  const BusInspectorScreen({required this.inspector, super.key});

  final BusInspector inspector;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: inspector,
      builder: (context, _) {
        final hasEvents =
            inspector.events.isNotEmpty || inspector.toolInvocations.isNotEmpty;
        return SelectionArea(
          child: DefaultTabController(
            length: 4,
            child: Scaffold(
              appBar: AppBar(
                title: Text(
                  'Bus (writes ${inspector.events.length} · '
                  'tools ${inspector.toolInvocations.length})',
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    tooltip: 'What does each tab show?',
                    onPressed: () => _showHelp(context),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: hasEvents ? inspector.clear : null,
                    tooltip: 'Clear bus + tool logs',
                  ),
                ],
                bottom: const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(icon: Icon(Icons.data_object), text: 'State'),
                    Tab(icon: Icon(Icons.history), text: 'Delta log'),
                    Tab(icon: Icon(Icons.code), text: 'Tools'),
                    Tab(icon: Icon(Icons.widgets_outlined), text: 'Widgets'),
                  ],
                ),
              ),
              body: TabBarView(
                children: [
                  BusStatePanel(state: inspector.latestState),
                  DeltaLogPanel(
                    events: inspector.events,
                    totalRecorded: inspector.eventsTotal,
                  ),
                  ToolLogPanel(
                    events: inspector.toolInvocations,
                    totalRecorded: inspector.toolInvocationsTotal,
                    registeredByScope: inspector.registeredToolsByScope,
                  ),
                  const WidgetsPanel(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => const _BusInspectorHelpDialog(),
    );
  }
}

class _BusInspectorHelpDialog extends StatelessWidget {
  const _BusInspectorHelpDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Bus Inspector — what each tab shows'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _HelpSection(
                icon: Icons.data_object,
                title: 'State',
                body:
                    'The bus\'s current agent-state snapshot for the active '
                    'thread (after the most recent write). This is the BUS '
                    'state — a superset of AG-UI state. Keys prefixed with '
                    '_ (e.g. _meta.steps) are added by client-side '
                    'extensions like the execution tracker; they never '
                    'round-trip back to the backend.',
              ),
              const SizedBox(height: 12),
              _HelpSection(
                icon: Icons.history,
                title: 'Delta log',
                body:
                    'Every committed bus write in chronological order '
                    '(newest at top). Includes:\n\n'
                    '• Server-side state — AG-UI STATE_SNAPSHOT and '
                    'STATE_DELTA events under tag ag-ui:run-state.\n'
                    '• Server-side tool calls — TOOL_CALL_START / _ARGS / '
                    '_END events appear here as bus writes touching '
                    '/toolCalls/* paths.\n'
                    '• Client-side bus writes — plugins like '
                    'NarrationPlugin and MapPlugin write directly to the '
                    'bus with their own tags (narrate.append, map.set_site, '
                    '...).\n'
                    '• Execution tracker — _meta.steps mirroring under '
                    'tag execution-tracker:steps.\n\n'
                    'Tap a row for the JSON Patch diff and full '
                    'before/after.',
              ),
              const SizedBox(height: 12),
              _HelpSection(
                icon: Icons.code,
                title: 'Tools',
                body:
                    'Two views via the segmented control:\n\n'
                    '• Registered — every ClientTool the active '
                    'session received, grouped by scope. Each entry '
                    'shows name, source attribution '
                    '(resolver vs. extension:<namespace>), description, '
                    'and the parameters JSON Schema.\n'
                    '• Invocations — every ClientTool execution '
                    'captured via ToolObserver. Server-side tools '
                    '(the LLM invokes them on the backend) do NOT '
                    'appear here; find them in the Delta log under '
                    '/toolCalls/*.',
              ),
              const SizedBox(height: 12),
              _HelpSection(
                icon: Icons.widgets_outlined,
                title: 'Widgets',
                body:
                    'Static catalog of what client-side rendering '
                    'builders exist:\n\n'
                    '• Markdown element builders registered on the '
                    'chat renderer (code, pre, latex).\n'
                    '• Code-fence languages the pre builder special-'
                    'cases (svg → live preview, default → highlighted '
                    'source).\n'
                    '• WidgetCatalog entries — the AG-UI WidgetSpec '
                    'dispatch table (InfoCard, StatChip, plus any '
                    'flavor-added builders).',
              ),
              const SizedBox(height: 16),
              Text(
                'Diff badges',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'ADD / MOD / REMOVE / MOVE / COPY are RFC 6902 JSON Patch '
                'ops between BEFORE and AFTER. (MOD = replace.)',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            icon,
            size: 18,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(body, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
