// ignore_for_file: avoid_dynamic_calls, require_trailing_commas

import 'dart:convert';

import 'package:soliplex_client/src/domain/workbench_snapshot.dart';
import 'package:test/test.dart';

import '../../../../test/fixtures/workbench/workbench_fixtures.g.dart';

void main() {
  test('rejects empty layouts and closed reserved nodes', () {
    expect(
      () => WorkbenchSnapshot.fromJson({
        'revision': 1,
        'layout': {
          'schemaVersion': 1,
          'layoutRevision': 1,
          'nodes': <Object?>[],
        },
        'registrations': <Object?>[],
        'records': <Object?>[],
      }),
      throwsFormatException,
    );
    final layout = jsonDecode(workbenchFixtures['layout_tree_v1.json']!)
        as Map<String, dynamic>;
    (layout['nodes'] as List)[1]['visibility'] = 'closed';
    expect(
      () => WorkbenchSnapshot.fromJson({
        'revision': 1,
        'layout': layout,
        'registrations': <Object?>[],
        'records': <Object?>[],
      }),
      throwsFormatException,
    );
  });

  test('validates the frozen layout acceptance and rejection cases', () {
    final layout = jsonDecode(workbenchFixtures['layout_tree_v1.json']!)
        as Map<String, dynamic>;
    expect(
      () => _parseSnapshot(layout),
      returnsNormally,
    );
    final nested = jsonDecode(workbenchFixtures['nested_tree_v1.json']!)
        as Map<String, dynamic>;
    expect(() => _parseSnapshot(nested), returnsNormally);

    final fixtureCases =
        (jsonDecode(workbenchFixtures['layout_rejections_v1.json']!)
            as Map<String, dynamic>)['cases'] as List;
    final layoutCases = fixtureCases
        .where((name) =>
            name is String &&
            !name.startsWith('point_') &&
            name != 'duplicate_point_id')
        .cast<String>();
    expect(layoutCases, hasLength(10));
    for (final name in layoutCases) {
      expect(
        () => _parseSnapshot(
          _rejectedLayout(name),
          excludeActivity: name == 'cross_scope_mount' ? 'activity_form' : null,
        ),
        throwsFormatException,
        reason: name,
      );
    }
  });

  test(
    'copies nested input and keeps publication parts by stable identity',
    () {
      final source = <String, dynamic>{
        'revision': 3,
        'layout': jsonDecode(workbenchFixtures['layout_tree_v1.json']!),
        'registrations': <Object?>[
          {
            'role': 'content',
            'activityMessageId': 'a1',
            'surfaceId': 's1',
          },
        ],
        'records': <Object?>[
          {
            'recordId': 'r1',
            'sequence': 4,
            'partIndex': 1,
            'partCount': 2,
            'content': {'n': 2},
          },
          {
            'recordId': 'r1',
            'sequence': 4,
            'partIndex': 0,
            'partCount': 2,
            'content': {'n': 1},
          },
        ],
      };
      final snapshot = WorkbenchSnapshot.fromJson(source);
      (source['records'] as List).clear();
      expect(snapshot.records.map((record) => record.partIndex), [0, 1]);
      expect(snapshot.records.first.identity, 'r1:0/2');
      expect(
        () => snapshot.records.first.content['n'] = 5,
        throwsUnsupportedError,
      );
    },
  );

  test('rejects unknown roles and malformed registration metadata', () {
    expect(
      () => WorkbenchRegistration.fromJson({
        'role': 'admin',
        'activityMessageId': 'a1',
        'surfaceId': 's1',
      }),
      throwsFormatException,
    );
    expect(
      () => WorkbenchRegistration.fromJson({
        'role': 'content',
        'surfaceId': 's1',
      }),
      throwsFormatException,
    );
  });

  test('rejects nested registration role fields', () {
    expect(
      () => WorkbenchActivityMetadata.fromJson({
        'role': 'content',
        'registration': {
          'activityMessageId': 'a1',
          'surfaceId': 's1',
          'role': 'admin',
        },
        'sequence': 1,
        'revision': 1,
        'publicationId': 'p1',
        'partIndex': 0,
        'partCount': 1,
      }),
      throwsFormatException,
    );
  });
}

