import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:soliplex_client/src/domain/workbench_snapshot.dart';

/// Validates a layout snapshot using the frozen workbench tree contract.
void validateWorkbenchLayout(
  Map<String, dynamic> layout,
  List<WorkbenchRegistration> registrations,
) {
  _validateEnvelope(layout);
  final nodes = _parseNodes(layout['nodes'] as List<Object?>);
  final rootId = layout['rootId'] as String;
  _validateRoot(rootId, nodes);
  _validateNodeContent(nodes, registrations);
  _validateEdges(nodes);
  _validateReachability(rootId, nodes);
  _validateReserved(rootId, nodes);
  _validateAncestry(nodes, registrations);
  _validateCapacities(layout, nodes, registrations);
}

void _validateEnvelope(Map<String, dynamic> layout) {
  _need(
    !_hasKeys(layout, {
          'schemaVersion',
          'layoutRevision',
          'rootId',
          'nodes',
          'shared',
        }) ||
        layout['schemaVersion'] is! int ||
        layout['schemaVersion'] != 1 ||
        layout['layoutRevision'] is! int ||
        (layout['layoutRevision'] as int) < 0 ||
        !_id(layout['rootId']) ||
        layout['nodes'] is! List ||
        (layout['nodes'] as List).length < 6 ||
        (layout['nodes'] as List).length > 64 ||
        layout['shared'] is! Map<String, dynamic>,
    'malformed layout',
  );
}

Map<String, Map<String, dynamic>> _parseNodes(List<Object?> rawNodes) {
  final nodes = <String, Map<String, dynamic>>{};
  for (final raw in rawNodes) {
    _validateNodeShape(raw);
    final node = raw! as Map<String, dynamic>;
    final id = node['id'] as String;
    _need(nodes.containsKey(id), 'duplicate node id');
    nodes[id] = node;
  }
  return nodes;
}

void _validateNodeShape(Object? raw) {
  _need(
    raw is! Map<String, dynamic> ||
        !_hasKeys(raw, {
          'id',
          'parentId',
          'children',
          'kind',
          'title',
          'size',
          'visibility',
          'payload',
        }) ||
        !_id(raw['id']) ||
        (raw['parentId'] != null && !_id(raw['parentId'])) ||
        raw['children'] is! List ||
        !(raw['children'] as List).every(_id) ||
        !_kinds.contains(raw['kind']) ||
        !_text(raw['title'], 80) ||
        !_sizes.contains(raw['size']) ||
        !_visibility.contains(raw['visibility']) ||
        raw['payload'] is! Map<String, dynamic>,
    'malformed layout node',
  );
}

void _validateRoot(String rootId, Map<String, Map<String, dynamic>> nodes) {
  _need(rootId != 'wb_root', 'reserved region contract mismatch');
  final root = nodes[rootId];
  _need(
    root == null || root['kind'] != 'workspace' || root['parentId'] != null,
    'invalid workspace root',
  );
  const reserved = ['r_chat', 'r_left', 'r_right', 'r_canvas', 'r_tray'];
  _need(
    !const ListEquality<String>().equals(
      (root!['children'] as List).cast<String>(),
      reserved,
    ),
    'reserved region order mismatch',
  );
}

void _validateNodeContent(
  Map<String, Map<String, dynamic>> nodes,
  List<WorkbenchRegistration> registrations,
) {
  final mounts = <String>{};
  final surfaceIds = <String>{};
  final registered = <String, WorkbenchRole>{};
  for (final entry in registrations) {
    _need(
      !_id(entry.activityMessageId) || !_id(entry.surfaceId),
      'invalid workbench registration identity',
    );
    final mount = '${entry.activityMessageId}\u0000${entry.surfaceId}';
    _need(registered.containsKey(mount), 'duplicate workbench registration');
    registered[mount] = entry.role;
  }
  for (final node in nodes.values) {
    final children = node['children'] as List;
    _need(children.toSet().length != children.length, 'duplicate child');
    final kind = node['kind'] as String;
    final payload = node['payload'] as Map<String, dynamic>;
    _validatePayload(kind, payload, mounts, surfaceIds, registered);
    _validateChildCapacity(kind, children.length);
  }
}

