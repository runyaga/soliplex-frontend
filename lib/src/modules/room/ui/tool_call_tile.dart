import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../../../widget_tree/widget_catalog.dart';
import '../../../widget_tree/widget_spec.dart';

/// Tool names whose arguments should be rendered as widgets via the
/// catalog instead of the generic tool-call envelope.
///
/// Workaround for the genui room's server-side gap — see
/// `~/dev/plans/genui-frontend-handoff.md` (update 2). When the
/// server's `genui_render` tool actually emits a StateDeltaEvent
/// patching `agui_state['ui']['widgets']`, the
/// `WidgetTreeProjection` panel takes over and these tiles still
/// render harmlessly.
const _genUiRenderToolNames = <String>{
  'genui_render',
  'canvas_render',
};

class ToolCallTile extends StatelessWidget {
  const ToolCallTile({super.key, required this.message});
  final ToolCallMessage message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final toolCall in message.toolCalls)
          _ToolCallCard(toolCall: toolCall),
      ],
    );
  }
}

/// Tries to extract a [WidgetSpec] from a tool call's arguments
/// when the tool name matches a known GenUI render call.
///
/// Returns null when the tool isn't a render call OR the args are
/// malformed. The renderer falls back to the generic tool-call
/// envelope in that case.
WidgetSpec? _tryWidgetFromToolCall(ToolCallInfo toolCall) {
  if (!_genUiRenderToolNames.contains(toolCall.name)) return null;
  if (!toolCall.hasArguments) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(toolCall.arguments);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final name = decoded['widget_name'];
  final data = decoded['data'];
  if (name is! String || data is! Map<String, dynamic>) return null;
  return WidgetSpec(
    id: 'tc-${toolCall.id}',
    name: name,
    data: data,
  );
}

class _ToolCallCard extends StatelessWidget {
  const _ToolCallCard({required this.toolCall});
  final ToolCallInfo toolCall;

  @override
  Widget build(BuildContext context) {
    final spec = _tryWidgetFromToolCall(toolCall);
    if (spec != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: WidgetCatalog.standard().build(spec),
      );
    }
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ExpansionTile(
        leading: Icon(Icons.bolt, color: theme.colorScheme.primary, size: 18),
        title: Row(
          children: [
            Flexible(
              child: Text(
                toolCall.name,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              toolCall.status.name,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        dense: true,
        children: [
          if (toolCall.hasArguments)
            _CodeBlock(label: 'Arguments', text: toolCall.arguments),
          if (toolCall.hasResult)
            _CodeBlock(label: 'Result', text: toolCall.result),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.label, required this.text});
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            text,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
