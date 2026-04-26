/// Standalone live demo of the reactive-bus architecture.
///
/// No server, no LLM, no Monty. Pure Dart and Flutter pushing real
/// state through real `StateBus` / `StateProjection` /
/// `NarrationController` types.
///
/// Run with:
///
/// ```sh
/// flutter run -d macos -t lib/demo/state_bus_demo.dart
/// ```
///
/// (or `-d chrome` for web; `-d <device>` for whatever you have).
///
/// What it demonstrates:
///
/// 1. A `StateBus` constructed in-process holds a single agent-state
///    map.
/// 2. A `NarrationProjection` reads `agentState['ui']['narrations']`.
/// 3. The projection feeds the app-singleton `narrationController`
///    via `wireProjection`.
/// 4. Tapping a button writes the bus (`bus.update(...)` for delta-
///    style writes, `bus.setAgentState(...)` for snapshot replacement).
/// 5. The `NarrationPanel` rebuilds reactively — it watches
///    `narrationController.entries`, which forwards from the
///    projection, which is derived from the bus.
///
/// This is the simulation of what an LLM-driven `narrate_say` tool
/// call does in the real app, but without any agent: you press the
/// button, the bus updates, the panel re-renders. Same path,
/// human-driven instead of agent-driven.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent_widgets/soliplex_agent_widgets.dart';
import 'package:soliplex_client/soliplex_client.dart' show StateBus;

void main() => runApp(const StateBusDemoApp());

class StateBusDemoApp extends StatelessWidget {
  const StateBusDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StateBus reactive-bus demo',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1E5AFF),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const _DemoScaffold(),
    );
  }
}

class _DemoScaffold extends StatefulWidget {
  const _DemoScaffold();

  @override
  State<_DemoScaffold> createState() => _DemoScaffoldState();
}

class _DemoScaffoldState extends State<_DemoScaffold> {
  final StateBus _bus = StateBus();
  late final ReadonlySignal<List<Narration>> _projected;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _projected = _bus.project<List<Narration>>(const NarrationProjection());
    narrationController.wireProjection(_projected);
  }

  @override
  void dispose() {
    narrationController.unwireProjection();
    _bus.dispose();
    super.dispose();
  }

  void _addNarration(String actor, String text) {
    _seq += 1;
    _bus.update((current) {
      final next = Map<String, dynamic>.from(current);
      final ui = Map<String, dynamic>.from(
        (next['ui'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
      final list = List<Map<String, dynamic>>.from(
        (ui['narrations'] as List?)?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[],
      );
      list.add({'actor': actor, 'text': '$text ($_seq)'});
      ui['narrations'] = list;
      next['ui'] = ui;
      return next;
    });
  }

  void _clear() {
    _bus.setAgentState(const {
      'ui': <String, dynamic>{
        'narrations': <Map<String, dynamic>>[],
      },
    });
  }

  void _replaceWithSnapshot() {
    // Demonstrates the snapshot path: a single setAgentState() that
    // wholesale-replaces the bus's view, simulating a server-emitted
    // StateSnapshotEvent.
    _bus.setAgentState({
      'ui': {
        'narrations': [
          {'actor': 'coordinator', 'text': 'Snapshot received from server'},
          {'actor': 'primary', 'text': 'Resuming from prior state'},
          {'actor': 'field', 'text': 'Site Alpha reached'},
        ],
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reactive bus — no server, no LLM, no Monty'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Each button writes the StateBus directly. The '
              'NarrationProjection reads the bus, forwards into '
              'NarrationController, and the panel below rebuilds.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _addNarration(
                    'coordinator',
                    'Coordinator update',
                  ),
                  icon: const Icon(Icons.campaign),
                  label: const Text('coordinator'),
                ),
                FilledButton.icon(
                  onPressed: () => _addNarration(
                    'primary',
                    'Primary report',
                  ),
                  icon: const Icon(Icons.directions_run),
                  label: const Text('primary'),
                ),
                FilledButton.icon(
                  onPressed: () => _addNarration(
                    'secondary',
                    'Secondary check-in',
                  ),
                  icon: const Icon(Icons.directions_walk),
                  label: const Text('secondary'),
                ),
                FilledButton.icon(
                  onPressed: () => _addNarration(
                    'field',
                    'Field report',
                  ),
                  icon: const Icon(Icons.flag),
                  label: const Text('field'),
                ),
                OutlinedButton.icon(
                  onPressed: _replaceWithSnapshot,
                  icon: const Icon(Icons.refresh),
                  label: const Text('replace (snapshot)'),
                ),
                OutlinedButton.icon(
                  onPressed: _clear,
                  icon: const Icon(Icons.clear),
                  label: const Text('clear'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 1,
                    child: _BusInspector(bus: _bus),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: const NarrationPanel(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live JSON view of the bus's `agentState`, so the reader can see
/// the data structure mutating as buttons are pressed.
class _BusInspector extends StatelessWidget {
  const _BusInspector({required this.bus});

  final StateBus bus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'StateBus.agentState',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Watch(
                (context) {
                  final encoder = const JsonEncoder.withIndent('  ');
                  return SelectableText(
                    encoder.convert(bus.agentState.value),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
