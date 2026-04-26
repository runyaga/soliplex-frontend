import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent_maps/soliplex_agent_maps.dart';
import 'package:soliplex_agent_monty/soliplex_agent_monty.dart';

import '../../maps_singleton.dart' as maps_singleton;
import '../../narration/narration.dart';
import '../../narration/narration_controller.dart';
import '../../narration_singleton.dart';
import '../../widget_tree/widget_spec.dart';
import '../../widget_tree/widget_tree_projection.dart';

import 'execution_tracker.dart';
import 'execution_tracker_extension.dart';
import 'historical_replay.dart';
import 'human_approval_extension.dart';
import 'tool_calls_extension.dart';
import 'run_registry.dart';
import 'send_error.dart';
import 'session_spawner.dart';

export 'send_error.dart';

sealed class ThreadViewStatus {}

class MessagesLoading extends ThreadViewStatus {}

class MessagesLoaded extends ThreadViewStatus {
  MessagesLoaded({required this.messages, required this.messageStates});
  final List<ChatMessage> messages;
  final Map<String, MessageState> messageStates;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessagesLoaded &&
          identical(messages, other.messages) &&
          identical(messageStates, other.messageStates);

  @override
  int get hashCode => Object.hash(messages, messageStates);
}

class MessagesFailed extends ThreadViewStatus {
  MessagesFailed(this.error);
  final Object error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessagesFailed && identical(error, other.error);

  @override
  int get hashCode => error.hashCode;
}

/// Callback invoked when thread history is loaded from the server.
///
/// Provides the thread ID and the full loaded history so callers can
/// seed the runtime's thread history cache with messages and AG-UI state.
typedef HistoryLoadedCallback = void Function(
  String threadId,
  ThreadHistory history,
);

class ThreadViewState {
  ThreadViewState({
    required ServerConnection connection,
    required String roomId,
    required this.threadId,
    required RunRegistry registry,
    this.onHistoryLoaded,
  })  : _connection = connection,
        _roomId = roomId,
        _registry = registry {
    // Wire surface projections once for the lifetime of this
    // thread. They follow the bus value through both
    // history-load (reload restoration) and live session
    // updates without rebinding.
    _wireSurfaceSingletons();
    // P6 spike: subscribe to surface-emitted events. Each event
    // becomes a synthetic user message so the LLM can react.
    _surfaceEventsSub = _bus.events.listen(_handleSurfaceEvent);
    if (!_restoreFromRegistry()) _fetch();
  }

  /// Forwards a surface-emitted event toward the agent as a
  /// synthetic prompt. The event becomes a one-line user message
  /// the LLM can react to via tool calls — the bidirectional half
  /// of the GenUI contract. Wire-format SSE events from the agent
  /// flow into the bus via [setAgentState] / [update]; surface
  /// events flow out via [emit] and end up here.
  ///
  /// v1: synthetic user-prompt routing. Future versions will use a
  /// dedicated AG-UI client→server event when the protocol grows
  /// one.
  void _handleSurfaceEvent(SurfaceEvent event) {
    final session = _activeSession;
    final prompt = '[surface event] '
        '${event.surfaceId} → ${event.kind}: '
        '${event.data}';
    debugPrint('SurfaceEvent forwarded as prompt: $prompt');
    if (session == null) {
      // No active session — for spike v1, log and drop.
      // Future: queue and flush on next session attach.
      return;
    }
    // Future: use a dedicated input channel rather than chat.
    // For the spike, the existing send-message path is enough.
    debugPrint(
      'SurfaceEvent received during active session — '
      'queue-and-prompt forwarding is a follow-up. '
      'Event was: $prompt',
    );
  }

  final ServerConnection _connection;
  final String _roomId;
  final String threadId;
  final HistoryLoadedCallback? onHistoryLoaded;
  final RunRegistry _registry;

  ThreadKey get threadKey => (
        serverId: _connection.serverId,
        roomId: _roomId,
        threadId: threadId,
      );

  CancelToken? _cancelToken;
  AgentSession? _activeSession;
  void Function()? _runStateUnsub;
  void Function()? _agentStateUnsub;
  void Function()? _markersFitOnceUnsub;
  void Function()? _convoyFollowUnsub;
  StreamSubscription<SurfaceEvent>? _surfaceEventsSub;
  bool _hasFitBoundsThisSession = false;
  double? _lastConvoyLat;
  double? _lastConvoyLng;
  bool _isDisposed = false;

