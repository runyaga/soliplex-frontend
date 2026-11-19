import 'package:a2ui_agent/a2ui_agent.dart';
import 'package:a2ui_core/a2ui_core.dart';

/// Selects the notation an agent asks its model to write.
enum A2uiReplyFormat { express, json }

/// Negotiates renderer capabilities and validates model replies with
/// `a2ui_agent`.
class A2uiReplyParser {
  A2uiReplyParser({
    required List<CatalogConfig> catalogs,
    this.format = A2uiReplyFormat.express,
  }) : _generator = A2uiGenerator(
          catalogs: catalogs,
          inferenceFormatFactory: _formatFactory(format),
        );

  final A2uiGenerator _generator;
  final A2uiReplyFormat format;

  /// Negotiates the renderer's supported protocol version and catalog set.
  A2uiNegotiatedReply negotiate(A2uiRendererCapabilities capabilities) =>
      A2uiNegotiatedReply(_generator.createProcessor(capabilities));
}

/// A reply parser bound to the catalogs and protocol negotiated for a renderer.
class A2uiNegotiatedReply {
  const A2uiNegotiatedReply(this._processor);

  final A2uiRequestProcessor _processor;

  /// Parses and validates a complete model reply, returning only A2UI messages.
  List<AgentToRendererMessage> parse(String reply) => [
        for (final ResponsePart part in _processor.parseResponse(reply))
          if (part case A2uiPart(:final a2ui)) ...a2ui,
      ];

  /// Parses a streamed reply incrementally and returns the emitted messages.
  Future<List<AgentToRendererMessage>> parseStream(
    Stream<String> chunks,
  ) async {
    final stream = _processor.openStream();
    final response = StringBuffer();
    await for (final chunk in chunks) {
      response.write(chunk);
      _checkStreamParts(stream.feed(chunk));
    }
    _checkStreamParts(stream.close());
    return parse(response.toString());
  }
}

InferenceFormatFactory _formatFactory(A2uiReplyFormat format) =>
    switch (format) {
      A2uiReplyFormat.express => const ExpressFormatFactory(),
      A2uiReplyFormat.json => const DirectJsonFormatFactory(),
    };

void _checkStreamParts(List<StreamPart> parts) {
  for (final part in parts) {
    if (part case ErrorPart(:final error)) throw error;
  }
}
