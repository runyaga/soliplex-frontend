import 'package:signals_core/signals_core.dart';

/// Mutable runtime ACL for client tool visibility.
///
/// Tracks which tool names are denied (hidden from the LLM). Changes take
/// effect immediately — the next `tools` read on a
/// `ToolFilteredEnvironment.acl` wrapper reflects the current denied set.
///
/// Mutate via [deny]/[allow] or from Python via the registered host functions
/// `acl_list`, `acl_deny`, `acl_allow`, and `acl_reset`.
class ToolAcl {
  /// Creates a [ToolAcl] with an optional initial denied set.
  ToolAcl({Set<String> denied = const {}})
      : _denied = signal(Set.unmodifiable(denied));

  final Signal<Set<String>> _denied;

  /// Reactive read-only view of the current denied set.
  ReadonlySignal<Set<String>> get denied => _denied;

  /// Returns `true` if [toolName] is NOT denied.
  bool isAllowed(String toolName) => !_denied.value.contains(toolName);

  /// Adds [toolName] to the denied set.
  void deny(String toolName) {
    if (!_denied.value.contains(toolName)) {
      _denied.value = {..._denied.value, toolName};
    }
  }

  /// Removes [toolName] from the denied set (allows it).
  void allow(String toolName) {
    if (_denied.value.contains(toolName)) {
      _denied.value = _denied.value.difference({toolName});
    }
  }

  /// Clears all denials — all tools become visible.
  void reset() => _denied.value = {};

  /// Sorted list of currently denied tool names.
  List<String> list() => [..._denied.value]..sort();

  @override
  String toString() {
    final items = list();
    if (items.isEmpty) return 'ToolAcl(none denied)';
    return 'ToolAcl(denied: ${items.join(', ')})';
  }
}