  /// Per-thread reactive bus mirroring AG-UI agent state.
  ///
  /// Re-created on every session attach because each AgentSession has
  /// its own agentState signal we pipe through. Surfaces register
  /// projections via `bus.project(...)` and read the returned signal;
  /// the projection re-runs whenever the agent emits a state event.
  ///
  /// This is the seam between the AG-UI streaming pipeline and the
  /// GenUI surface layer. See `packages/soliplex_client/lib/src/
  /// application/state_bus.dart`.
  /// Lives for the full lifetime of this ThreadViewState — survives
  /// session attach/detach. Seeded from `history.aguiState` on
  /// thread-history load (so reload restores state), updated by
  /// the active session's `agentState` signal while a session is
  /// attached. Disposed in [dispose].
  final StateBus _bus = StateBus();
  StateBus get bus => _bus;

  /// Projected widget tree from the bus — driven by
  /// `agentState['ui']['widgets']`. Widgets render via
  /// [WidgetTreePanel]; empty list = panel collapses.
  late final ReadonlySignal<List<WidgetSpec>> _widgetsSignal =
      _bus.project<List<WidgetSpec>>(const WidgetTreeProjection());
  ReadonlySignal<List<WidgetSpec>> get widgets => _widgetsSignal;

  final SessionSpawner _spawner = SessionSpawner();

  final Signal<ThreadViewStatus> _messages =
      Signal<ThreadViewStatus>(MessagesLoading());
  ReadonlySignal<ThreadViewStatus> get messages => _messages;

  final Signal<StreamingState?> _streamingState = Signal<StreamingState?>(null);
  ReadonlySignal<StreamingState?> get streamingState => _streamingState;

  /// Tracks the session lifecycle: null → spawning → running → null.
  /// Driven by [_spawner] during spawn (via its state-transition callback)
  /// and updated directly here for attach, running, and detach transitions.
  final Signal<AgentSessionState?> _sessionState =
      Signal<AgentSessionState?>(null);
  ReadonlySignal<AgentSessionState?> get sessionState => _sessionState;

  final Signal<SendError?> _lastSendError = Signal<SendError?>(null);
  ReadonlySignal<SendError?> get lastSendError => _lastSendError;

  // Persists historical trackers from loaded thread history and from
  // completed sessions (absorbed in _detachSession). Plain map — the live
  // registry lives inside ExecutionTrackerExtension, which outlives the
  // view when the session runs in the background.
  final Map<String, ExecutionTracker> _historicalTrackers = {};

  /// Returns all execution trackers for this thread: historical (from loaded
  /// thread history) merged with any live trackers from the active session.
  Map<String, ExecutionTracker> get executionTrackers {
    final ext = _activeSession?.getExtension<ExecutionTrackerExtension>();
    if (ext == null) return Map.unmodifiable(_historicalTrackers);
    return {..._historicalTrackers, ...ext.trackers};
  }

  /// Live tool call statuses from the active session, or null if no session
  /// is attached.
  ReadonlySignal<List<ToolCallEntry>>? get toolCalls =>
      _activeSession?.getExtension<ToolCallsExtension>()?.stateSignal;

  /// Pending approval request from the active session, or null if no session
  /// is attached or no approval is pending.
  ReadonlySignal<ApprovalRequest?>? get pendingApproval =>
      _activeSession?.getExtension<HumanApprovalExtension>()?.stateSignal;

  /// The [HumanApprovalExtension] attached to the active session, or null.
  /// Use [respond] to resolve a pending request shown via [pendingApproval].
  HumanApprovalExtension? get approvalExtension =>
      _activeSession?.getExtension<HumanApprovalExtension>();

  /// The [MapExtension] attached to the active session, or null.
  /// Used by the room view to mount a `MapView` widget so the LLM-driven
  /// `MapController` has something to bind to.
  MapExtension? get mapExtension =>
      _activeSession?.getExtension<MapExtension>();

  /// The [MontyRuntimeExtension] attached to the active session, or null.
  /// When non-null, the room shows a Terminal button that opens a panel
  /// for running Python directly on-device, bypassing the LLM.
  MontyRuntimeExtension? get montyRuntimeExtension =>
      _activeSession?.getExtension<MontyRuntimeExtension>();

  /// Returns `(namespace, signal)` pairs for every stateful extension on the
  /// active session, or an empty iterable if no session is attached.
  ///
  /// Re-evaluate whenever [sessionState] changes.
  Iterable<(String, ReadonlySignal<Object?>)> get statefulObservations =>
      _activeSession?.statefulObservations() ??
      const <(String, ReadonlySignal<Object?>)>[];

  void submitFeedback(String runId, FeedbackType feedback, String? reason) {
    unawaited(
      _connection.api
          .submitFeedback(_roomId, threadId, runId, feedback, reason: reason)
          .catchError((Object e) {
        debugPrint('Feedback submission failed: $e');
      }),
    );
  }

  void clearSendError() => _lastSendError.value = null;

  void refresh() => _fetch();

