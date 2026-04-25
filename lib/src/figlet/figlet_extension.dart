import 'dart:convert';

import 'package:soliplex_agent/soliplex_agent.dart';
// ignore: implementation_imports
import 'package:soliplex_agent/src/tools/tool_execution_context.dart'
    show ToolExecutionContext;

import 'figlet_impl_stub.dart'
    if (dart.library.js_interop) 'figlet_impl_web.dart' as impl;

const _layoutValues = [
  'default',
  'full',
  'fitted',
  'controlled smushing',
  'universal smushing',
];

/// Exposes a `render_figlet` ClientTool that calls the figlet.js library
/// loaded in `web/index.html`. Web-only; on native targets the stub
/// implementation reports an unsupported-platform error in the tool
/// payload so the LLM gets a completed call rather than a thrown error.
class FigletExtension extends SessionExtension {
  @override
  String get namespace => 'figlet';

  @override
  Future<void> onAttach(AgentSession session) async {}

  @override
  void onDispose() {}

  @override
  List<ClientTool> get tools => [
        ClientTool.simple(
          name: 'list_figlet_fonts',
          description:
              'Returns the names of every figlet font available in the '
              'browser. Useful when the user asks "what fonts are there?" '
              'or you want to pick a stylistic font you have not seen '
              'before. Web-only.',
          parameters: const {'type': 'object', 'properties': {}},
          executor: _executeListFonts,
        ),
        ClientTool.simple(
          name: 'figlet_font_metadata',
          description:
              'Returns metadata for one figlet font: its parsed `.flf` '
              'header (height, hardBlank, smushing rules, layout) and the '
              "font author's free-form comment. Use this to describe a "
              'font to the user before rendering with it. Web-only.',
          parameters: const {
            'type': 'object',
            'properties': {
              'font': {
                'type': 'string',
                'description':
                    'Font name (e.g. "Standard", "Doom", "Star Wars").',
              },
            },
            'required': ['font'],
          },
          executor: _executeMetadata,
        ),
        ClientTool.simple(
          name: 'render_figlet',
          description:
              'Renders ASCII-art banner text using the figlet.js library. '
              'Useful for headings, splash text, or playful formatting in '
              'responses. Web-only — on other platforms returns an '
              "'unsupported' error in the payload. "
              'IMPORTANT: the `output` field already contains a complete '
              'fenced code block tagged ```figlet. Embed it verbatim in '
              'your response — do NOT re-wrap, re-indent, summarize, or '
              'add any prose inside the fence. The chat renders the '
              '```figlet fence with a custom widget that needs the '
              'whitespace preserved exactly. Call the tool exactly once '
              'per banner the user asks for.',
          parameters: const {
            'type': 'object',
            'properties': {
              'text': {
                'type': 'string',
                'description': 'Text to render as ASCII art.',
              },
              'font': {
                'type': 'string',
                'description': 'Figlet font name. Examples by flavor — plain: '
                    '"Standard", "Big", "Mini", "Small", "Term", "Thin"; '
                    'slant/italic: "Slant", "Small Slant", '
                    '"Slant Relief"; heavy/blocky: "Block", "Banner", '
                    '"Doh", "Doom", "Stop"; decorative: "Bubble", '
                    '"Ghost", "Graffiti", "Whimsy"; 3D-ish: "Larry 3D", '
                    '"Star Wars", "Univers"; script: "Script", "Soft"; '
                    'shadow/outline: "Shadow", "Speed". Defaults to '
                    '"Standard". Pick a font that matches the user\'s '
                    'tone (fancy, big, small, playful, etc.).',
              },
              'horizontalLayout': {
                'type': 'string',
                'enum': _layoutValues,
                'description':
                    'How adjacent letters merge horizontally. "default" '
                        'uses the font\'s baked-in rules; "full" keeps full '
                        'spacing (no merging); "fitted" minimal merging; '
                        '"controlled smushing" / "universal smushing" '
                        'aggressively overlap glyphs. Default: "default".',
              },
              'verticalLayout': {
                'type': 'string',
                'enum': _layoutValues,
                'description': 'Same options as horizontalLayout but applied '
                    'vertically. Mostly relevant for tall fonts. '
                    'Default: "default".',
              },
              'width': {
                'type': 'integer',
                'description': 'Maximum output width in columns. Combined with '
                    'whitespaceBreak this word-wraps long inputs across '
                    'multiple banner-rows. Omit for no wrapping.',
              },
              'whitespaceBreak': {
                'type': 'boolean',
                'description':
                    'When true, breaks at whitespace within `width` so '
                        'multi-word input wraps cleanly. Has no effect '
                        'without `width`. Default: false.',
              },
            },
            'required': ['text'],
          },
          executor: _execute,
        ),
      ];

