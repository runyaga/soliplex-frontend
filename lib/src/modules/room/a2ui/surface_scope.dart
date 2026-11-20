import 'dart:convert';

import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/widgets.dart';

import 'surface_controller.dart';

/// Keeps surface state across timeline virtualization and streamed updates.
class ChatSurfaceStore {
  ChatSurfaceStore({this.onAction, this.catalogs = const []});

  final void Function(String messageId, Map<String, Object?> action)? onAction;

  /// Catalogs each controller renders in addition to the basic catalog.
  final List<CatalogImplementation> catalogs;
  final Map<String, ChatSurfaceController> _controllers = {};
  final Map<String, List<String>> _wire = {};
  final Set<String> _invalid = {};
  bool _closed = false;

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

  void dispose() {
    if (_closed) return;
    _closed = true;
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _wire.clear();
    _invalid.clear();
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

  @override
  bool updateShouldNotify(ChatSurfaceOrigin oldWidget) =>
      live != oldWidget.live;
}
