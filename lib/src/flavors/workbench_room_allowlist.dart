import 'package:flutter/widgets.dart';

import '../interfaces/workbench_presentation.dart';

/// Selects the workbench host only for the configured room IDs.
class WorkbenchRoomAllowlistPresentation implements WorkbenchPresentation {
  const WorkbenchRoomAllowlistPresentation({
    required this.rooms,
    required this.host,
  });

  final Set<String> rooms;
  final WorkbenchPresentation host;

  @override
  Widget buildHost({
    required String roomId,
    required String threadId,
    required Widget chat,
    required Widget Function(String activityMessageId, String surfaceId)
        surfaceBuilder,
  }) {
    if (!rooms.contains(roomId)) return chat;
    return host.buildHost(
      roomId: roomId,
      threadId: threadId,
      chat: chat,
      surfaceBuilder: surfaceBuilder,
    );
  }
}
