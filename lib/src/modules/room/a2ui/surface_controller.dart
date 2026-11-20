import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/basic_catalog.dart';
import 'package:flutter/widgets.dart';

/// Owns validated A2UI surfaces independently of chat navigation.
///
/// Renders the basic catalog plus every catalog in [catalogs]. A payload names
/// components only: nothing in a wire message runs code.
class ChatSurfaceController extends ChangeNotifier {
  ChatSurfaceController({
    this.onAction,
    this.onActionPayload,
    this.live = false,
    List<CatalogImplementation> catalogs = const [],
  }) {
    processor = MessageProcessor<ComponentImplementation>(
      catalogs: [_basicCatalog(), ...catalogs],
      validationConfig: ValidationConfig.strict,
    );
    processor.model.onSurfaceCreated.subscribe((_) {
      if (!_closed) notifyListeners();
    });
    processor.model.onSurfaceDeleted.subscribe((_) {
      if (!_closed) notifyListeners();
    });
    processor.model.onAction.subscribe((action) {
      if (_closed) return;
      onAction?.call(action.name);
      onActionPayload?.call(action.toJson());
    });
    processor.model.onError.subscribe((error) {
      if (_closed) return;
      this.error = 'Cannot render surface: ${error.code}: ${error.message}';
      notifyListeners();
    });
  }

  final void Function(String name)? onAction;
  final void Function(Map<String, Object?> action)? onActionPayload;

  /// Whether the surface first arrived from a run in flight rather than from
  /// history. Set once, when the controller is created.
  final bool live;
  late final MessageProcessor<ComponentImplementation> processor;
  final List<Map<String, Object?>> _messages = [];
  String? error;
  bool _closed = false;

  Iterable<SurfaceModel<ComponentImplementation>> get surfaces =>
      processor.model.allSurfaces;

  /// Applies wire messages without executing code from the payload.
  void apply(List<Map<String, Object?>> messages) {
    if (_closed) throw StateError('Surface controller is closed');
    final owned = (jsonDecode(jsonEncode(messages)) as List)
        .map((message) => Map<String, Object?>.from(message as Map));
    for (final message in owned) {
      processor.processMessages([message]);
      _messages.add(message);
    }
    notifyListeners();
  }

  /// Serializes wire messages and current local bindings for surface replay.
  Map<String, Object?> snapshot() {
    if (_closed) throw StateError('Surface controller is closed');
    return {
      'messages': jsonDecode(
        jsonEncode([
          ..._messages,
          for (final surface in surfaces)
            {
              'version': surface.protocolVersion ?? '1.0',
              'updateDataModel': {
                'surfaceId': surface.id,
                'path': '/',
                'value': surface.dataModel.get('/'),
              },
            },
        ]),
      ),
    };
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    processor.dispose();
    super.dispose();
  }
}

// A field needs its own semantics boundary so nearby static labels do not
// merge into its accessible name. Keep the catalog's binding and validation.
CatalogImplementation _basicCatalog() {
  final basic = basicCatalog();
  return basic.copyWith(components: [
    for (final component in basic.components.values)
      if (component.name == 'TextField')
        ComponentImplementation(
          name: component.name,
          schema: component.schema,
          allowedParents: component.allowedParents,
          allowedChildren: component.allowedChildren,
          builder: (context, node, props, buildChild) => Semantics(
            container: true,
            child: component.builder(context, node, props, buildChild),
          ),
        )
      else
        component,
  ]);
}
