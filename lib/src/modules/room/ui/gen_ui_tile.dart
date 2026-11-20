import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';

import '../a2ui/surface_controller.dart';
import '../a2ui/surface_scope.dart';
import '../a2ui/surface_view.dart';

class GenUiTile extends StatelessWidget {
  const GenUiTile({super.key, required this.message});
  final GenUiMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.widgetName == 'a2ui') {
      final scope = ChatSurfaceScope.scopeOf(context);
      final registration = message.data['workbenchRegistration'];
      if (scope?.hostsWorkbench == true &&
          (scope!.hostedActivityIds.contains(message.id) ||
              (registration is Map &&
                  const ['content', 'program', 'layout']
                      .contains(registration['role'])))) {
        return Card(
            child: Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s2),
          child: Text(registration is Map && registration['role'] == 'layout'
              ? 'Workspace layout updated'
              : 'Surface in workspace'),
        ));
      }
      return _A2uiTile(key: ValueKey(message.id), message: message);
    }
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SoliplexSpacing.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.widgetName,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SoliplexSpacing.s2),
            Text(
              const JsonEncoder.withIndent('  ').convert(message.data),
              style: context.monospaceOn(theme.textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}

class _A2uiTile extends StatefulWidget {
  const _A2uiTile({super.key, required this.message});
  final GenUiMessage message;

  @override
  State<_A2uiTile> createState() => _A2uiTileState();
}

class _A2uiTileState extends State<_A2uiTile> {
  late ChatSurfaceController controller;
  ChatSurfaceStore? _store;
  bool _loaded = false;
  bool _ownsController = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = ChatSurfaceScope.maybeOf(context);
    if (!_loaded || !identical(store, _store)) {
      if (_loaded && _ownsController) controller.dispose();
      _store = store;
      _load();
    }
  }

  void _load() {
    _loaded = true;
    _ownsController = _store == null;
    if (_ownsController) controller = ChatSurfaceController();
    try {
      final messages = (widget.message.data['messages'] as List)
          .map((m) => Map<String, Object?>.from(m as Map))
          .toList();
      if (_store case final store?) {
        final runId = widget.message.runId;
        controller = store.obtain(
          widget.message.id,
          messages,
          live:
              runId != null && runId == ChatSurfaceScope.activeRunIdOf(context),
        );
      } else {
        controller.apply(messages);
      }
    } catch (error) {
      if (!_ownsController) {
        controller = ChatSurfaceController();
        _ownsController = true;
      }
      controller.error = 'Cannot render surface: $error';
    }
  }

  @override
  void didUpdateWidget(_A2uiTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.message.data, oldWidget.message.data)) {
      if (_ownsController) controller.dispose();
      _load();
    }
  }

  @override
  void dispose() {
    if (_ownsController) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.message.data['messages'];
    final status = widget.message.data['status'];
    if (messages is List && messages.isEmpty && status is String) {
      return Text(switch (status) {
        'building' => 'Building interactive response…',
        'retrying' => 'Retrying interactive response…',
        'failed' => 'Interactive response failed.',
        _ => 'Interactive response: $status',
      });
    }
    return ChatSurfaceView(controller: controller);
  }
}
