/// Test host for lab surfaces: the basic and lab catalogs in one processor.
library;

import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/basic_catalog.dart';
import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_monty/soliplex_monty.dart';

/// Owns surfaces rendered with the basic and lab catalogs.
class LabSurfaceController extends ChangeNotifier {
  LabSurfaceController({
    this.onActionPayload,
    ReplRuntimeStarter? startRuntime,
    ReplLimits limits = const ReplLimits(),
    bool live = false,
    RepairChains? chains,
  }) {
    processor = MessageProcessor<ComponentImplementation>(
      catalogs: [
        basicCatalog(),
        labCatalog(
          startRuntime: startRuntime,
          limits: limits,
          isLive: (_) => live,
          chains: chains,
        ),
      ],
      validationConfig: ValidationConfig.strict,
    );
    processor.model.onSurfaceCreated.subscribe((_) {
      if (!_closed) notifyListeners();
    });
    processor.model.onSurfaceDeleted.subscribe((_) {
      if (!_closed) notifyListeners();
    });
    processor.model.onAction.subscribe((action) {
      if (!_closed) onActionPayload?.call(action.toJson());
    });
    processor.model.onError.subscribe((error) {
      if (_closed) return;
      this.error = error.toString();
      notifyListeners();
    });
  }

  final void Function(Map<String, Object?> action)? onActionPayload;
  late final MessageProcessor<ComponentImplementation> processor;
  String? error;
  bool _closed = false;

  Iterable<SurfaceModel<ComponentImplementation>> get surfaces =>
      processor.model.allSurfaces;

  /// Applies wire messages. Nothing in them starts Python.
  void apply(List<Map<String, Object?>> messages) {
    if (_closed) throw StateError('Lab surface controller is closed');
    final owned = (jsonDecode(jsonEncode(messages)) as List).map(
      (message) => Map<String, Object?>.from(message as Map),
    );
    for (final message in owned) {
      processor.processMessages([message]);
    }
    notifyListeners();
  }

  /// The data model of every surface, keyed by surface id.
  Map<String, Object?> dataModels() => {
    for (final surface in surfaces) surface.id: surface.dataModel.get('/'),
  };

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    processor.dispose();
    super.dispose();
  }
}

/// Renders lab surfaces in a card.
class LabSurfaceView extends StatelessWidget {
  const LabSurfaceView({required this.controller, super.key});

  final LabSurfaceController controller;

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
              A2uiSurface(key: ObjectKey(surface), surface: surface),
          ],
        ),
      ),
    ),
  );
}
