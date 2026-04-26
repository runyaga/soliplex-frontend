/// Widget-tree and narration surfaces for `soliplex_agent`.
///
/// Two surfaces in one package, no `dart_monty` dependency:
///
/// **Widget tree** — renders a list of [WidgetSpec]s emitted by the
/// agent (via AG-UI state) through a [WidgetCatalog] of named
/// builders. The default catalog provides built-ins (`InfoCard`,
/// `StatChip`); apps extend it with their own widgets via
/// [WidgetCatalog.extending].
///
/// **Narration** — an app-singleton [NarrationController] plus the
/// [NarrationPanel] widget. Both the LLM tool (`narrate_say`) and the
/// Python host functions (`narrate_say`, `narrate_clear`) are declared
/// on `NarrationPlugin`. The bridge in `soliplex_agent_monty` (Phase 2
/// step 9) synthesizes a `MontyExtension` from the host functions
/// automatically — this package stays `dart_monty`-free.
library;

export 'src/narration.dart';
export 'src/narration_controller.dart';
export 'src/narration_panel.dart';
export 'src/narration_plugin.dart';
export 'src/narration_singleton.dart';
export 'src/widget_catalog.dart';
export 'src/widget_spec.dart';
export 'src/widget_tree_panel.dart';
export 'src/widget_tree_projection.dart';
