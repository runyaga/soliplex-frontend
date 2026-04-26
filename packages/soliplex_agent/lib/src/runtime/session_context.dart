import 'package:meta/meta.dart';
import 'package:soliplex_agent/src/runtime/agent_runtime.dart';
import 'package:soliplex_agent/src/runtime/agent_session.dart';
import 'package:soliplex_agent/src/runtime/session_coordinator.dart';
import 'package:soliplex_agent/src/runtime/session_extension.dart';

/// Per-session execution context passed to
/// [SessionExtension.onAttachWithContext].
///
/// Carries the references a handler is most likely to need:
///
/// - [session] — the [AgentSession] this extension is attached to.
/// - [runtime] — the [AgentRuntime] that owns the session, used for
///   spawning children, looking up other sessions, or accessing
///   per-runtime state.
///
/// In Phase 1 step 3 of the reactive-bus redesign this gains a
/// per-thread `bus` reference; in Phase 2 it becomes the object plugin
/// `hostFunctions` receive. For now the context is intentionally
/// minimal — the additive surface lands first, the new fields land
/// alongside the changes that need them.
///
/// Plan reference: `docs/plans/reactive-bus-redesign.md` (Phase 1 step 2).
@immutable
class SessionContext {
  /// Constructs a context bound to a single [session]. Callers should
  /// not construct contexts directly; the [SessionCoordinator] creates
  /// one per session during [SessionCoordinator.attachAll].
  const SessionContext({required this.session, required this.runtime});

  /// The session this context is bound to.
  final AgentSession session;

  /// The runtime that owns [session].
  final AgentRuntime runtime;
}
