import 'package:soliplex_client/soliplex_client.dart'
    show WorkbenchRegistration;

import 'layout_tree.dart';

/// Holds the last validated control tree; incomplete deliveries are inert.
class LayoutReducer {
  LayoutTree? _current;

  /// Last accepted complete tree.
  LayoutTree? get current => _current;

  /// Accepts a control activity tree against server-issued content bindings.
  bool acceptLayout(
      Map<String, dynamic>? layout, List<WorkbenchRegistration> registrations) {
    if (layout == null) return false;
    try {
      _current = LayoutTree.fromLayout(layout, registrations);
      return true;
    } on FormatException {
      return false;
    }
  }
}
