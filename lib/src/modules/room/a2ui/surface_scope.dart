import 'dart:convert';

import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:soliplex_client/soliplex_client.dart';

import '../workbench/layout_reducer.dart';
import '../workbench/layout_tree.dart';
import 'surface_controller.dart';

/// Keeps surface state across timeline virtualization and streamed updates.
class ChatSurfaceStore extends ChangeNotifier {
  ChatSurfaceStore({this.onAction, this.catalogs = const []});

  final void Function(String messageId, Map<String, Object?> action)? onAction;

  /// Catalogs each controller renders in addition to the basic catalog.
  final List<CatalogImplementation> catalogs;
  Future<String> Function(String filename)? readProgramFile;
  Future<void> Function(String filename, String text)? writeProgramFile;
  Map<String, Object?> Function()? programSnapshot;

  final Map<String, ChatSurfaceController> _controllers = {};
  final Map<String, List<String>> _wire = {};
  final Set<String> _invalid = {};
  bool _closed = false;

  // Surface delivery and RUN_FINISHED may share a frame. Remember the turn
  // observed by this in-memory store so its final replacement stays live.
  String? _lastActiveRunId;

  final Map<String, WorkbenchRegistration> _registrations = {};
  final _layoutReducer = LayoutReducer();
  String? _layoutActivityId;
  String? _layoutSurfaceId;
  String? _layoutError;

  /// Last fully validated tree, retained while delivery is incomplete.
  LayoutTree? get layout => _layoutReducer.current;
  String? get layoutError => _layoutError;
  String? get layoutActivityId => _layoutActivityId;
  String? get layoutSurfaceId => _layoutSurfaceId;

  /// Whether this activity has an accepted server workbench registration.
  bool isWorkbenchSurface(String messageId) =>
      _registrations.containsKey(messageId) || messageId == _layoutActivityId;

  /// Ingest every projected activity before either chat or canvas builds.
  /// This is independent of which timeline rows have been virtualized.
  void ingest(Iterable<GenUiMessage> activities, {String? activeRunId}) {
    if (_closed) throw StateError('Surface store is closed');
    final deliveryRunId = activeRunId ?? _lastActiveRunId;
    // Allow the final batch once; later history ingestion has no live turn.
    _lastActiveRunId = activeRunId;
    final candidates = <(WorkbenchRegistration, List<Map<String, Object?>>)>[];
    var changed = false;
    for (final activity in activities) {
      if (activity.widgetName != 'a2ui') continue;
      final raw = activity.data['messages'];
      if (raw is! List) continue;
      final operations = raw
          .map((message) => Map<String, Object?>.from(message as Map))
          .toList();
      // Layout is a control surface; it never needs a rendering controller.
      WorkbenchRegistration? registration;
      final metadata = activity.data['workbenchRegistration'];
      if (metadata is Map<String, dynamic>) {
        try {
          final parsed = WorkbenchRegistration.fromJson(metadata);
          if (parsed.activityMessageId == activity.id &&
              operations.isNotEmpty &&
              operations.every((operation) => operation.entries
                  .where((entry) => entry.key != 'version')
                  .every((entry) =>
                      entry.value is Map &&
                      (entry.value! as Map)['surfaceId'] ==
                          parsed.surfaceId))) {
            registration = parsed;
          }
        } on FormatException {
          // Only the canonical server projection supplies a valid binding.
        }
      }
      if (registration?.role == WorkbenchRole.layout) {
        candidates.add((registration!, operations));
        continue;
      }
      final before = _wire[activity.id];
      final controller = obtain(activity.id, operations,
          live: deliveryRunId != null &&
              (activity.runId == deliveryRunId ||
                  (activity.data['updatedByRunIds'] is List &&
                      (activity.data['updatedByRunIds'] as List)
                          .contains(deliveryRunId))));
      changed |= !identical(before, _wire[activity.id]);
      if (registration != null &&
          controller.error == null &&
          controller.surfaces
              .any((surface) => surface.id == registration!.surfaceId)) {
        _registrations[activity.id] = registration;
      } else {
        _registrations.remove(activity.id);
      }
    }
    for (final (registration, operations) in candidates) {
      try {
        if (_layoutActivityId != null &&
            (_layoutActivityId != registration.activityMessageId ||
                _layoutSurfaceId != registration.surfaceId)) {
          throw const FormatException('Workbench control identity changed');
        }
        final update = operations
            .map((op) => op['updateDataModel'])
            .whereType<Map>()
            .lastWhere((body) => body['path'] == '/');
        final value = update['value'];
        final rawLayout = value is Map ? value['workbench'] : null;
        if (rawLayout is! Map<String, dynamic>) {
          throw const FormatException('Workbench control tree is missing');
        }
        final previous = layout;
        final revision = rawLayout['layoutRevision'];
        if (previous != null &&
            revision is int &&
            revision < (previous.layout['layoutRevision'] as int)) {
          continue;
        }
        if (!_layoutReducer.acceptLayout(
            rawLayout, _registrations.values.toList())) {
          throw const FormatException(
              'Workbench control tree or references are invalid');
        }
        _layoutActivityId = registration.activityMessageId;
        _layoutSurfaceId = registration.surfaceId;
        changed |= _layoutError != null ||
            jsonEncode(previous?.layout) != jsonEncode(layout!.layout);
        _layoutError = null;
      } on Object {
        const error =
            'Workbench update is incomplete or invalid. Waiting for thread activities.';
        changed |= _layoutError != error;
        _layoutError = error;
      }
    }
    if (changed) notifyListeners();
  }

