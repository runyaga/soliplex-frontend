import 'package:soliplex_agent/src/runtime/agent_session.dart';
import 'package:soliplex_agent/src/runtime/session_context.dart';
import 'package:soliplex_agent/src/tools/tool_registry.dart';

/// A capability bound to the lifecycle of an [AgentSession].
///
/// Extensions provide tools and resources that are created when the
/// session starts and disposed when the session ends.
///
/// Subclass via `extends SessionExtension` to inherit the default
/// [namespace] and [priority]. Mix in `StatefulSessionExtension` to
/// add a typed reactive-state signal.
abstract class SessionExtension {
  /// Unique identifier for this extension type.
  ///
  /// The coordinator validates uniqueness across all extensions in a session
  /// when the namespace is non-empty. Use the default empty string for
  /// extensions that do not need cross-extension discovery.
  String get namespace => '';

  /// Attach priority. Higher values attach first and dispose last.
  int get priority => 0;

  /// Called after session creation, before the run starts.
  ///
  /// Receives the [session] for context access (e.g. spawning children,
  /// emitting events, or accessing other extensions).
  ///
  /// Prefer overriding [onAttachWithContext] in new extensions — it
  /// receives a [SessionContext] that exposes the session, runtime, and
  /// (after step 3 of the reactive-bus redesign) the per-thread bus.
  /// The default [onAttachWithContext] forwards to this method, so
  /// existing extensions keep working unchanged.
  Future<void> onAttach(AgentSession session);

  /// Called after session creation, before the run starts. Receives a
  /// [SessionContext] with the session, runtime, and (after step 3 of
  /// the reactive-bus redesign) the per-thread bus.
  ///
  /// The default implementation forwards to [onAttach] for backwards
  /// compatibility. New extensions should override this method instead
  /// of [onAttach] when they need access to anything beyond the session.
  ///
  /// Plan reference: `docs/plans/reactive-bus-redesign.md` (Phase 1 step 2).
  Future<void> onAttachWithContext(SessionContext ctx) => onAttach(ctx.session);

  /// Tools this extension provides.
  ///
  /// Returned tools are merged into the session's [ToolRegistry] during
  /// [onAttach]. The list must be stable after [onAttach] completes.
  List<ClientTool> get tools;

  /// Called when the session is disposed. Must be idempotent.
  void onDispose();
}

/// Factory that creates extensions for each new session.
typedef SessionExtensionFactory = Future<List<SessionExtension>> Function();
