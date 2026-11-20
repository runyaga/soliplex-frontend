// JSON fixtures and wire examples intentionally use dynamic maps and long strings.
// ignore_for_file: avoid_dynamic_calls, lines_longer_than_80_chars, missing_whitespace_between_adjacent_strings, require_trailing_commas

import 'dart:convert';

import 'package:a2ui_agent/a2ui_agent.dart' show A2uiPart, ResponsePart;
import 'package:a2ui_core/a2ui_core.dart' show BasicCatalog;
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

import '../../../../test/fixtures/workbench/workbench_fixtures.g.dart';
import '../fixtures/a2ui/catalog_fixtures.g.dart';

const _chartId = 'urn:soliplex:catalog:graphics:2';
const _dataId = 'urn:soliplex:catalog:data:1';
const _intakeId = 'urn:soliplex:catalog:intake:1';

Map<String, Object?> _catalog(String name) =>
    jsonDecode(a2uiCatalogDocuments[name]!) as Map<String, Object?>;

final List<CatalogConfig> _catalogs = [
  for (final name in ['chart', 'data', 'intake'])
    CatalogConfig(InMemoryCatalogProvider(_catalog(name)).load()),
];
final _capabilities = A2uiRendererCapabilities.forCatalogIds(
  [_chartId, _dataId, _intakeId],
  version: A2uiProtocolVersion.v1_0,
);

