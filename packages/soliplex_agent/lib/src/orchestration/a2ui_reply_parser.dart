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
      A2uiNegotiatedReply(_generator.createProcessor(capabilities), format);
}

/// A reply parser bound to the catalogs and protocol negotiated for a renderer.
class A2uiNegotiatedReply {
  const A2uiNegotiatedReply(this._processor, this._format);

  final A2uiRequestProcessor _processor;
  final A2uiReplyFormat _format;

  /// Parses and validates a complete model reply, returning only A2UI messages.
  List<AgentToRendererMessage> parse(String reply) => [
        for (final ResponsePart part in _processor.parseResponse(reply))
          if (part case A2uiPart(:final a2ui)) ...a2ui,
      ];

  /// Parses a streamed reply incrementally and returns the emitted messages.
  Future<List<AgentToRendererMessage>> parseStream(
    Stream<String> chunks, {
    void Function(ResponsePart part)? onPart,
  }) async {
    final state = _DeferredTopologyRendererState(_processor.activeCatalogs);
    final stream = _processor.openContinuingStream(state: state);
    final parts = <ResponsePart>[];
    final currentBlockParts = <ResponsePart>[];
    final closingTag = switch (_format) {
      A2uiReplyFormat.express => '</a2ui>',
      A2uiReplyFormat.json => '</a2ui-json>',
    };
    var pending = '';

    void collect(List<StreamPart> streamedParts) {
      currentBlockParts.addAll(_consumeStreamParts(streamedParts, onPart));
    }

    void finishBlock() {
      final blockParts = _format == A2uiReplyFormat.express
          ? _mergeProvisionalExpressUpdates(
              currentBlockParts
                  .whereType<A2uiPart>()
                  .expand((part) => part.a2ui)
                  .toList(),
            )
          : null;
      if (blockParts == null) {
        parts.addAll(currentBlockParts);
      } else {
        var inserted = false;
        for (final part in currentBlockParts) {
          if (part is A2uiPart) {
            if (!inserted && blockParts.isNotEmpty) {
              parts.add(A2uiPart(blockParts));
              inserted = true;
            }
          } else {
            parts.add(part);
          }
        }
      }
      currentBlockParts.clear();
    }

    try {
      await for (final chunk in chunks) {
        var input = '$pending$chunk';
        pending = '';
        var close = input.indexOf(closingTag);
        while (close >= 0) {
          final end = close + closingTag.length;
          collect(stream.feed(input.substring(0, end)));
          finishBlock();
          input = input.substring(end);
          close = input.indexOf(closingTag);
        }
        final safeLength = input.length - closingTag.length + 1;
        if (safeLength > 0) {
          collect(stream.feed(input.substring(0, safeLength)));
          pending = input.substring(safeLength);
        } else {
          pending = input;
        }
      }
      if (pending.isNotEmpty) collect(stream.feed(pending));
      collect(stream.close());
      finishBlock();
      final touched = <String>{
        for (final part in parts)
          if (part is A2uiPart)
            for (final message in part.a2ui)
              if (message case CreateSurfaceMessage(:final surfaceId))
                surfaceId
              else if (message case UpdateComponentsMessage(:final surfaceId))
                surfaceId
              else if (message case UpdateDataModelMessage(:final surfaceId))
                surfaceId
              else if (message case DeleteSurfaceMessage(:final surfaceId))
                surfaceId,
      };
      state.checkTopology(touched);
      final messages = [
        for (final part in parts)
          if (part case A2uiPart(:final a2ui)) ...a2ui,
      ];
      return _format == A2uiReplyFormat.express
          ? _mergeProvisionalExpressUpdates(messages)
          : messages;
    } finally {
      state.dispose();
    }
  }
}

List<AgentToRendererMessage> _mergeProvisionalExpressUpdates(
  List<AgentToRendererMessage> messages,
) {
  final result = <AgentToRendererMessage>[];
  for (final message in messages) {
    if (message
        case UpdateComponentsMessage(:final surfaceId, :final components)) {
      final createIndex = result.lastIndexWhere(
        (candidate) =>
            candidate is CreateSurfaceMessage &&
            candidate.surfaceId == surfaceId &&
            candidate.components != null,
      );
      if (createIndex >= 0) {
        final create = result[createIndex] as CreateSurfaceMessage;
        final original = create.components!;
        final originalIds =
            original.map((component) => component['id']).toSet();
        if (components
            .every((component) => originalIds.contains(component['id']))) {
          final replacements = {
            for (final component in components) component['id']: component,
          };
          result[createIndex] = CreateSurfaceMessage(
            version: create.version,
            surfaceId: create.surfaceId,
            catalogId: create.catalogId,
            theme: create.theme,
            sendDataModel: create.sendDataModel,
            components: [
              for (final component in original)
                replacements[component['id']] ?? component,
            ],
            dataModel: create.dataModel,
            metadata: create.metadata,
          );
          continue;
        }
      }
    }
    result.add(message);
  }
  return result;
}

InferenceFormatFactory _formatFactory(A2uiReplyFormat format) =>
    switch (format) {
      A2uiReplyFormat.express => const ExpressFormatFactory(),
      A2uiReplyFormat.json => const DirectJsonFormatFactory(),
    };

List<ResponsePart> _consumeStreamParts(
  List<StreamPart> parts,
  void Function(ResponsePart part)? onPart,
) {
  final responseParts = <ResponsePart>[];
  for (final part in parts) {
    switch (part) {
      case ErrorPart(:final error):
        throw error;
      case ResponsePart():
        responseParts.add(part);
        onPart?.call(part);
    }
  }
  return responseParts;
}

/// Lets blocks contribute to one final tree check instead of checking each
/// closing block before later blocks can resolve its references.
class _DeferredTopologyRendererState extends RendererState {
  _DeferredTopologyRendererState(super.catalogs);

  @override
  void checkTopology(Iterable<String> surfaceIds) {}
}
