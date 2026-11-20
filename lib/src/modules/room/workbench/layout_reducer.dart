import 'package:soliplex_client/soliplex_client.dart' show WorkbenchSnapshot;

import 'layout_tree.dart';

/// Holds the last valid complete server snapshot; partial deliveries are inert.
class LayoutReducer {
  LayoutTree? _current;

  /// Last accepted complete tree.
  LayoutTree? get current => _current;

  /// Atomically validates and accepts [snapshot]. Invalid candidates retain state.
  bool acceptSnapshot(WorkbenchSnapshot? snapshot) {
    if (snapshot == null) return false;
    try {
      _current = LayoutTree.fromSnapshot(snapshot);
      return true;
    } on FormatException {
      return false;
    }
  }
}