void main() {
  final parser = A2uiReplyParser(catalogs: _catalogs);

  test('Chart Express and JSON parse the frozen bar chart with expected data',
      () async {
    final frozen = jsonDecode(workbenchFixtures['content_v1.json']!)
        as Map<String, dynamic>;
    final spec = frozen['spec'];
    const express = '<a2ui>surface("surface_chart"); '
        'root = Chart(catalogId="$_chartId", spec={"kind":"bar","series":[{"id":"values",'
        '"label":"Value","points":[{"id":"north","label":"North",'
        '"value":80},{"id":"south","label":"South","value":60}]}]})'
        '</a2ui>';
    final expected = _jsonReply(
      'surface_chart',
      _chartId,
      {'component': 'Chart', 'spec': spec},
    );
    await _expectFormats(
      parser,
      express,
      expected,
      'Chart',
      'surface_chart',
      {'component': 'Chart', 'spec': spec},
    );
  });

  test('DataTable Express and JSON parse fixed keyed rows', () async {
    const component = {
      'component': 'DataTable',
      'columns': ['ID', 'Label', 'Value'],
      'rows': [
        {'id': 'north', 'label': 'North', 'value': 80},
        {'id': 'south', 'label': 'South', 'value': 60},
      ],
    };
    const express = '<a2ui>surface("surface_data"); '
        'root = DataTable(catalogId="$_dataId", columns=["ID", "Label", "Value"], rows= '
        '[{"id":"north","label":"North","value":80},'
        '{"id":"south","label":"South","value":60}])</a2ui>';
    await _expectFormats(
      parser,
      express,
      _jsonReply('surface_data', _dataId, component),
      'DataTable',
      'surface_data',
      component,
    );
  });

  test('intake form Express and JSON parse frozen submission fields', () async {
    final submission = jsonDecode(workbenchFixtures['intake_action_v1.json']!)
        as Map<String, dynamic>;
    final action = submission['userAction'] as Map<String, dynamic>;
    const component = {
      'component': 'IntakeForm',
      'title': 'District intake',
      'question': 'Which district needs support?',
      'districts': ['north'],
      'acknowledged': true,
    };
    const express = '<a2ui>surface("surface_intake"); '
        'root = IntakeForm(catalogId="$_intakeId", title="District intake", question= '
        '"Which district needs support?", districts=["north"], '
        'acknowledged=true)</a2ui>';
    await _expectFormats(
      parser,
      express,
      _jsonReply('surface_intake', _intakeId, component),
      'IntakeForm',
      'surface_intake',
      component,
    );
    expect(action, {
      'question': component['question'],
      'districts': component['districts'],
      'acknowledged': true,
    });
  });

  test('rejects components outside the negotiated catalogs', () {
    expect(
      () => parser.negotiate(_capabilities).parse(
            '<a2ui>surface("s", "$_chartId"); root = Unknown()</a2ui>',
          ),
      throwsA(isA<A2uiError>()),
    );
  });

  test('rejects a renderer with no supported protocol/catalog pairing', () {
    expect(
      () => parser.negotiate(
        A2uiRendererCapabilities.forCatalogIds([_chartId]),
      ),
      throwsA(isA<A2uiError>()),
    );
  });

  test('rejects a catalog declaring an unsupported protocol version', () {
    expect(
      () => const InMemoryCatalogProvider({
        'catalogId': 'unsupported.catalog',
        'protocolVersion': '2.0',
        'components': <String, Object?>{},
      }).load(),
      throwsA(isA<A2uiError>()),
    );
  });

  test('rejects a truncated streamed block', () async {
    await expectLater(
      parser.negotiate(_capabilities).parseStream(
            Stream<String>.value(
              '<a2ui>surface("surface_chart"); '
              'root = Chart(catalogId="$_chartId", spec={"kind":"bar"}',
            ),
          ),
      throwsA(isA<A2uiError>()),
    );
  });

  test('propagates SDK stream validation errors', () async {
    await expectLater(
      parser.negotiate(_capabilities).parseStream(
            Stream<String>.value(
              '<a2ui>surface("surface_chart"); root = Unknown()</a2ui>',
            ),
          ),
      throwsA(isA<A2uiError>()),
    );
  });

  test('streaming across a value token boundary returns canonical messages',
      () async {
    const response = '<a2ui>surface("surface_chart"); '
        'root = Chart(catalogId="$_chartId", spec={"kind":"bar","series":[{"id":"values",'
        '"label":"Value","points":[{"id":"north","label":"North",'
        '"value":80}]}]})</a2ui>';
    final split = response.indexOf('Nor') + 1;
    final complete = parser.negotiate(_capabilities).parse(response);
    var streamedPartCount = 0;
    final streamed = await parser.negotiate(_capabilities).parseStream(
          Stream<String>.fromIterable([
            response.substring(0, split),
            response.substring(split),
          ]),
          onPart: (_) => streamedPartCount++,
        );
    expect(_messageJson(streamed), _messageJson(complete));
    expect(_messageJson(streamed).single['createSurface']['components'], [
      {
        'id': 'root',
        'component': 'Chart',
        '@catalogId': _chartId,
        'spec': {
          'kind': 'bar',
          'series': [
            {
              'id': 'values',
              'label': 'Value',
              'points': [
                {'id': 'north', 'label': 'North', 'value': 80},
              ],
            },
          ],
        },
      },
    ]);
    expect(streamedPartCount, greaterThan(0));
  });

  test('Text streaming inside a value returns only the final message',
      () async {
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
    final textParser = A2uiReplyParser(
      catalogs: [CatalogConfig(catalog)],
    ).negotiate(
      A2uiRendererCapabilities.forCatalogIds(
        ['test.catalog'],
        version: A2uiProtocolVersion.v1_0,
      ),
    );
    const response = '<a2ui>surface("s"); root = Text("Hello")</a2ui>';
    final progressiveParts = <ResponsePart>[];
    final streamed = await textParser.parseStream(
      Stream<String>.fromIterable([
        '<a2ui>surface("s"); root = Text("Hel',
        'lo")</a2ui>',
      ]),
      onPart: progressiveParts.add,
    );
    final complete = textParser.parse(response);
    expect(_messageJson(streamed), _messageJson(complete));
    expect(_messageJson(streamed), [
      {
        'version': '1.0',
        'createSurface': {
          'surfaceId': 's',
          'catalogId': 'test.catalog',
          'sendDataModel': false,
          'components': [
            {'id': 'root', 'component': 'Text', 'text': 'Hello'},
          ],
        },
      },
    ]);
    expect(
      progressiveParts.whereType<A2uiPart>().expand((part) => part.a2ui),
      isNotEmpty,
    );
  });

  test('JSON stream validates topology completed by a later block', () async {
    final catalog = BasicCatalog.v0_9();
    final jsonParser = A2uiReplyParser(
      catalogs: [CatalogConfig(catalog)],
      format: A2uiReplyFormat.json,
    ).negotiate(A2uiRendererCapabilities.forCatalogIds(
      [BasicCatalog.v0_9Id],
    ));
    const response =
        '<a2ui-json>[{"version":"v0.9","createSurface":{"surfaceId":"s",'
        '"catalogId":"${BasicCatalog.v0_9Id}","sendDataModel":false}}]</a2ui-json>'
        '<a2ui-json>[{"version":"v0.9","updateComponents":{"surfaceId":"s",'
        '"components":[{"id":"root","component":"Column","children":["a"]}]}}]</a2ui-json>'
        '<a2ui-json>[{"version":"v0.9","updateComponents":{"surfaceId":"s",'
        '"components":[{"id":"a","component":"Text","text":"Ready"}]}}]</a2ui-json>';
    final complete = jsonParser.parse(response);
    final streamed = await jsonParser.parseStream(Stream.value(response));
    expect(_messageJson(streamed), _messageJson(complete));
    expect(streamed, hasLength(3));
  });

  test('streamed invalid JSON topologies match complete parsing', () async {
    final jsonParser = A2uiReplyParser(
      catalogs: [CatalogConfig(BasicCatalog.v0_9())],
      format: A2uiReplyFormat.json,
    ).negotiate(A2uiRendererCapabilities.forCatalogIds([
      BasicCatalog.v0_9Id,
    ]));
    const missingChild =
        '<a2ui-json>[{"version":"v0.9","createSurface":{"surfaceId":"s",'
        '"catalogId":"${BasicCatalog.v0_9Id}"}},{"version":"v0.9",'
        '"updateComponents":{"surfaceId":"s","components":[{"id":"root",'
        '"component":"Column","children":["a"]}]}}]</a2ui-json>';
    const missingRoot =
        '<a2ui-json>[{"version":"v0.9","createSurface":{"surfaceId":"s",'
        '"catalogId":"${BasicCatalog.v0_9Id}"}},{"version":"v0.9",'
        '"updateComponents":{"surfaceId":"s","components":[{"id":"other",'
        '"component":"Text","text":"No root"}]}}]</a2ui-json>';
    for (final reply in [missingChild, missingRoot]) {
      expect(() => jsonParser.parse(reply), throwsA(isA<A2uiError>()));
      await expectLater(
        jsonParser.parseStream(Stream.value(reply)),
        throwsA(isA<A2uiError>()),
      );
    }
  });

  test('stream preserves explicit updates across Express blocks', () async {
    final textParser = A2uiReplyParser(
      catalogs: [
        CatalogConfig(Catalog.fromJson({
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
        }))
      ],
    ).negotiate(A2uiRendererCapabilities.forCatalogIds(
      ['test.catalog'],
      version: A2uiProtocolVersion.v1_0,
    ));
    const reply = '<a2ui>surface("s"); root = Text("A")</a2ui>'
        '<a2ui>surface("s", update=true); root = Text("B")</a2ui>';
    final complete = textParser.parse(reply);
    final streamed = await textParser.parseStream(Stream.value(reply));
    expect(_messageJson(complete), hasLength(2));
    expect(_messageJson(streamed), _messageJson(complete));
  });

  test('literal closing tag text does not split streaming parsing', () async {
    final textParser = A2uiReplyParser(
      catalogs: [
        CatalogConfig(Catalog.fromJson({
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
        }))
      ],
    ).negotiate(A2uiRendererCapabilities.forCatalogIds(
      ['test.catalog'],
      version: A2uiProtocolVersion.v1_0,
    ));
    const reply = '<a2ui>surface("s"); root = Text("</a2ui>")</a2ui>';
    final complete = textParser.parse(reply);
    final streamed = await textParser.parseStream(Stream.value(reply));
    expect(_messageJson(streamed), _messageJson(complete));
  });
}

