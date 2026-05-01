import 'package:flutter/foundation.dart';

/// One categorised change between two state snapshots.
@immutable
sealed class SnapshotChange {
  const SnapshotChange(this.path);

  /// Slash-joined JSON path, e.g. `/ui/narrations/0/text`.
  final String path;
}

class AddedChange extends SnapshotChange {
  const AddedChange(super.path, this.value);
  final dynamic value;
}

class RemovedChange extends SnapshotChange {
  const RemovedChange(super.path, this.value);
  final dynamic value;
}

class ReplacedChange extends SnapshotChange {
  const ReplacedChange(super.path, this.before, this.after);
  final dynamic before;
  final dynamic after;
}

/// Result of diffing two `Map<String, dynamic>` snapshots, broken out
/// into added / removed / replaced for UI rendering.
@immutable
class SnapshotDiff {
  const SnapshotDiff({
    required this.added,
    required this.removed,
    required this.replaced,
  });

  const SnapshotDiff.empty()
      : added = const [],
        removed = const [],
        replaced = const [];

  final List<AddedChange> added;
  final List<RemovedChange> removed;
  final List<ReplacedChange> replaced;

  bool get isEmpty => added.isEmpty && removed.isEmpty && replaced.isEmpty;

  int get totalChanges => added.length + removed.length + replaced.length;

  /// Compact summary like `+2 / -1 / ~3` for tile rendering. Empty
  /// segments are dropped (so `+1` / `~2` etc.).
  String get summary {
    final parts = <String>[
      if (added.isNotEmpty) '+${added.length}',
      if (removed.isNotEmpty) '-${removed.length}',
      if (replaced.isNotEmpty) '~${replaced.length}',
    ];
    return parts.isEmpty ? 'no change' : parts.join(' / ');
  }
}

/// Compute the structural diff between two snapshots.
///
/// Pass `null` for [prior] to treat the comparison as "everything in
/// [current] is new" — produces an `AddedChange` per top-level key.
/// Recurses into nested maps; lists are compared by index. Leaf values
/// are compared with `==`. Type mismatches at a path are recorded as a
/// single replacement (no further recursion into the mismatched value).
SnapshotDiff diffSnapshots(
  Map<String, dynamic>? prior,
  Map<String, dynamic> current,
) {
  final added = <AddedChange>[];
  final removed = <RemovedChange>[];
  final replaced = <ReplacedChange>[];
  _diffMap(prior ?? const {}, current, '', added, removed, replaced);
  return SnapshotDiff(
    added: List.unmodifiable(added),
    removed: List.unmodifiable(removed),
    replaced: List.unmodifiable(replaced),
  );
}

void _diffMap(
  Map<dynamic, dynamic> a,
  Map<dynamic, dynamic> b,
  String basePath,
  List<AddedChange> added,
  List<RemovedChange> removed,
  List<ReplacedChange> replaced,
) {
  for (final key in {...a.keys, ...b.keys}) {
    final path = '$basePath/$key';
    final inA = a.containsKey(key);
    final inB = b.containsKey(key);
    if (!inA) {
      added.add(AddedChange(path, b[key]));
    } else if (!inB) {
      removed.add(RemovedChange(path, a[key]));
    } else {
      _diffValue(a[key], b[key], path, added, removed, replaced);
    }
  }
}

void _diffValue(
  dynamic before,
  dynamic after,
  String path,
  List<AddedChange> added,
  List<RemovedChange> removed,
  List<ReplacedChange> replaced,
) {
  if (before is Map && after is Map) {
    _diffMap(before, after, path, added, removed, replaced);
    return;
  }
  if (before is List && after is List) {
    final maxLen = before.length > after.length ? before.length : after.length;
    for (var i = 0; i < maxLen; i++) {
      final childPath = '$path/$i';
      if (i >= before.length) {
        added.add(AddedChange(childPath, after[i]));
      } else if (i >= after.length) {
        removed.add(RemovedChange(childPath, before[i]));
      } else {
        _diffValue(before[i], after[i], childPath, added, removed, replaced);
      }
    }
    return;
  }
  if (before != after) {
    replaced.add(ReplacedChange(path, before, after));
  }
}
