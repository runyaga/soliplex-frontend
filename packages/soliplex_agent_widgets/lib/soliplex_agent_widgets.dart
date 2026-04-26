/// Generic widget-tree surface for `soliplex_agent`.
///
/// Renders a list of [WidgetSpec]s emitted by the agent (via AG-UI
/// state) through a [WidgetCatalog] of named builders. The default
/// catalog provides built-ins (`InfoCard`, `StatChip`); apps extend it
/// with their own widgets via [WidgetCatalog.extending].
library;

export 'src/widget_catalog.dart';
export 'src/widget_spec.dart';
export 'src/widget_tree_panel.dart';
export 'src/widget_tree_projection.dart';
