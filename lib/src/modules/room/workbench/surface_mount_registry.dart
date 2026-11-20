import 'package:flutter/widgets.dart';

/// Owns one keyed mount per registered content surface for the host lifetime.
class SurfaceMountRegistry {
  final Map<String, GlobalKey> _keys = {};

  /// Returns the stable key for a registered surface identity.
  GlobalKey keyFor(String activityMessageId, String surfaceId) =>
      _keys.putIfAbsent('$activityMessageId\u0000$surfaceId', GlobalKey.new);

  /// Drops keys for identities no longer present in the accepted tree.
  void retain(Iterable<String> identities) {
    final keep = identities.toSet();
    _keys.removeWhere((key, _) => !keep.contains(key));
  }

  /// Current mounted identity count.
  int get length => _keys.length;
}
