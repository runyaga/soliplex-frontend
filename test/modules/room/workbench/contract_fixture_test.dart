import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/workbench/workbench_fixtures.g.dart';

const _digests = <String, String>{
  'snapshot_content_v1.json':
      '1615980ad68b18de8bf4af23b60a4c158dbbfa4c9f7ca8fb69b4ab232e47a7d6',
  'snapshot_fresh_v1.json':
      'cfb1c76e3cced37771b26483fdff0d4e3d847cffd6b2e7db18aeb122fabcc886',
  'content_v1.json':
      '55c062166bf65c5a34700d0e484edf054963dc4bda5ea88dcaec6eeb9d13f2e2',
  'export_action_v1.json':
      'a855f678939f4c955576a19be3a7902df45bc70e7ae9e4460ecc47a9f2452606',
  'handoff_pointer_v1.json':
      '257e670dc3261bce37ececea2ed2744a5bdef4ef052014907e37ac4b95659936',
  'intake_action_v1.json':
      '4158e1b2110a938b8678189f36594607c4ddb7bac1eb0ccffde4fad72c5e42c1',
  'layout_rejections_v1.json':
      '66a696c0f7424657c09bc2ab922a1f4946a6d2dd8b541b716c33e1dc29a69238',
  'layout_tree_v1.json':
      '9534b4f57e922c55b288070ed84856fcff33af7f72907f34bebb7f82f4e6e696',
  'nested_tree_v1.json':
      'c9f314806e63ad08debdfaf961ae054c7c26e0001e79fa320000454cdffe9e0c',
  'python_sides_v1.json':
      'e02f91610459c62479b6c78981a952e51353994577afd537469ef97a3308e8c0',
};

void main() {
  group('workbench frozen contract fixtures', () {
    test('fixture bytes match Python SHA-256 contract', _matchesDigests);
    test('layout fixtures preserve IDs and numeric types', _loadsLayouts);
    test('content and action fixtures retain typed payloads', _loadsActions);
    test('Python sides and handoff retain their contracts', _loadsPythonSides);
  });
}

Map<String, dynamic> _readFixture(String name) =>
    jsonDecode(workbenchFixtures[name]!) as Map<String, dynamic>;

void _matchesDigests() {
  expect(workbenchFixtures.keys.toSet(), _digests.keys.toSet());
  for (final entry in _digests.entries) {
    final bytes = utf8.encode(workbenchFixtures[entry.key]!);
    expect(sha256.convert(bytes).toString(), entry.value);
  }
}

void _loadsLayouts() {
  final basic = _readFixture('layout_tree_v1.json');
  final nested = _readFixture('nested_tree_v1.json');
  expect(basic['rootId'], 'wb_root');
  expect(basic['schemaVersion'], 1);
  expect(nested['layoutRevision'], isA<int>());
  final nodes = (nested['nodes'] as List).cast<Map<String, dynamic>>();
  expect(
      nodes.map((node) => node['id']),
      containsAll([
        'left_tabs',
        'chart_surface',
        'program_surface',
        'help_surface',
      ]));
  expect(_treeDepth(nodes), 8);
}

int _treeDepth(List<Map<String, dynamic>> nodes) {
  final byId = {for (final node in nodes) node['id'] as String: node};
  return _nodeDepth(byId, 'wb_root');
}

int _nodeDepth(Map<String, Map<String, dynamic>> nodes, String id) {
  final children = (nodes[id]!['children'] as List).cast<String>();
  if (children.isEmpty) return 1;
  return 1 +
      children
          .map((child) => _nodeDepth(nodes, child))
          .reduce((left, right) => left > right ? left : right);
}

void _loadsActions() {
  final content = _readFixture('content_v1.json');
  final intake = _readFixture('intake_action_v1.json');
  final exported = _readFixture('export_action_v1.json');
  expect(content['component'], 'Chart');
  expect(intake['userAction']['acknowledged'], isTrue);
  expect(exported['userAction']['points'][0]['value'], 80);
}

void _loadsPythonSides() {
  final sides = _readFixture('python_sides_v1.json');
  final handoff = _readFixture('handoff_pointer_v1.json');
  expect(sides['disabledServerResult']['execution'], 'disabled');
  expect(sides['disabledServerResult'].keys,
      containsAll(['status', 'code', 'tool', 'side', 'execution']));
  expect(handoff['sha256'], hasLength(64));
  expect(handoff['hop'], 0);
}
