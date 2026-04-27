import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'narration.dart';

/// A [SessionExtension] that exposes narration writes on two surfaces:
///
/// - **LLM tool** (`narrate_say`) declared in [tools].
/// - **Python host functions** (`narrate_say`, `narrate_clear`)
///   declared in [hostFunctions]. The bridge in `soliplex_agent_monty`
///   (Phase 2 step 9) synthesizes a [`MontyExtension`] for these
///   automatically — this plugin does not import `dart_monty`.
///
/// Both surfaces share the same private helpers
/// [_appendNarration] and [_clearNarrations], so the LLM-driven path
/// and the Python-driven path mutate the bus identically. The existing
/// `NarrationProjection` (in `narration_controller.dart`) reads
/// `/ui/narrations`, so each entry flows: bus delta → projection →
/// `NarrationController._entries` → `NarrationPanel`.
///
/// Plan reference: `docs/plans/reactive-bus-redesign.md` (Phase 1
/// step 4 + Phase 2 step 10).
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

  @override
  List<HostFunction> get hostFunctions => [
        HostFunction(
          schema: const HostFunctionSchema(
            name: 'narrate_say',
            description: 'Emit a narration line to the on-screen log. Pass '
                '`actor` to attribute the line to one of the four '
                'rendering buckets: "coordinator" | "primary" | '
                '"secondary" | "field". Aliases (hq, dispatch, lead, '
                'support, ground, site, reporter, …) accepted; see '
                'NarrationActor.parse. Defaults to "primary". '
                'Returns "ok" on success.',
            params: [
              HostParam(name: 'text', type: HostParamType.string),
              HostParam(
                name: 'actor',
                type: HostParamType.string,
                isRequired: false,
              ),
            ],
          ),
          handler: (args, ctx) async {
            final text = (args['text'] as String?)?.trim() ?? '';
            if (text.isEmpty) return 'narrate_say: empty text';
            final actor = NarrationActor.parse(args['actor'] as String?).name;
            _appendNarration(ctx, actor: actor, text: text);
            return 'ok';
          },
        ),
        HostFunction(
          schema: const HostFunctionSchema(
            name: 'narrate_clear',
            description: 'Clear the narration log. Call at the start of a '
                'script so each run begins on a clean board.',
            params: [],
          ),
          handler: (args, ctx) async {
            _clearNarrations(ctx);
            return true;
          },
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
    final text = args['text']?.toString().trim() ?? '';
    if (text.isEmpty) return 'narrate_say: empty text';
    final actor = NarrationActor.parse(args['actor']?.toString()).name;
    _appendNarration(ctx, actor: actor, text: text);
    return 'ok';
  }

  void _appendNarration(
    SessionContext ctx, {
    required String actor,
    required String text,
  }) {
    appendNarrationToBus(ctx.bus, actor: actor, text: text);
  }

  void _clearNarrations(SessionContext ctx) {
    clearNarrationsOnBus(ctx.bus);
  }
}

/// Appends a narration entry to `agentState['ui']['narrations']`.
///
/// Pure top-level helper: takes a [StateBus] directly so unit tests
/// can exercise the mutation without booting an [AgentSession] or a
/// [SessionContext]. Plugin handlers call this through their
/// `SessionContext.bus` reference.
@visibleForTesting
void appendNarrationToBus(
  StateBus bus, {
  required String actor,
  required String text,
}) {
  bus.update(
    (current) {
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
    },
    tag: 'narration.append',
  );
}

/// Clears `agentState['ui']['narrations']`.
///
/// Pure top-level helper paired with [appendNarrationToBus].
@visibleForTesting
void clearNarrationsOnBus(StateBus bus) {
  bus.update(
    (current) {
      final next = Map<String, dynamic>.from(current);
      final ui = Map<String, dynamic>.from(
        (next['ui'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
      ui['narrations'] = const <Map<String, dynamic>>[];
      next['ui'] = ui;
      return next;
    },
    tag: 'narration.clear',
  );
}
