import 'dart:developer' as developer;

import 'package:json_patch/json_patch.dart' as pkg;

/// Applies RFC 6902 JSON Patch operations to a state map.
///
/// Returns a new map with the patches applied. Logs and skips invalid
/// operations rather than failing entirely. Backed by `package:json_patch`
/// (`JsonPatch.apply` with `strict: false`).
///
/// Example:
/// ```dart
/// final state = {'count': 0};
/// final operations = [
///   {'op': 'replace', 'path': '/count', 'value': 1},
///   {'op': 'add', 'path': '/name', 'value': 'test'},
/// ];
/// final result = applyJsonPatch(state, operations);
/// // result == {'count': 1, 'name': 'test'}
/// ```
Map<String, dynamic> applyJsonPatch(
  Map<String, dynamic> state,
  List<dynamic> operations,
) {
  if (operations.isEmpty) return Map<String, dynamic>.from(state);
  final typed = <Map<String, dynamic>>[];
  for (final op in operations) {
    if (op is Map<String, dynamic>) {
      typed.add(op);
    } else if (op is Map) {
      typed.add(Map<String, dynamic>.from(op));
    } else {
      _logPatchError('Operation is not a map', op);
    }
  }
  if (typed.isEmpty) return Map<String, dynamic>.from(state);
  try {
    final result = pkg.JsonPatch.apply(state, typed);
    if (result is Map<String, dynamic>) return result;
    if (result is Map) return Map<String, dynamic>.from(result);
    _logPatchError(
      'Patched root is not a Map (kind=${result.runtimeType})',
      typed,
    );
    return Map<String, dynamic>.from(state);
  } on Object catch (e) {
    _logPatchError('Failed to apply patch: $e', typed);
    return Map<String, dynamic>.from(state);
  }
}

/// Returns the RFC 6902 patch ops that, applied to [before], produce
/// [after]. Backed by `package:json_patch` (`JsonPatch.diff`).
///
/// Each entry is a `Map<String, dynamic>` matching the wire shape AG-UI
/// `StateDeltaEvent` carries (`{op, path, value?}`). Returns an empty
/// list if the two are equal.
///
/// Powers the bus inspector's "what changed" view.
List<Map<String, dynamic>> diffJsonPatch(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) {
  try {
    return pkg.JsonPatch.diff(before, after);
  } on Object catch (e) {
    _logPatchError('Failed to compute diff: $e', null);
    return const [];
  }
}

void _logPatchError(String message, Object? operation) {
  developer.log(
    operation == null ? message : '$message: $operation',
    name: 'JsonPatch',
    level: 900,
  );
}
