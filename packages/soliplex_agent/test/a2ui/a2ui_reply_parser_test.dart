import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

void main() {
  final catalog = Catalog.fromJson({
    'catalogId': 'test.catalog',
    'protocolVersion': '1.0',
    'components': {
      'Text': {
        'type': 'object',
        'properties': {
          'component': {'const': 'Text'},
          'text': {'type': 'string'},
        },
        'required': ['component', 'text'],
      },
    },
  });
  final parser = A2uiReplyParser(
    catalogs: [CatalogConfig(catalog)],
  );
  final capabilities = A2uiRendererCapabilities.forCatalogIds(
    ['test.catalog'],
    version: A2uiProtocolVersion.v1_0,
  );

  test('parses Express and JSON replies into equivalent messages', () {
    const express = '<a2ui>surface("s", "test.catalog"); '
        'root = Text("Hello")</a2ui>';
    const json = '<a2ui-json>[{"version":"1.0","createSurface":'
        '{"surfaceId":"s","catalogId":"test.catalog",'
        '"components":[{"id":"root","component":"Text",'
        '"text":"Hello"}]}}]</a2ui-json>';
    final expressMessages = parser.negotiate(capabilities).parse(express);
    final jsonMessages = A2uiReplyParser(
      catalogs: [CatalogConfig(catalog)],
      format: A2uiReplyFormat.json,
    ).negotiate(capabilities).parse(json);
    expect(
      [for (final message in expressMessages) message.toJson()],
      [for (final message in jsonMessages) message.toJson()],
    );
  });

  test('rejects components outside the negotiated catalog', () {
    expect(
      () => parser.negotiate(capabilities).parse(
            '<a2ui>surface("s", "test.catalog"); root = Unknown()</a2ui>',
          ),
      throwsA(isA<A2uiError>()),
    );
  });

  test('streamed parsing returns the complete response messages', () async {
    final reply = parser.negotiate(capabilities);
    final complete = reply.parse(
      '<a2ui>surface("s", "test.catalog"); root = Text("Hello")</a2ui>',
    );
    final streamed = await reply.parseStream(
      Stream<String>.fromIterable([
        '<a2ui>surface("s", "test.catalog"); ',
        'root = Text("Hello")</a2ui>',
      ]),
    );
    expect(
      [for (final message in streamed) message.toJson()],
      [for (final message in complete) message.toJson()],
    );
  });

  test('rejects a renderer with no supported catalog protocol', () {
    expect(
      () => parser.negotiate(
        A2uiRendererCapabilities.forCatalogIds(
          ['test.catalog'],
        ),
      ),
      throwsA(isA<A2uiError>()),
    );
  });

  test('rejects a truncated streamed block', () async {
    final reply = parser.negotiate(capabilities);
    await expectLater(
      reply.parseStream(Stream<String>.value('<a2ui>root = Text("Hello")')),
      throwsA(isA<A2uiError>()),
    );
  });
}
