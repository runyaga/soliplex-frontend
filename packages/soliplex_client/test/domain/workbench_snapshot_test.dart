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

  test(
    'schemaVersion requires an integer value',
    () {
      final layout = jsonDecode(workbenchFixtures['layout_tree_v1.json']!)
          as Map<String, dynamic>;
      layout['schemaVersion'] = 1.0;
      expect(() => _parseSnapshot(layout), throwsFormatException);
    },
    // dart2js represents 1.0 and 1 as the same JavaScript number.
    // The VM and dart2wasm keep int and double distinct.
    testOn: '!js',
  );

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
      WorkbenchSnapshot parse() => _parseSnapshot(
            _rejectedLayout(name),
            excludeActivity:
                name == 'cross_scope_mount' ? 'activity_form' : null,
          );
      final expectedReason = switch (name) {
        'cycle' => 'cycle',
        'duplicate_mount' => 'duplicate mount',
        'wrong_parent_kind' => 'wrong parent kind',
        'protected_chat_mutation' => 'chat and tray cannot have children',
        _ => null,
      };
      if (expectedReason == null) {
        expect(parse, throwsFormatException, reason: name);
      } else {
        expect(
          parse,
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains(expectedReason),
            ),
          ),
          reason: name,
        );
      }
    }
  });

  test('layout verdict is independent of node-list ordering', () {
    for (final fixtureName in ['layout_tree_v1.json', 'nested_tree_v1.json']) {
      final base =
          jsonDecode(workbenchFixtures[fixtureName]!) as Map<String, dynamic>;
      final sourceNodes = base['nodes'] as List;
      for (var offset = 0; offset < sourceNodes.length; offset++) {
        final layout =
            jsonDecode(workbenchFixtures[fixtureName]!) as Map<String, dynamic>;
        final nodes = layout['nodes'] as List;
        layout['nodes'] = [
          ...nodes.skip(offset),
          ...nodes.take(offset),
        ];
        expect(() => _parseSnapshot(layout), returnsNormally,
            reason: '$fixtureName rotated by $offset');
      }
      final reversed =
          jsonDecode(workbenchFixtures[fixtureName]!) as Map<String, dynamic>;
      reversed['nodes'] = (reversed['nodes'] as List).reversed.toList();
      expect(() => _parseSnapshot(reversed), returnsNormally,
          reason: '$fixtureName reversed');
    }

    final cases = (jsonDecode(workbenchFixtures['layout_rejections_v1.json']!)
        as Map<String, dynamic>)['cases'] as List;
    for (final name in cases.whereType<String>().where(
          (name) => !name.startsWith('point_') && name != 'duplicate_point_id',
        )) {
      final layout = _rejectedLayout(name);
      (layout['nodes'] as List).setAll(
        0,
        (layout['nodes'] as List).reversed.toList(),
      );
      expect(
        () => _parseSnapshot(
          layout,
          excludeActivity: name == 'cross_scope_mount' ? 'activity_form' : null,
        ),
        throwsFormatException,
        reason: '$name with reversed node order',
      );
    }
  });

  test('enforces Python root identity and Unicode title length', () {
    final renamedRoot = jsonDecode(
      workbenchFixtures['layout_tree_v1.json']!,
    ) as Map<String, dynamic>;
    renamedRoot['rootId'] = 'other_root';
    final nodes = renamedRoot['nodes'] as List;
    (nodes.firstWhere((n) => n['id'] == 'wb_root') as Map)['id'] = 'other_root';
    for (final node in nodes) {
      if (node['parentId'] == 'wb_root') node['parentId'] = 'other_root';
    }
    expect(() => _parseSnapshot(renamedRoot), throwsFormatException);

    final unicodeTitle = jsonDecode(
      workbenchFixtures['layout_tree_v1.json']!,
    ) as Map<String, dynamic>;
    final root = (unicodeTitle['nodes'] as List)
        .firstWhere((n) => n['id'] == 'wb_root') as Map;
    root['title'] = '😀' * 80;
    expect(() => _parseSnapshot(unicodeTitle), returnsNormally);
  });

  test('public constructor validates revision and layout', () {
    final validLayout = jsonDecode(workbenchFixtures['layout_tree_v1.json']!)
        as Map<String, dynamic>;
    expect(
      () => WorkbenchSnapshot(
        revision: -1,
        layout: validLayout,
        registrations: const [],
        records: const [],
      ),
      throwsFormatException,
    );
    expect(
      () => WorkbenchSnapshot(
        revision: 1,
        layout: {'invalid': true},
        registrations: const [],
        records: const [],
      ),
      throwsFormatException,
    );
    expect(
      () => WorkbenchSnapshot(
        revision: 1,
        layout: validLayout,
        registrations: [
          WorkbenchRegistration(
            role: WorkbenchRole.content,
            activityMessageId: '',
            surfaceId: 'surface_1',
          ),
        ],
        records: const [],
      ),
      throwsFormatException,
    );
  });

  test('public publication-part constructor validates ordering fields', () {
    expect(
      () => WorkbenchPublicationPart(
        recordId: 'record_1',
        sequence: -1,
        partIndex: 0,
        partCount: 1,
        content: {},
      ),
      throwsFormatException,
    );
  });

  test('surfaces require content mounts and program ancestry match surface ids',
      () {
    final nested = jsonDecode(workbenchFixtures['nested_tree_v1.json']!)
        as Map<String, dynamic>;
    final nodes = nested['nodes'] as List;
    final chart = nodes.firstWhere((node) => node['id'] == 'chart_surface');
    final chartPayload = chart['payload'] as Map<String, dynamic>;
    final activityId = chartPayload['activityMessageId'] as String;
    final registrations = _registrationsFor(nested);
    final chartRegistration = registrations.firstWhere(
      (registration) => registration['activityMessageId'] == activityId,
    );
    chartRegistration['role'] = 'layout';
    expect(
      () => _parseSnapshot(nested, registrations: registrations),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('layout registration cannot mount'),
        ),
      ),
    );

    final programLayout = jsonDecode(
      workbenchFixtures['nested_tree_v1.json']!,
    ) as Map<String, dynamic>;
    final programNodes = programLayout['nodes'] as List;
    final chartNode = programNodes.firstWhere(
      (node) => node['id'] == 'chart_surface',
    );
    final programNode = programNodes.firstWhere(
      (node) => node['id'] == 'program_surface',
    );
    final chartData = chartNode['payload'] as Map<String, dynamic>;
    final programData = programNode['payload'] as Map<String, dynamic>;
    final programSurfaceId = programData['surfaceId'] as String;
    programData['surfaceId'] = 'mounted_program';
    chartData['surfaceId'] = programSurfaceId;
    final explicitRegistrations = _registrationsFor(programLayout)
      ..add({
        'role': 'program',
        'activityMessageId': 'activity_program_registration',
        'surfaceId': programSurfaceId,
      });
    expect(
      () => _parseSnapshot(
        programLayout,
        registrations: explicitRegistrations,
      ),
      throwsFormatException,
    );
  });

  test('non-JSON shared data fails as a format error', () {
    final layout = jsonDecode(workbenchFixtures['layout_tree_v1.json']!)
        as Map<String, dynamic>;
    layout['shared'] = {1: 'non-string key'};
    expect(() => _parseSnapshot(layout), throwsFormatException);

    final unsupported = jsonDecode(workbenchFixtures['layout_tree_v1.json']!)
        as Map<String, dynamic>;
    (unsupported['shared'] as Map<String, dynamic>)['object'] = Object();
    expect(() => _parseSnapshot(unsupported), throwsFormatException);
  });

  test('non-string-key registration and record maps are format errors', () {
    final layout = jsonDecode(workbenchFixtures['layout_tree_v1.json']!)
        as Map<String, dynamic>;
    for (final key in ['registrations', 'records']) {
      expect(
        () => WorkbenchSnapshot.fromJson({
          'revision': 1,
          'layout': layout,
          'registrations': key == 'registrations'
              ? [
                  <Object, Object?>{1: 'x'}
                ]
              : <Object?>[],
          'records': key == 'records'
              ? [
                  <Object, Object?>{1: 'x'}
                ]
              : <Object?>[],
        }),
        throwsFormatException,
        reason: key,
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

  test('rejects publication records with sequence splits or missing parts', () {
    final records = [
      {
        'recordId': 'r1',
        'sequence': 4,
        'partIndex': 0,
        'partCount': 2,
        'content': <String, Object?>{}
      },
      {
        'recordId': 'r1',
        'sequence': 5,
        'partIndex': 1,
        'partCount': 2,
        'content': <String, Object?>{}
      },
    ];
    final layout = jsonDecode(workbenchFixtures['layout_tree_v1.json']!)
        as Map<String, dynamic>;
    expect(
      () => _parseSnapshot(layout, records: records),
      throwsFormatException,
    );
    expect(
      () => _parseSnapshot(layout, records: [records.first]),
      throwsFormatException,
    );
  });

  test('rejects unknown roles and malformed registration metadata', () {
    expect(
      () => WorkbenchRegistration(
        role: WorkbenchRole.content,
        activityMessageId: '',
        surfaceId: 's1',
      ),
      throwsFormatException,
    );
    expect(
      () => WorkbenchRegistration(
        role: WorkbenchRole.content,
        activityMessageId: 'a1',
        surfaceId: 'invalid id',
      ),
      throwsFormatException,
    );
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

  test('public metadata constructors validate ordering invariants', () {
    expect(
      () => WorkbenchPartMetadata(
        sequence: -1,
        publicationId: 'p1',
        partIndex: 0,
        partCount: 1,
      ),
      throwsFormatException,
    );
    expect(
      () => WorkbenchPartMetadata(
        sequence: 1,
        publicationId: 'invalid id',
        partIndex: 0,
        partCount: 1,
      ),
      throwsFormatException,
    );
    expect(
      () => WorkbenchPartMetadata(
        sequence: 1,
        publicationId: 'p1',
        partIndex: 1,
        partCount: 1,
      ),
      throwsFormatException,
    );
    expect(
      () => WorkbenchActivityMetadata(
        registration: WorkbenchRegistration(
          role: WorkbenchRole.content,
          activityMessageId: 'a1',
          surfaceId: 's1',
        ),
        revision: -1,
        part: WorkbenchPartMetadata(
          sequence: 0,
          publicationId: 'p1',
          partIndex: 0,
          partCount: 1,
        ),
      ),
      throwsFormatException,
    );
  });
}

WorkbenchSnapshot _parseSnapshot(
  Map<String, dynamic> layout, {
  String? excludeActivity,
  List<Map<String, Object?>> records = const [],
  List<Map<String, dynamic>>? registrations,
}) {
  final resolvedRegistrations = registrations ??
      [
        for (final node
            in (layout['nodes'] as List).cast<Map<String, dynamic>>())
          if (node['kind'] == 'surface')
            if (node['payload']['activityMessageId'] != excludeActivity)
              {
                'role':
                    node['payload']['activityMessageId'] == 'activity_python'
                        ? 'program'
                        : 'content',
                'activityMessageId': node['payload']['activityMessageId'],
                'surfaceId': node['payload']['surfaceId'],
              },
      ].fold<List<Map<String, dynamic>>>([], (unique, registration) {
        if (!unique.any((existing) =>
            existing['role'] == registration['role'] &&
            existing['activityMessageId'] ==
                registration['activityMessageId'] &&
            existing['surfaceId'] == registration['surfaceId'])) {
          unique.add(registration);
        }
        return unique;
      });
  return WorkbenchSnapshot.fromJson({
    'revision': 1,
    'layout': layout,
    'registrations': resolvedRegistrations,
    'records': records,
  });
}

List<Map<String, dynamic>> _registrationsFor(Map<String, dynamic> layout) => [
      for (final node in (layout['nodes'] as List).cast<Map<String, dynamic>>())
        if (node['kind'] == 'surface')
          {
            'role': node['payload']['activityMessageId'] == 'activity_python'
                ? 'program'
                : 'content',
            'activityMessageId': node['payload']['activityMessageId'],
            'surfaceId': node['payload']['surfaceId'],
          },
    ];

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
      final nested = jsonDecode(workbenchFixtures['nested_tree_v1.json']!)
          as Map<String, dynamic>;
      final nestedNodes = nested['nodes'] as List;
      final leftPanel = nestedNodes.firstWhere((n) => n['id'] == 'left_panel');
      leftPanel['children'] = ['wrong_region'];
      nestedNodes.add({
        'id': 'wrong_region',
        'parentId': 'left_panel',
        'children': <Object?>[],
        'kind': 'region',
        'title': 'Wrong region',
        'size': 'medium',
        'visibility': 'open',
        'payload': {'role': 'other'},
      });
      return nested;
    case 'protected_chat_mutation':
      (nodes.firstWhere((n) => n['id'] == 'r_chat') as Map)['children'] = [
        'chat_panel',
      ];
      nodes.add({
        'id': 'chat_panel',
        'parentId': 'r_chat',
        'children': <Object?>[],
        'kind': 'panel',
        'title': 'Chat panel',
        'size': 'medium',
        'visibility': 'open',
        'payload': <String, Object?>{},
      });
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