  Future<void> sendMessage(
    String prompt,
    AgentRuntime runtime, {
    Map<String, dynamic>? stateOverlay,
  }) {
    // Guard against sends while a session is already spawning/running.
    // The spawner's own re-entrancy guard only covers in-flight spawns;
    // this blocks overlapping sends when a prior session is attached.
    if (_sessionState.value != null) return Future<void>.value();
    return _spawner.spawn(
      spawnFn: () => runtime.spawn(
        roomId: _roomId,
        prompt: prompt,
        threadId: threadId,
        stateOverlay: stateOverlay,
      ),
      errorSignal: _lastSendError,
      prompt: prompt,
      isDisposed: () => _isDisposed,
      onSpawned: (session) {
        _registry.register(threadKey, session);
        if (_isDisposed) return;
        _attachSession(session);
      },
      onStateTransition: (state) {
        if (_isDisposed) return;
        _sessionState.value = state;
      },
    );
  }

  void attachSession(AgentSession session) {
    _attachSession(session);
  }

  void cancelRun() {
    if (_spawner.cancel()) {
      _sessionState.value = null;
      return;
    }
    _activeSession?.cancel();
  }

  void _attachSession(AgentSession session) {
    if (_isDisposed) return;
    _detachSession();
    _cancelToken?.cancel('session attached');
    _activeSession = session;
    _sessionState.value = session.state;
    _runStateUnsub = session.runState.subscribe(_onRunState);
    // Feed the existing bus from the session's agentState signal.
    // The bus is per-thread and survives session detach so
    // history-loaded state isn't discarded; only the subscription
    // changes here.
    final initial = session.agentState.value;
    if (initial.isNotEmpty) _bus.setAgentState(initial);
    _agentStateUnsub = session.agentState.subscribe(_bus.setAgentState);
  }

  /// Auto-wire the app-level surface singletons to projections over
  /// the per-thread bus. Without this, real session events flow to
  /// `aguiState` but the panels never see them — only the demo
  /// button's free-standing bus would update them.
  ///
  /// Mirrors the demo-button setup but driven by the live session.
  /// Unwired in [_detachSession] when the session ends.
  void _wireSurfaceSingletons() {
    final narrationSignal = _bus.project<List<Narration>>(
      const NarrationProjection(),
    );
    final markersSignal = _bus.project<List<MarkerData>>(
      const MapMarkersProjection(),
    );
    final spritesSignal = _bus.project<List<ImageOverlayData>>(
      const MapSpritesProjection(),
    );
    final hudsSignal = _bus.project<List<HudOverlayData>>(
      const MapHudProjection(),
    );
    narrationController.wireProjection(narrationSignal);
    maps_singleton.mapExtension
      ..wireMarkersProjection(markersSignal)
      ..wireImagesProjection(spritesSignal)
      ..wireHudsProjection(hudsSignal);
    // Auto-fit the camera to the markers ONCE per session, when
    // the first non-empty marker list arrives. Camera stays under
    // user control after that — subsequent deltas (status flips,
    // convoy moves) leave the viewport alone.
    _hasFitBoundsThisSession = false;
    _markersFitOnceUnsub = markersSignal.subscribe((markers) {
      if (_hasFitBoundsThisSession || markers.isEmpty) return;
      _hasFitBoundsThisSession = true;
      unawaited(
        maps_singleton.mapExtension.fitBounds(
          points: [
            for (final m in markers) [m.lat, m.lng],
          ],
          paddingPct: 18,
        ),
      );
    });
    // Camera-follow the primary sprite (convoy). When the
    // convoy's id-1 sprite moves to a new position, fly the
    // camera with it for the cinematic arc — the sprite tween
    // and the camera arc finish in lockstep via flyWithImage.
    _lastConvoyLat = null;
    _lastConvoyLng = null;
    _convoyFollowUnsub = spritesSignal.subscribe((sprites) {
      final convoy = sprites.cast<ImageOverlayData?>().firstWhere(
            (s) => s?.id == 'convoy-1',
            orElse: () => null,
          );
      if (convoy == null) return;
      // Skip if position didn't change (same delta replays etc.)
      if (_lastConvoyLat == convoy.lat && _lastConvoyLng == convoy.lng) {
        return;
      }
      // Skip the very first emission (initial pose) — fitBounds
      // already framed the scene; flying immediately fights it.
      final hasPrior = _lastConvoyLat != null;
      _lastConvoyLat = convoy.lat;
      _lastConvoyLng = convoy.lng;
      if (!hasPrior) return;
      unawaited(
        maps_singleton.mapExtension.flyWithImage(
          imageId: convoy.id,
          lat: convoy.lat,
          lng: convoy.lng,
          durationMs: 1500,
        ),
      );
    });
  }

