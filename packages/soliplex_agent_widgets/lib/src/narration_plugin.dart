import 'dart:convert';

import 'package:soliplex_agent/soliplex_agent.dart';

import 'narration.dart';

/// A [SessionExtension] that declares the `narrate_say` LLM tool.
///
/// The executor writes a narration entry into the per-thread bus at
/// `agentState['ui']['narrations']`. The existing
/// `NarrationProjection` (in `narration_controller.dart`) reads from
/// the same path, so the entry flows from bus delta → projection →
/// `NarrationController._entries` → `NarrationPanel` automatically.
///
/// Phase 1 step 4b — first plugin converted to the bus-write pattern.
/// `NarrationMontyExtension` (the Python bridge) is carried forward
/// unchanged and still calls `narrationController.add(...)`
/// imperatively; Phase 2 retires it.
///
/// Plan reference: `docs/plans/reactive-bus-redesign.md` (Phase 1 step 4).
class NarrationPlugin extends SessionExtension {
  NarrationPlugin();

  SessionContext? _ctx;

  @override
  String get namespace => 'narration';

  @override
  Future<void> onAttach(AgentSession session) async {}

  @override
  Future<void> onAttachWithContext(SessionContext ctx) async {
    _ctx = ctx;
    await onAttach(ctx.session);
  }

  @override
  void onDispose() {
    _ctx = null;
  }

  @override
  List<ClientTool> get tools => [
        ClientTool.simple(
          name: 'narrate_say',
          description: 'Append a narration line to the on-screen log. '
              'Choose an actor: coordinator (default), primary, secondary, '
              'or field.',
          parameters: const {
            'type': 'object',
            'properties': {
              'text': {
                'type': 'string',
                'description': 'The narration text to display.',
              },
              'actor': {
                'type': 'string',
                'description':
                    'Speaker label: coordinator | primary | secondary | field',
              },
            },
            'required': ['text'],
          },
          executor: _executeNarrateSay,
        ),
      ];

  Future<String> _executeNarrateSay(
    ToolCallInfo toolCall,
    ToolExecutionContext _,
  ) async {
    final ctx = _ctx;
    if (ctx == null) return 'narrate_say: plugin not attached';
    final args = toolCall.hasArguments
        ? (jsonDecode(toolCall.arguments) as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final text = args['text']?.toString() ?? '';
    if (text.isEmpty) return 'narrate_say: empty text';
    final actor = NarrationActor.parse(args['actor']?.toString()).name;
    ctx.bus.update((current) {
      final next = Map<String, dynamic>.from(current);
      final ui = Map<String, dynamic>.from(
        (next['ui'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
      final list = List<Map<String, dynamic>>.from(
        (ui['narrations'] as List?)?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[],
      );
      list.add({'actor': actor, 'text': text});
      ui['narrations'] = list;
      next['ui'] = ui;
      return next;
    });
    return 'ok';
  }
}
