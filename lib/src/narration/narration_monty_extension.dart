import 'package:dart_monty/dart_monty_bridge.dart'
    show
        HostFunction,
        HostFunctionSchema,
        HostParam,
        HostParamType,
        MontyExtension;

import 'narration.dart';
import 'narration_controller.dart';

/// Exposes Python externals for emitting narration log lines from
/// scripts. Wraps the [NarrationController] singleton — a fresh
/// extension instance per runtime, but they all funnel into the same
/// log signal that the UI reads.
class NarrationMontyExtension extends MontyExtension {
  NarrationMontyExtension(this._controller);

  final NarrationController _controller;

  @override
  String get namespace => 'narrate';

  @override
  List<HostFunction> get functions => [
        HostFunction(
          schema: HostFunctionSchema(
            name: 'narrate_say',
            description: 'Emit a narration line to the on-screen log. Pass '
                '`actor` to attribute the line to one of the four '
                'rendering buckets: "coordinator" | "primary" | '
                '"secondary" | "field". Aliases (hq, dispatch, lead, '
                'support, ground, site, reporter, …) accepted; see '
                'NarrationActor.parse. Defaults to "primary". '
                'Returns the narration id.',
            params: const [
              HostParam(name: 'text', type: HostParamType.string),
              HostParam(
                name: 'actor',
                type: HostParamType.string,
                isRequired: false,
                defaultValue: 'primary',
              ),
            ],
          ),
          handler: (args, ctx) async {
            final text = (args['text'] as String?)?.trim() ?? '';
            if (text.isEmpty) return '';
            final actor = NarrationActor.parse(args['actor'] as String?);
            final entry = _controller.add(actor: actor, text: text);
            return entry.id;
          },
        ),
        HostFunction(
          schema: HostFunctionSchema(
            name: 'narrate_clear',
            description: 'Clear the narration log. Call at the start of a '
                'script so each run begins on a clean board.',
            params: const [],
          ),
          handler: (args, ctx) async {
            _controller.clear();
            return true;
          },
        ),
      ];
}
