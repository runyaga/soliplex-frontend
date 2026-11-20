import 'package:flutter/widgets.dart';

/// Room-owned presentation hook supplied by an opt-in flavor.
abstract interface class WorkbenchPresentation {
  /// Builds the workbench host for a thread, keeping layout interpretation in
  /// the room feature and composition in the flavor.
  Widget buildHost({
    required String roomId,
    required String threadId,
    required Widget chat,
    required Widget Function(String activityMessageId, String surfaceId)
        surfaceBuilder,
  });
}
