import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../../../widget_tree/widget_catalog.dart';
import '../../../widget_tree/widget_spec.dart';
import '../execution_tracker.dart';
import '../room_providers.dart';
import 'citations_section.dart';
import 'execution/activity_indicator.dart';
import 'execution/execution_timeline.dart';
import 'execution/thinking_block.dart';
import 'copy_button.dart';
import 'feedback_buttons.dart';
import 'markdown/flutter_markdown_plus_renderer.dart';

/// Detects an assistant message whose entire body is a single
/// `{widget_name, data}` JSON envelope (the shape the LLM emits when
/// the genui room asks for a widget render but the `genui_render`
/// tool isn't registered server-side and the LLM falls back to text).
///
/// Returns the parsed [WidgetSpec] if recognised, or null. Tolerant
/// of leading/trailing whitespace and a single set of code-fence
/// backticks. Strict on shape — exactly two top-level keys
/// (`widget_name` string, `data` object) so plain text replies that
/// happen to mention JSON aren't false positives.
///
/// **This is a workaround for a server-side gap.** Once the genui
/// room registers `genui_render` as a Python tool that mutates
/// `agui_state['ui']['widgets']`, widgets render through the proper
/// `WidgetTreeProjection` path and this detector becomes redundant
/// (it'll still match harmless edge cases but the canonical path
/// runs first).
WidgetSpec? _tryParseWidgetEnvelope(String text) {
  var s = text.trim();
  if (s.isEmpty) return null;
  // Strip a single ```...``` fence (any language tag) if present.
  if (s.startsWith('```')) {
    final firstNewline = s.indexOf('\n');
    if (firstNewline > 0) s = s.substring(firstNewline + 1);
    if (s.endsWith('```')) s = s.substring(0, s.length - 3);
    s = s.trim();
  }
  if (!s.startsWith('{')) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(s);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final name = decoded['widget_name'];
  final data = decoded['data'];
  if (name is! String || data is! Map<String, dynamic>) return null;
  // Must be just these two keys (plus optional id) — keep the
  // detector strict to avoid false positives.
  final allowed = {'widget_name', 'data', 'id'};
  if (decoded.keys.any((k) => !allowed.contains(k))) return null;
  final id = decoded['id'] is String
      ? decoded['id']! as String
      : 'envelope-${name.hashCode}-${data.length}';
  return WidgetSpec(id: id, name: name, data: data);
}

/// Detects an assistant message whose entire body is an AG-UI
/// wire-format event echo (`{"type": "STATE_DELTA", "delta": ...}`,
/// `{"type": "STATE_SNAPSHOT", ...}`, etc.).
///
/// These show up when the server-side tool prints / returns the
/// raw SSE event payload in addition to emitting it on the wire.
/// The actual event has already been applied to `aguiState` by
/// `agui_event_processor` — the chat-side text echo is noise.
///
/// Returns true if [text] looks like one. Caller should suppress
/// rendering.
bool _looksLikeAguiEventEcho(String text) {
  var s = text.trim();
  if (s.isEmpty) return false;
  if (s.startsWith('```')) {
    final firstNewline = s.indexOf('\n');
    if (firstNewline > 0) s = s.substring(firstNewline + 1);
    if (s.endsWith('```')) s = s.substring(0, s.length - 3);
    s = s.trim();
  }
  if (!s.startsWith('{')) return false;
  Object? decoded;
  try {
    decoded = jsonDecode(s);
  } on FormatException {
    return false;
  }
  if (decoded is! Map<String, dynamic>) return false;
  final type = decoded['type'];
  if (type is! String) return false;
  return type.startsWith('STATE_') ||
      type.startsWith('ACTIVITY_') ||
      type == 'TOOL_CALL_RESULT' ||
      type == 'RUN_FINISHED' ||
      type == 'RUN_STARTED';
}

class TextMessageTile extends StatelessWidget {
  const TextMessageTile({
    super.key,
    required this.roomId,
    required this.message,
    this.runId,
    this.sourceReferences,
    this.onFeedbackSubmit,
    this.onInspect,
    this.onShowChunkVisualization,
    this.executionTracker,
    this.streamingActivity,
  });

  final String roomId;
  final TextMessage message;
  final String? runId;
  final List<SourceReference>? sourceReferences;
  final void Function(FeedbackType feedback, String? reason)? onFeedbackSubmit;
  final VoidCallback? onInspect;
  final void Function(SourceReference)? onShowChunkVisualization;
  final ExecutionTracker? executionTracker;
  final ActivityType? streamingActivity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.user == ChatUser.user;
    final showFeedback = !isUser && onFeedbackSubmit != null;
    final hasTracker = executionTracker != null;
    // Workaround: detect "LLM fell back to plain widget JSON" and
    // render via the catalog. See _tryParseWidgetEnvelope docs.
    final widgetEnvelope =
        isUser ? null : _tryParseWidgetEnvelope(message.text);
    final isAguiEventEcho = !isUser && _looksLikeAguiEventEcho(message.text);
    if (isAguiEventEcho) {
      // Suppress the entire tile — the event already drove the
      // panel via agui_event_processor.
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (streamingActivity != null)
          ActivityIndicator(activity: streamingActivity!),
        if (hasTracker)
          ExecutionTimeline(
            roomId: roomId,
            messageId: message.id,
            tracker: executionTracker!,
          ),
        if (hasTracker)
          ExecutionThinkingBlock(
            roomId: roomId,
            messageId: message.id,
            tracker: executionTracker!,
          )
        else if (!isUser && message.hasThinkingText)
          _ThinkingBlock(
            roomId: roomId,
            messageId: message.id,
            text: message.thinkingText,
          ),
        Text(
          isUser ? 'You' : 'Assistant',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: isUser
              ? SelectableText(
                  message.text,
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                )
              : widgetEnvelope != null
                  ? WidgetCatalog.standard().build(widgetEnvelope)
                  : message.text.isEmpty
                      ? const Text('...')
                      : FlutterMarkdownPlusRenderer(data: message.text),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            CopyButton(text: message.text),
            if (isUser && onInspect != null) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'Inspect HTTP traffic',
                child: InkWell(
                  onTap: onInspect,
                  borderRadius: BorderRadius.circular(4),
                  child: Icon(
                    Icons.bug_report_outlined,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (showFeedback) ...[
              const SizedBox(width: 8),
              FeedbackButtons(onFeedbackSubmit: onFeedbackSubmit!),
            ],
          ],
        ),
        if (sourceReferences != null && sourceReferences!.isNotEmpty)
          CitationsSection(
            sourceReferences: sourceReferences!,
            onShowChunkVisualization: onShowChunkVisualization,
          ),
      ],
    );
  }
}

class _ThinkingBlock extends ConsumerWidget {
  const _ThinkingBlock({
    required this.roomId,
    required this.messageId,
    required this.text,
  });

  final String roomId;
  final String messageId;
  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final expansion =
        ref.read(messageExpansionsProvider).forMessage(roomId, messageId);
    // ExpansionTile reads initiallyExpanded once on mount and does not
    // rebuild when the store changes. Safe because _ThinkingBlock and
    // ExecutionThinkingBlock are selected by hasTracker and are therefore
    // mutually exclusive for any given (roomId, messageId), so only one
    // of them writes thinkingExpanded.
    return ExpansionTile(
      initiallyExpanded: expansion.thinkingExpanded,
      onExpansionChanged: (v) => expansion.thinkingExpanded = v,
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Thinking...',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          CopyButton(
            text: text,
            tooltip: 'Copy thinking',
            iconSize: 16,
          ),
        ],
      ),
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 4),
      children: [
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
