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
/// [NarrationPanel] widget. The LLM writes via the `narrate_say`
/// `ClientTool` declared on `NarrationPlugin`. Python access (the
/// existing `NarrationMontyExtension`) lives in the app shell rather
/// than here so this package stays `dart_monty`-free; Phase 2 of the
/// reactive-bus redesign retires it.
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
