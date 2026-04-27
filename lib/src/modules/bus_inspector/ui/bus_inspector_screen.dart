import 'package:flutter/material.dart';

import '../bus_inspector.dart';
import 'bus_state_panel.dart';
import 'delta_log_panel.dart';
import 'tool_log_panel.dart';

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
            length: 3,
            child: Scaffold(
              appBar: AppBar(
                title: Text(
                  'Bus (writes ${inspector.events.length} · '
                  'tools ${inspector.toolInvocations.length})',
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: hasEvents ? inspector.clear : null,
                    tooltip: 'Clear bus + tool logs',
                  ),
                ],
                bottom: const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.data_object), text: 'State'),
                    Tab(icon: Icon(Icons.history), text: 'Delta log'),
                    Tab(icon: Icon(Icons.code), text: 'Tools'),
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
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
