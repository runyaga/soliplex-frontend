/// Narration log surface for `soliplex_agent`.
///
/// Owns an app-singleton [NarrationController] that the in-room
/// [NarrationPanel] watches reactively. Both the LLM (via the
/// `narrate_say` `ClientTool`) and Python (via `narrate_say(...)` from
/// `narration_monty_extension.dart`) write through the same instance,
/// so messages from either source render in the same UI.
library;

export 'src/narration.dart';
export 'src/narration_controller.dart';
export 'src/narration_monty_extension.dart';
export 'src/narration_panel.dart';
export 'src/narration_singleton.dart';