void _validatePayload(
  String kind,
  Map<String, dynamic> payload,
  Set<String> mounts,
  Set<String> surfaceIds,
  Map<String, WorkbenchRole> registered,
) {
  if (kind == 'region') {
    _need(!_hasKeys(payload, {'role'}), 'invalid region payload');
  } else if (kind == 'split') {
    _need(
      !_hasKeys(payload, {'axis'}) ||
          !{'horizontal', 'vertical'}.contains(payload['axis']),
      'invalid split payload',
    );
  } else if (kind == 'surface') {
    _validateSurface(payload, mounts, surfaceIds, registered);
  } else {
    _need(payload.isNotEmpty, 'unexpected payload');
  }
}

void _validateSurface(
  Map<String, dynamic> payload,
  Set<String> mounts,
  Set<String> surfaceIds,
  Map<String, WorkbenchRole> registered,
) {
  _need(
    !_hasKeys(payload, {'activityMessageId', 'surfaceId'}) ||
        !_id(payload['activityMessageId']) ||
        !_id(payload['surfaceId']),
    'invalid surface payload',
  );
  final mount = '${payload['activityMessageId']}\u0000${payload['surfaceId']}';
  final role = registered[mount];
  _need(role == null, 'unregistered mount');
  _need(role == WorkbenchRole.layout, 'layout registration cannot mount');
  _need(mounts.contains(mount), 'duplicate mount');
  _need(
    surfaceIds.contains(payload['surfaceId'] as String),
    'duplicate surface id',
  );
  mounts.add(mount);
  surfaceIds.add(payload['surfaceId'] as String);
}

void _validateChildCapacity(String kind, int count) {
  _need(
    kind == 'split' && count > 3 ||
        kind == 'tabs' && count > 12 ||
        {'panel', 'window'}.contains(kind) && count > 1,
    'child capacity exceeded',
  );
}

void _validateEdges(Map<String, Map<String, dynamic>> nodes) {
  for (final node in nodes.values) {
    final kind = node['kind'] as String;
    for (final childId in (node['children'] as List).cast<String>()) {
      final child = nodes[childId];
      _need(
        child == null || child['parentId'] != node['id'],
        'inconsistent child edge',
      );
      _need(!_allowsChild(kind, child!['kind'] as String), 'wrong parent kind');
    }
  }
}

