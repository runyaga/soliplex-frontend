import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'surface_controller.dart';
import 'surface_scope.dart';

/// Renders the same surface in a chat tile or an embedded shell.
class ChatSurfaceView extends StatelessWidget {
  const ChatSurfaceView({super.key, required this.controller});

  final ChatSurfaceController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Card(
          child: Padding(
            padding: const EdgeInsets.all(SoliplexSpacing.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (controller.error case final error?) Text(error),
                for (final surface in controller.surfaces)
                  ChatSurfaceOrigin(
                    live: controller.live,
                    child: A2uiSurface(
                      key: ObjectKey(surface),
                      surface: surface,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}
