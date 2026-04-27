import 'package:flutter/material.dart';

import '../bus_inspector.dart';
import 'bus_state_panel.dart';
import 'delta_log_panel.dart';

/// Tabbed scaffold mirroring `NetworkInspectorScreen`'s ergonomics.
///
/// Two tabs in v1:
///
/// - **State** — the bus's current agent-state snapshot rendered as
///   an expandable JSON tree (most recent write's `after` map).
/// - **Delta log** — chronological list of every committed write with
///   tap-to-expand before/after detail.
///
/// Step 6 will add a **Registry** tab listing the per-session
/// extension graph (tools + host functions) once the registry hook
/// lands.
class BusInspectorScreen extends StatelessWidget {
  const BusInspectorScreen({required this.inspector, super.key});

  final BusInspector inspector;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: inspector,
      builder: (context, _) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text('Bus (${inspector.events.length})'),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: inspector.events.isEmpty ? null : inspector.clear,
                tooltip: 'Clear bus event log',
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.data_object), text: 'State'),
                Tab(icon: Icon(Icons.history), text: 'Delta log'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              BusStatePanel(state: inspector.latestState),
              DeltaLogPanel(events: inspector.events),
            ],
          ),
        ),
      ),
    );
  }
}