void _validateReachability(
  String rootId,
  Map<String, Map<String, dynamic>> nodes,
) {
  final complete = <String>{};
  final visiting = <String>{};
  final parents = <String, int>{};
  for (final node in nodes.values) {
    for (final child in (node['children'] as List).cast<String>()) {
      parents.update(child, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  _need(parents.values.any((count) => count > 1), 'multiple parents');
  final reachableFromRoot = <String>{};
  void visit(String id, int depth, {required bool fromRoot}) {
    _need(depth > 8, 'maximum depth exceeded');
    if (fromRoot) reachableFromRoot.add(id);
    _need(visiting.contains(id), 'cycle');
    if (complete.contains(id)) return;
    visiting.add(id);
    for (final child in (nodes[id]!['children'] as List).cast<String>()) {
      visit(child, depth + 1, fromRoot: fromRoot);
    }
    visiting.remove(id);
    complete.add(id);
  }

  visit(rootId, 1, fromRoot: true);
  for (final id in nodes.keys) {
    if (!complete.contains(id)) {
      visit(id, 1, fromRoot: false);
    }
  }
  _need(reachableFromRoot.length != nodes.length, 'orphan node');
}

void _validateReserved(
  String rootId,
  Map<String, Map<String, dynamic>> nodes,
) {
  const roles = {
    'r_chat': 'chat',
    'r_left': 'left',
    'r_right': 'right',
    'r_canvas': 'canvas',
    'r_tray': 'tray',
  };
  for (final entry in roles.entries) {
    final node = nodes[entry.key];
    _need(
      node == null ||
          node['kind'] != 'region' ||
          node['parentId'] != 'wb_root' ||
          (node['payload'] as Map)['role'] != entry.value,
      'reserved region contract mismatch',
    );
    _need(node!['visibility'] != 'open', 'reserved nodes must remain open');
  }
  _need(
    nodes['wb_root']!['visibility'] != 'open',
    'reserved nodes must remain open',
  );
  _need(
    (nodes['r_chat']!['children'] as List).isNotEmpty,
    'chat cannot have children',
  );
}

void _validateAncestry(
  Map<String, Map<String, dynamic>> nodes,
  List<WorkbenchRegistration> registrations,
) {
  for (final node in nodes.values.where((n) => n['kind'] == 'window')) {
    _validateWindowAncestors(node, nodes);
  }
  final programs = {
    for (final entry in registrations)
      if (entry.role == WorkbenchRole.program) entry.surfaceId,
  };
  for (final node in nodes.values.where((n) => n['kind'] == 'surface')) {
    final payload = node['payload'] as Map;
    if (programs.contains(payload['surfaceId'])) {
      _requireWindowAncestor(node, nodes);
    }
  }
}

void _validateWindowAncestors(
  Map<String, dynamic> node,
  Map<String, Map<String, dynamic>> nodes,
) {
  var parentId = node['parentId'] as String?;
  var canvasAncestor = false;
  while (parentId != null) {
    final parent = nodes[parentId]!;
    if (parentId == 'r_canvas') canvasAncestor = true;
    _need(parent['kind'] == 'window', 'nested windows are forbidden');
    parentId = parent['parentId'] as String?;
  }
  _need(!canvasAncestor, 'windows require canvas ancestry');
}

void _requireWindowAncestor(
  Map<String, dynamic> node,
  Map<String, Map<String, dynamic>> nodes,
) {
  var parentId = node['parentId'] as String?;
  var found = false;
  while (parentId != null) {
    final parent = nodes[parentId]!;
    found |= parent['kind'] == 'window';
    parentId = parent['parentId'] as String?;
  }
  _need(!found, 'program surface requires window ancestry');
}

void _validateCapacities(
  Map<String, dynamic> layout,
  Map<String, Map<String, dynamic>> nodes,
  List<WorkbenchRegistration> registrations,
) {
  final openSurfaces = nodes.values.where(
    (node) => node['kind'] == 'surface' && _effectivelyOpen(node, nodes),
  );
  _need(openSurfaces.length > 12, 'open content mount capacity exceeded');
  final openWindows = nodes.values.where(
    (node) => node['kind'] == 'window' && _effectivelyOpen(node, nodes),
  );
  final apps = (layout['shared'] as Map)['programApps'] ?? <String, dynamic>{};
  _need(apps is! Map<String, dynamic>, 'invalid program app bindings');
  final bindings = apps as Map<String, dynamic>;
  final programs = {
    for (final entry in registrations)
      if (entry.role == WorkbenchRole.program) entry.surfaceId,
  };
  _need(
    bindings.values.toSet().length != bindings.length,
    'duplicate program app binding',
  );
  for (final entry in bindings.entries) {
    final app = nodes[entry.key];
    _need(
      !programs.contains(entry.value) ||
          app == null ||
          app['kind'] != 'window' ||
          app['parentId'] != 'r_canvas' ||
          (app['children'] as List).isNotEmpty,
      'invalid program app binding',
    );
  }
  _need(
    openWindows.length > 3 ||
        openWindows.where((n) => !bindings.containsKey(n['id'])).length > 2,
    'expanded window capacity exceeded',
  );
  _need(_utf8Length(layout) > 65536, 'layout exceeds 64 KiB');
}

bool _effectivelyOpen(
  Map<String, dynamic> node,
  Map<String, Map<String, dynamic>> nodes,
) {
  Map<String, dynamic>? current = node;
  while (current != null) {
    if (current['visibility'] != 'open') return false;
    final parentId = current['parentId'] as String?;
    current = parentId == null ? null : nodes[parentId];
  }
  return true;
}

const _kinds = {
  'workspace',
  'region',
  'split',
  'tabs',
  'panel',
  'window',
  'surface',
};
const _sizes = {'small', 'medium', 'large'};
const _visibility = {'open', 'minimized', 'closed'};

bool _allowsChild(String parent, String child) => switch (parent) {
      'workspace' => child == 'region',
      'region' => {'split', 'tabs', 'panel', 'window'}.contains(child),
      'split' || 'tabs' => {'split', 'tabs', 'panel', 'window'}.contains(child),
      'panel' || 'window' => {'split', 'tabs', 'surface'}.contains(child),
      _ => false,
    };

bool _id(Object? value) =>
    value is String && RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$').hasMatch(value);
bool _text(Object? value, int max) =>
    value is String && value.isNotEmpty && value.runes.length <= max;
bool _hasKeys(Map<dynamic, dynamic> value, Set<String> keys) =>
    value.length == keys.length && value.keys.every(keys.contains);
int _utf8Length(Object? value) => utf8.encode(_encodeJson(value)).length;

String _encodeJson(Object? value) {
  try {
    return jsonEncode(value);
  } on Object {
    throw const FormatException('Value is not JSON encodable');
  }
}

void _need(bool invalid, String reason) {
  if (invalid) throw FormatException(reason);
}