  Future<String> _execute(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    final String text;
    final String? font;
    final String? horizontalLayout;
    final String? verticalLayout;
    final int? width;
    final bool? whitespaceBreak;
    try {
      final args = toolCall.arguments.isEmpty
          ? const <String, Object?>{}
          : jsonDecode(toolCall.arguments) as Map<String, Object?>;
      final rawText = args['text'];
      if (rawText is! String) {
        return jsonEncode({
          'error': 'render_figlet: "text" argument must be a string',
        });
      }
      text = rawText;
      font = args['font'] is String ? args['font'] as String : null;
      horizontalLayout = args['horizontalLayout'] is String
          ? args['horizontalLayout'] as String
          : null;
      verticalLayout = args['verticalLayout'] is String
          ? args['verticalLayout'] as String
          : null;
      width = args['width'] is int ? args['width'] as int : null;
      whitespaceBreak = args['whitespaceBreak'] is bool
          ? args['whitespaceBreak'] as bool
          : null;

      final allowed = _layoutValues.toSet();
      for (final entry in [
        ('horizontalLayout', horizontalLayout),
        ('verticalLayout', verticalLayout),
      ]) {
        final value = entry.$2;
        if (value != null && !allowed.contains(value)) {
          return jsonEncode({
            'error':
                'render_figlet: ${entry.$1}="$value" is not one of $_layoutValues',
          });
        }
      }
    } on Object catch (e) {
      return jsonEncode({
        'error': 'render_figlet: failed to parse arguments: $e',
      });
    }

    try {
      final rendered = await impl.renderFiglet(
        text,
        font: font,
        horizontalLayout: horizontalLayout,
        verticalLayout: verticalLayout,
        width: width,
        whitespaceBreak: whitespaceBreak,
      );
      return jsonEncode({'output': '```figlet\n$rendered\n```'});
    } on Object catch (e) {
      return jsonEncode({'error': 'render_figlet: $e'});
    }
  }

  Future<String> _executeListFonts(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    try {
      final fonts = await impl.listFiglets();
      return jsonEncode({'fonts': fonts, 'count': fonts.length});
    } on Object catch (e) {
      return jsonEncode({'error': 'list_figlet_fonts: $e'});
    }
  }

  Future<String> _executeMetadata(
    ToolCallInfo toolCall,
    ToolExecutionContext context,
  ) async {
    final String font;
    try {
      final args = toolCall.arguments.isEmpty
          ? const <String, Object?>{}
          : jsonDecode(toolCall.arguments) as Map<String, Object?>;
      final rawFont = args['font'];
      if (rawFont is! String) {
        return jsonEncode({
          'error': 'figlet_font_metadata: "font" argument must be a string',
        });
      }
      font = rawFont;
    } on Object catch (e) {
      return jsonEncode({
        'error': 'figlet_font_metadata: failed to parse arguments: $e',
      });
    }

    try {
      final meta = await impl.figletMetadata(font);
      return jsonEncode({'font': font, ...meta});
    } on Object catch (e) {
      return jsonEncode({'error': 'figlet_font_metadata: $e'});
    }
  }
}