String _jsonReply(
    String surface, String catalog, Map<String, Object?> component) {
  final payload = {...component, '@catalogId': catalog};
  return '<a2ui-json>[{"version":"1.0","createSurface":{"surfaceId":"$surface",'
      '"components":[{"id":"root",'
      '${jsonEncode(payload).substring(1)}]}}]</a2ui-json>';
}

Future<void> _expectFormats(
  A2uiReplyParser parser,
  String express,
  String json,
  String componentName,
  String surfaceId,
  Map<String, Object?> expectedComponent,
) async {
  final expressMessages = parser.negotiate(_capabilities).parse(express);
  final jsonMessages = A2uiReplyParser(
    catalogs: _catalogs,
    format: A2uiReplyFormat.json,
  ).negotiate(_capabilities).parse(json);
  final expressReply = parser.negotiate(_capabilities);
  final jsonReply = A2uiReplyParser(
    catalogs: _catalogs,
    format: A2uiReplyFormat.json,
  ).negotiate(_capabilities);
  final streamedExpress = await expressReply.parseStream(
    Stream<String>.fromIterable([
      express.substring(0, express.length ~/ 2),
      express.substring(express.length ~/ 2),
    ]),
  );
  final streamedJson = await jsonReply.parseStream(
    Stream<String>.fromIterable([
      json.substring(0, json.length ~/ 2),
      json.substring(json.length ~/ 2),
    ]),
  );
  final expected = _messageJson(jsonMessages);
  final expectedCatalogId = switch (expectedComponent['component']) {
    'Chart' => _chartId,
    'DataTable' => _dataId,
    _ => _intakeId,
  };
  expect(_messageJson(expressMessages), expected);
  expect(_messageJson(streamedExpress), _messageJson(expressMessages));
  expect(_messageJson(streamedJson), _messageJson(jsonMessages));
  expect(expected, hasLength(1));
  final create = expected.single['createSurface'] as Map<String, dynamic>;
  expect(create['surfaceId'], surfaceId);
  expect(create['components'], hasLength(1));
  expect(create['components'], [
    {
      'id': 'root',
      ...expectedComponent,
      '@catalogId': expectedCatalogId,
    },
  ]);
  expect((create['components'] as List).single['component'], componentName);
}

List<Map<String, dynamic>> _messageJson(
        List<AgentToRendererMessage> messages) =>
    [for (final message in messages) message.toJson()];
