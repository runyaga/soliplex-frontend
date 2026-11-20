import 'package:soliplex_client/soliplex_client.dart'
    show WorkbenchRegistration, WorkbenchSnapshot;

/// Immutable indexed view of the accepted server-authored layout tree.
class LayoutTree {
  LayoutTree._(this.layout, this.nodes);

  /// Builds an indexed tree from a validated snapshot from the workbench API.
  factory LayoutTree.fromSnapshot(WorkbenchSnapshot snapshot) =>
      LayoutTree.fromLayout(snapshot.layout, snapshot.registrations);

  /// Builds and validates a tree candidate.
  factory LayoutTree.fromLayout(
    Map<String, dynamic> layout, [
    List<WorkbenchRegistration> registrations = const [],
  ]) {
    final validated = WorkbenchSnapshot(
      revision: layout['layoutRevision'] is int
          ? layout['layoutRevision'] as int
          : -1,
      layout: layout,
      registrations: registrations,
      records: const [],
    );
    final nodes = <String, LayoutNode>{};
    for (final value in layout['nodes']! as List) {
      final raw = Map<String, dynamic>.from(value as Map);
      final node = LayoutNode.fromJson(raw);
      nodes[node.id] = node;
    }
    return LayoutTree._(validated.layout, Map.unmodifiable(nodes));
  }

  /// Original accepted, closed layout document.
  final Map<String, dynamic> layout;

  /// Stable ID index of all nodes, including closed nodes.
  final Map<String, LayoutNode> nodes;

  /// The node with [id], if present.
  LayoutNode? node(String id) => nodes[id];

  /// Reserved root node.
  LayoutNode get root => nodes[layout['rootId'] as String]!;
}

/// A typed projection of one layout node.
class LayoutNode {
  /// Creates a node projection.
  const LayoutNode({
    required this.id,
    required this.parentId,
    required this.children,
    required this.kind,
    required this.title,
    required this.size,
    required this.visibility,
    required this.payload,
  });

  /// Parses a node already checked by the shared client validator.
  factory LayoutNode.fromJson(Map<String, dynamic> json) => LayoutNode(
        id: json['id']! as String,
        parentId: json['parentId'] as String?,
        children: List.unmodifiable((json['children']! as List).cast<String>()),
        kind: json['kind']! as String,
        title: json['title']! as String,
        size: json['size']! as String,
        visibility: json['visibility']! as String,
        payload: Map.unmodifiable(json['payload']! as Map<String, dynamic>),
      );

  final String id;
  final String? parentId;
  final List<String> children;
  final String kind;
  final String title;
  final String size;
  final String visibility;
  final Map<String, dynamic> payload;
}
