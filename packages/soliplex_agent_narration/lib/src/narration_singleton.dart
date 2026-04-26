/// App-level singleton for the narration log. Both the Python
/// `narrate_say(...)` external and the in-room narration panel
/// reference this instance, so messages from any session — or from
/// any non-session direct caller — appear in the same UI.
library;

import 'narration_controller.dart';

final NarrationController narrationController = NarrationController();