  /// The controller for [messageId] with [messages] applied. [live] marks a
  /// controller created now as arriving from a run in flight.
  ChatSurfaceController obtain(
    String messageId,
    List<Map<String, Object?>> messages, {
    bool live = false,
  }) {
    if (_closed) throw StateError('Surface store is closed');
    final encoded = messages.map(jsonEncode).toList();
    final previous = _wire[messageId] ?? const [];
    final extendsPrevious = encoded.length >= previous.length &&
        List.generate(previous.length, (i) => i)
            .every((i) => encoded[i] == previous[i]);
    final unchanged = encoded.length == previous.length && extendsPrevious;
    if (!extendsPrevious &&
        !_invalid.contains(messageId) &&
        _controllers[messageId]?.updateProgram(messages) == true) {
      _controllers[messageId]!.live = live;
      _wire[messageId] = encoded;
      return _controllers[messageId]!;
    }
    if (!extendsPrevious || (_invalid.contains(messageId) && !unchanged)) {
      _controllers.remove(messageId)?.dispose();
      _wire.remove(messageId);
      _invalid.remove(messageId);
    }
    final controller = _controllers.putIfAbsent(
      messageId,
      () => ChatSurfaceController(
        onActionPayload: (action) => onAction?.call(messageId, action),
        live: live,
        catalogs: catalogs,
      ),
    );
    final offset = _wire[messageId]?.length ?? 0;
    if (offset < messages.length) {
      try {
        controller.apply(messages.sublist(offset));
        _wire[messageId] = encoded;
      } catch (error) {
        controller.error = 'Cannot render surface: $error';
        _wire[messageId] = encoded;
        _invalid.add(messageId);
      }
    }
    return controller;
  }

  ChatSurfaceController? operator [](String messageId) =>
      _controllers[messageId];

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _wire.clear();
    _invalid.clear();
    _registrations.clear();
    super.dispose();
  }
}

/// Supplies conversation-owned surfaces to the shared message timeline.
class ChatSurfaceScope extends InheritedWidget {
  const ChatSurfaceScope({
    super.key,
    required this.store,
    required super.child,
    this.activeRunId,
    this.hostedActivityIds = const {},
    this.hostsWorkbench = false,
  });

  final ChatSurfaceStore store;

  /// Activities mounted by the workbench rather than by timeline tiles.
  final Set<String> hostedActivityIds;
  final bool hostsWorkbench;

  /// The run in flight, whose surfaces count as live.
  final String? activeRunId;

  static ChatSurfaceScope? scopeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatSurfaceScope>();

  static ChatSurfaceStore? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatSurfaceScope>()?.store;

  static String? activeRunIdOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ChatSurfaceScope>()
      ?.activeRunId;

  @override
  bool updateShouldNotify(ChatSurfaceScope oldWidget) =>
      store != oldWidget.store ||
      activeRunId != oldWidget.activeRunId ||
      hostedActivityIds != oldWidget.hostedActivityIds ||
      hostsWorkbench != oldWidget.hostsWorkbench;
}

/// Tells components inside a chat surface whether it arrived live.
///
/// A component that may act without a click, such as one that reruns a
/// repaired program, reads [isLive] and does nothing for a replayed surface.
class ChatSurfaceOrigin extends InheritedWidget {
  const ChatSurfaceOrigin({
    super.key,
    required this.live,
    required super.child,
  });

  final bool live;

  /// False outside a chat surface and for a surface restored from history.
  static bool isLive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatSurfaceOrigin>()?.live ??
      false;

  /// The in-flight model turn around this surface, or null after it settles.
  static String? activeRunIdOf(BuildContext context) =>
      ChatSurfaceScope.activeRunIdOf(context);

  @override
  bool updateShouldNotify(ChatSurfaceOrigin oldWidget) =>
      live != oldWidget.live;
}