WorkbenchSnapshot _parseSnapshot(
  Map<String, dynamic> layout, {
  String? excludeActivity,
}) {
  final registrations = [
    for (final node in (layout['nodes'] as List).cast<Map<String, dynamic>>())
      if (node['kind'] == 'surface')
        if (node['payload']['activityMessageId'] != excludeActivity)
          {
            'role': node['payload']['activityMessageId'] == 'activity_python'
                ? 'program'
                : 'content',
            'activityMessageId': node['payload']['activityMessageId'],
            'surfaceId': node['payload']['surfaceId'],
          },
  ];
  return WorkbenchSnapshot.fromJson({
    'revision': 1,
    'layout': layout,
    'registrations': registrations,
    'records': <Object?>[],
  });
}

Map<String, dynamic> _rejectedLayout(String name) {
  final base = jsonDecode(workbenchFixtures['layout_tree_v1.json']!)
      as Map<String, dynamic>;
  final nodes = base['nodes'] as List;
  switch (name) {
    case 'cycle':
      final nested = jsonDecode(workbenchFixtures['nested_tree_v1.json']!)
          as Map<String, dynamic>;
      (nested['nodes'] as List).addAll([
        {
          'id': 'cycle_tabs',
          'parentId': 'cycle_split',
          'children': ['cycle_split'],
          'kind': 'tabs',
          'title': 'Cycle',
          'size': 'medium',
          'visibility': 'open',
          'payload': <String, Object?>{},
        },
        {
          'id': 'cycle_split',
          'parentId': 'cycle_tabs',
          'children': ['cycle_tabs'],
          'kind': 'split',
          'title': 'Cycle',
          'size': 'medium',
          'visibility': 'open',
          'payload': {'axis': 'horizontal'},
        },
      ]);
      return nested;
    case 'duplicate_id':
      nodes.add(Map<String, dynamic>.from(nodes.last as Map));
    case 'depth_9':
      final nested = jsonDecode(workbenchFixtures['nested_tree_v1.json']!)
          as Map<String, dynamic>;
      final nestedNodes = nested['nodes'] as List;
      final split = nestedNodes.firstWhere((n) => n['id'] == 'depth_split');
      split['children'].add('depth_split_2');
      nestedNodes.addAll([
        {
          'id': 'depth_split_2',
          'parentId': 'depth_split',
          'children': ['depth_panel_2'],
          'kind': 'split',
          'title': 'Nested',
          'size': 'medium',
          'visibility': 'open',
          'payload': {'axis': 'horizontal'},
        },
        {
          'id': 'depth_panel_2',
          'parentId': 'depth_split_2',
          'children': ['depth_surface_2'],
          'kind': 'panel',
          'title': 'Deep',
          'size': 'medium',
          'visibility': 'open',
          'payload': <String, Object?>{},
        },
        {
          'id': 'depth_surface_2',
          'parentId': 'depth_panel_2',
          'children': <Object?>[],
          'kind': 'surface',
          'title': 'Deep',
          'size': 'medium',
          'visibility': 'open',
          'payload': {
            'activityMessageId': 'activity_deep',
            'surfaceId': 'surface_deep'
          },
        },
      ]);
      return nested;
    case 'orphan':
      nodes.add({
        'id': 'orphan',
        'parentId': null,
        'children': <Object?>[],
        'kind': 'panel',
        'title': 'Orphan',
        'size': 'medium',
        'visibility': 'open',
        'payload': <String, Object?>{},
      });
    case 'inconsistent_children':
      (nodes.firstWhere((n) => n['id'] == 'r_left') as Map)['children'] = [
        'r_right'
      ];
    case 'wrong_parent_kind':
      (nodes.firstWhere((n) => n['id'] == 'r_chat') as Map)['children'] = [
        'r_left'
      ];
    case 'protected_chat_mutation':
      (nodes.firstWhere((n) => n['id'] == 'r_chat') as Map)['children'] = [
        'r_tray'
      ];
    case 'duplicate_mount':
      final nested = jsonDecode(workbenchFixtures['nested_tree_v1.json']!)
          as Map<String, dynamic>;
      final nestedNodes = nested['nodes'] as List;
      final byId = {for (final node in nestedNodes) node['id']: node};
      byId['chart_surface']['payload'] = byId['form_surface']['payload'];
      return nested;
    case 'cross_scope_mount':
      final nested = jsonDecode(workbenchFixtures['nested_tree_v1.json']!)
          as Map<String, dynamic>;
      return nested;
    case 'oversized_utf8':
      (base['shared'] as Map<String, dynamic>)['large'] = 'é' * 33000;
    default:
      throw StateError('Unknown layout rejection fixture: $name');
  }
  return base;
}
