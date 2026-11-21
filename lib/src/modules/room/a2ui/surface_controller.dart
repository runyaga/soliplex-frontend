import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/basic_catalog.dart';
import 'package:flutter/widgets.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';

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
  }) : _catalogs = catalogs {
    processor = MessageProcessor<ComponentImplementation>(
      catalogs: [
        _basicCatalog(),
        if (!catalogs.any((catalog) => catalog.id == chartGraphicsCatalogId))
          chartGraphicsCatalog(),
        ...catalogs,
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

  final List<CatalogImplementation> _catalogs;
  final void Function(String name)? onAction;
  final void Function(Map<String, Object?> action)? onActionPayload;

  /// Whether the current publication arrived from a run in flight rather
  /// than history. A program replacement updates this delivery origin.
  bool live;
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

  /// Reconciles a complete publication of the same Python editor in place.
  /// A different surface, catalog or component remains a fresh publication.
  bool updateProgram(List<Map<String, Object?>> messages) {
    Map<String, Object?>? identity(List<Map<String, Object?>> wire) {
      if (wire.length != 3 ||
          wire[0]['createSurface'] is! Map ||
          wire[1]['updateDataModel'] is! Map ||
          wire[2]['updateComponents'] is! Map) {
        return null;
      }
      final create = wire[0]['createSurface']! as Map;
      final data = wire[1]['updateDataModel']! as Map;
      final update = wire[2]['updateComponents']! as Map;
      final components = update['components'];
      if (data['surfaceId'] != create['surfaceId'] ||
          update['surfaceId'] != create['surfaceId'] ||
          data['path'] != '/' ||
          components is! List ||
          components.length != 1 ||
          components.single is! Map) {
        return null;
      }
      final component = Map<String, Object?>.from(components.single as Map);
      if (component['id'] != 'root' || component['component'] != 'PythonRepl') {
        return null;
      }
      // Attempt metadata may change while the editor identity stays stable.
      component.remove('retry');
      return {'create': wire[0], 'component': component};
    }

    final before = identity(_messages);
    final after = identity(messages);
    if (_closed ||
        error != null ||
        before == null ||
        after == null ||
        jsonEncode(before) != jsonEncode(after)) {
      return false;
    }
    // Validate the entire replacement before changing any live bindings.
    final candidate = ChatSurfaceController(catalogs: _catalogs);
    try {
      candidate.apply(messages);
      if (candidate.error != null) return false;
    } on Object {
      return false;
    } finally {
      candidate.dispose();
    }
    _messages.clear();
    // Reuse the existing SurfaceModel and component instance: createSurface
    // would replace their widget State and dispose the retained interpreter.
    apply(messages.skip(1).toList());
    _messages.insert(
        0, jsonDecode(jsonEncode(messages.first)) as Map<String, Object?>);
    return true;
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
      if ({'TextField', 'ChoicePicker', 'CheckBox', 'DateTimeInput'}
          .contains(component.name))
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
