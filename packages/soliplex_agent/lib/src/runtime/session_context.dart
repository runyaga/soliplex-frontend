import 'package:meta/meta.dart';
import 'package:soliplex_agent/src/runtime/agent_runtime.dart';
import 'package:soliplex_agent/src/runtime/agent_session.dart';
import 'package:soliplex_agent/src/runtime/session_coordinator.dart';
import 'package:soliplex_agent/src/runtime/session_extension.dart';
import 'package:soliplex_client/soliplex_client.dart' show StateBus;

/// Per-session execution context passed to
/// [SessionExtension.onAttachWithContext].
///
/// Carries the references a handler is most likely to need:
///
/// - [session] — the [AgentSession] this extension is attached to.
/// - [runtime] — the [AgentRuntime] that owns the session, used for
///   spawning children, looking up other sessions, or accessing
///   per-runtime state.
/// - [bus] — the per-thread reactive document. Handlers write state
///   via `bus.applyDelta(...)` (or `bus.update(...)` /
///   `bus.setAgentState(...)`) and read derived signals via
///   `bus.project(...)`. The bus survives session boundaries within
///   a thread.
///
/// Plan reference: `docs/plans/reactive-bus-redesign.md` (Phase 1
/// steps 2 + 3b).
@immutable
class SessionContext {
  /// Constructs a context bound to a single [session]. Callers should
  /// not construct contexts directly; the [SessionCoordinator] creates
  /// one per session during [SessionCoordinator.attachAll].
  const SessionContext({
    required this.session,
    required this.runtime,
    required this.bus,
  });

  /// The session this context is bound to.
  final AgentSession session;

  /// The runtime that owns [session].
  final AgentRuntime runtime;

  /// The per-thread reactive bus. Owned by the runtime; survives
  /// session boundaries within the thread's lifetime.
  final StateBus bus;
}
