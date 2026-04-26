import 'package:meta/meta.dart';

/// One element in an agent-emitted widget tree.
///
/// Agents emit widget specs as JSON via AG-UI state events:
///
/// ```json
/// {
///   "ui": {
///     "widgets": [
///       {"id": "w-1", "name": "InfoCard",
///        "data": {"title": "Welcome", "subtitle": "..."}}
///     ]
///   }
/// }
/// ```
///
/// The client's [WidgetTreeProjection] turns each entry into a
/// [WidgetSpec], and a renderer dispatches `name` to a Flutter
/// widget from a developer-supplied catalog.
@immutable
class WidgetSpec {
  /// Construct from name + data + optional stable id (defaults to
  /// the index when absent server-side).
  const WidgetSpec({
    required this.id,
    required this.name,
    this.data = const <String, dynamic>{},
  });

  /// Stable identity. Used as the widget key so the tree
  /// reconciles correctly across re-renders.
  final String id;

  /// Catalog key. Resolves to a builder in the catalog.
  final String name;

  /// Free-form payload. The catalog builder decides what's
  /// required.
  final Map<String, dynamic> data;
}
