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

  /// Streams progress to [onPart] and returns the complete validated result.
  Future<List<AgentToRendererMessage>> parseStream(
    Stream<String> chunks, {
    void Function(ResponsePart part)? onPart,
  }) async {
    final response = StringBuffer();
    ContinuingResponseStream? stream;
    try {
      stream = _processor.openContinuingStream();
    } on Object {
      // The complete parser below owns the returned result and validation.
    }
    await for (final chunk in chunks) {
      response.write(chunk);
      if (stream != null) {
        try {
          _consumeStreamParts(stream.feed(chunk), onPart);
        } on Object {
          // The complete parser below owns the returned result and validation.
        }
      }
    }
    if (stream != null) {
      try {
        _consumeStreamParts(stream.close(), onPart);
      } on Object {
        // A progressive stream error must not override complete parsing.
      }
    }
    return parse(response.toString());
  }
}

InferenceFormatFactory _formatFactory(A2uiReplyFormat format) =>
    switch (format) {
      A2uiReplyFormat.express => const ExpressFormatFactory(),
      A2uiReplyFormat.json => const DirectJsonFormatFactory(),
    };

void _consumeStreamParts(
  List<StreamPart> parts,
  void Function(ResponsePart part)? onPart,
) {
  for (final part in parts) {
    switch (part) {
      case ErrorPart():
        continue;
      case ResponsePart():
        onPart?.call(part);
    }
  }
}