  void _unwireSurfaceSingletons() {
    _markersFitOnceUnsub?.call();
    _markersFitOnceUnsub = null;
    _convoyFollowUnsub?.call();
    _convoyFollowUnsub = null;
    narrationController.unwireProjection();
    maps_singleton.mapExtension.unwireAllProjections();
  }

  void _onRunState(RunState runState) {
    switch (runState) {
      case RunningState(:final conversation, :final streaming):
        final current = _messages.value;
        if (current is! MessagesLoaded ||
            !identical(current.messages, conversation.messages)) {
          _messages.value = _messagesLoaded(conversation);
        }
        _streamingState.value = streaming;
        _sessionState.value = AgentSessionState.running;
      case CompletedState(:final conversation):
        _detachSession();
        _messages.value = _messagesLoaded(conversation);
      case FailedState(:final conversation, :final error):
        _detachSession();
        _lastSendError.value = SendError(error);
        if (conversation != null) {
          _messages.value = _messagesLoaded(conversation);
        }
      case CancelledState(:final conversation):
        _detachSession();
        if (conversation != null) {
          _messages.value = _messagesLoaded(conversation);
        }
      case IdleState():
      case ToolYieldingState():
        break;
    }
  }

  MessagesLoaded _messagesLoaded(Conversation conversation) {
    final existing = switch (_messages.value) {
      MessagesLoaded(:final messageStates) => messageStates,
      _ => const <String, MessageState>{},
    };
    final merged = {...existing, ...conversation.messageStates};
    return MessagesLoaded(
      messages: conversation.messages,
      messageStates: merged,
    );
  }

  void _detachSession() {
    // Absorb live trackers from the extension before clearing the session
    // reference, so historical data persists after the session ends.
    final ext = _activeSession?.getExtension<ExecutionTrackerExtension>();
    if (ext != null) {
      // Live tracker wins over any historical entry with the same key.
      for (final entry in ext.trackers.entries) {
        _historicalTrackers.putIfAbsent(entry.key, () => entry.value);
      }
    }
    _runStateUnsub?.call();
    _runStateUnsub = null;
    _agentStateUnsub?.call();
    _agentStateUnsub = null;
    _activeSession = null;
    _streamingState.value = null;
    _sessionState.value = null;
    // Bus and projection wires survive across detach — last value
    // remains visible in the panels until the next session attach
    // or thread reload feeds new state. Surface singletons stay
    // wired (unwired only in [dispose]).
  }

  bool _restoreFromRegistry() {
    final session = _registry.activeSession(threadKey);
    if (session != null) {
      _attachSession(session);
      return true;
    }
    final outcome = _registry.completedOutcome(threadKey);
    if (outcome != null) {
      _applyOutcome(outcome);
      return true;
    }
    return false;
  }

  void _applyOutcome(RunOutcome outcome) {
    switch (outcome) {
      case CompletedRun(:final conversation):
        _messages.value = _messagesLoaded(conversation);
      case FailedRun(:final conversation, :final error):
        _lastSendError.value = SendError(error);
        if (conversation != null) {
          _messages.value = _messagesLoaded(conversation);
        }
      case CancelledRun(:final conversation):
        if (conversation != null) {
          _messages.value = _messagesLoaded(conversation);
        }
    }
  }

  void _fetch() {
    if (_isDisposed) return;
    _cancelToken?.cancel('re-fetch');
    final token = CancelToken();
    _cancelToken = token;

    if (_messages.value is! MessagesLoaded) {
      _messages.value = MessagesLoading();
    }

    _connection.api
        .getThreadHistory(_roomId, threadId, cancelToken: token)
        .then((history) {
      if (token.isCancelled) return;
      _cancelToken = null;
      for (final entry in replayToTrackers(history.runs).entries) {
        _historicalTrackers.putIfAbsent(entry.key, () => entry.value);
      }
      _messages.value = MessagesLoaded(
        messages: history.messages,
        messageStates: history.messageStates,
      );
      // Rehydrate the surface bus from persisted aguiState so
      // the panels restore their last state on browser reload.
      // Projections wired in the constructor pick this up
      // immediately; no session needed.
      if (history.aguiState.isNotEmpty) {
        _bus.setAgentState(Map<String, dynamic>.from(history.aguiState));
      }
      onHistoryLoaded?.call(threadId, history);
    }).catchError((Object error) {
      if (token.isCancelled) return;
      _cancelToken = null;
      if (_messages.value is! MessagesLoaded) {
        _messages.value = MessagesFailed(error);
      }
    });
  }

  void dispose() {
    _isDisposed = true;
    _cancelToken?.cancel('disposed');
    _detachSession();
    _unwireSurfaceSingletons();
    unawaited(_surfaceEventsSub?.cancel());
    _surfaceEventsSub = null;
    _bus.dispose();
    _sessionState.dispose();
  }
}
