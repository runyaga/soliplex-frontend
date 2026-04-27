import 'package:meta/meta.dart';
import 'package:soliplex_agent/src/tools/tool_execution_context.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// Signature for a function that executes a tool call with context.
///
/// Receives the [ToolCallInfo] (name, arguments, id) and a
/// [ToolExecutionContext] providing cancellation, child spawning, and
/// session-scoped extensions. Returns a result string. Throwing an
/// exception marks the tool call as failed; the error message is
/// forwarded to the model.
typedef ToolExecutor = Future<String> Function(
  ToolCallInfo toolCall,
  ToolExecutionContext context,
);

/// One LLM tool invocation observed by [ToolRegistry.execute].
///
/// Emitted to the [ToolObserver] after the executor returns or
/// throws. Carries enough information for the in-app tool log to
/// display name, args, return value, duration, and error attribution
/// without re-running the tool.
@immutable
class ToolInvocationEvent {
  /// Constructs a tool-invocation event.
  const ToolInvocationEvent({
    required this.toolName,
    required this.toolCallId,
    required this.arguments,
    required this.startedAt,
    required this.duration,
    this.result,
    this.error,
  });

  /// Resolved canonical tool name (after alias resolution).
  final String toolName;

  /// Tool-call id supplied by the model. Useful for cross-referencing
  /// against AG-UI events in the network inspector.
  final String toolCallId;

  /// JSON-encoded arguments string as sent by the model. Empty when
  /// the executor was called without arguments.
  final String arguments;

  /// Wall-clock at execution start.
  final DateTime startedAt;

  /// Wall-clock duration of the executor call.
  final Duration duration;

  /// String returned by the executor on success. `null` when the
  /// executor threw.
  final String? result;

  /// Error thrown by the executor, or `null` on success.
  final Object? error;
}

/// Observer callback fired after every committed [ToolRegistry.execute]
/// — both success and failure paths.
typedef ToolObserver = void Function(ToolInvocationEvent event);

/// Default JSON Schema for tools that take no parameters.
const Map<String, Object> emptyToolParameters = {
  'type': 'object',
  'properties': <String, Object>{},
};

/// A client-side tool definition paired with its executor.
@immutable
class ClientTool {
  /// Creates a client-side tool from a pre-built [Tool] definition.
  const ClientTool({required this.definition, required this.executor});

  /// Creates a client-side tool with sensible defaults.
  ///
  /// [parameters] defaults to an empty JSON Schema object so servers that
  /// require a non-null schema don't reject the tool.
  ClientTool.simple({
    required String name,
    required String description,
    required this.executor,
    dynamic parameters = emptyToolParameters,
  }) : definition = Tool(
          name: name,
          description: description,
          parameters: parameters,
        );

  /// AG-UI [Tool] definition sent to the backend so the model knows this
  /// tool exists.
  final Tool definition;

  /// Function that executes the tool and returns a result string.
  final ToolExecutor executor;
}

/// Immutable registry of client-side tools.
///
/// Shared via a Riverpod provider so multiple notifier instances (current
/// singleton or future multiplexed family) use the same tool set.
///
/// Register tools at app startup; the registry is immutable once built.
/// Each [register] call returns a **new** registry instance.
@immutable
class ToolRegistry {
  /// Creates an empty registry.
  const ToolRegistry()
      : _tools = const {},
        _aliases = const {},
        _observer = null;

  const ToolRegistry._(this._tools, this._aliases, [this._observer]);

  final Map<String, ClientTool> _tools;
  final ToolObserver? _observer;

  /// Maps alternative names to canonical tool names.
  ///
  /// Used when the backend sends tool calls using a short name (e.g.
  /// `get_current_datetime`) but the tool is registered under its full
  /// name (e.g. `soliplex.tools.get_current_datetime`). Aliases are
  /// not included in [toolDefinitions] to avoid conflicts.
  final Map<String, String> _aliases;

  /// Registers a [ClientTool] and returns a new registry containing it.
  ///
  /// The tool is keyed by the tool definition's name.
  @useResult
  ToolRegistry register(ClientTool tool) {
    return ToolRegistry._(
      {..._tools, tool.definition.name: tool},
      _aliases,
      _observer,
    );
  }

  /// Maps [aliasName] to the canonical [canonicalName] for lookup.
  ///
  /// The alias is only used by [lookup] / [execute] / [contains]; it does
  /// not appear in [toolDefinitions].
  @useResult
  ToolRegistry alias(String aliasName, String canonicalName) {
    return ToolRegistry._(
      _tools,
      {..._aliases, aliasName: canonicalName},
      _observer,
    );
  }

  /// Returns a new registry without the tool named [name].
  ///
  /// If [name] is an alias, only the alias is removed; the canonical
  /// tool remains. If [name] is a canonical name, the tool and any
  /// aliases pointing to it are removed.
  @useResult
  ToolRegistry unregister(String name) {
    if (_aliases.containsKey(name)) {
      return ToolRegistry._(
        _tools,
        {..._aliases}..remove(name),
        _observer,
      );
    }
    final newAliases = {
      for (final e in _aliases.entries)
        if (e.value != name) e.key: e.value,
    };
    return ToolRegistry._(
      {..._tools}..remove(name),
      newAliases,
      _observer,
    );
  }

  /// Returns a new registry with [observer] installed. The observer
  /// is fired after every [execute] call (success or failure).
  /// Pass `null` to remove an existing observer.
  @useResult
  ToolRegistry withObserver(ToolObserver? observer) =>
      ToolRegistry._(_tools, _aliases, observer);

  /// Returns the [ClientTool] registered under [name].
  ///
  /// Throws [StateError] if no tool with that name is registered.
  ClientTool lookup(String name) {
    final tool = _tools[name] ?? _tools[_aliases[name]];
    if (tool == null) {
      throw StateError('No tool registered with name "$name"');
    }
    return tool;
  }

  /// Executes the tool matching the given tool call's name.
  ///
  /// The [ctx] is forwarded to the tool executor so tools can access
  /// cancellation tokens, child spawning, and session extensions.
  ///
  /// If a [ToolObserver] is installed (see [withObserver]), it fires
  /// once per call after the executor returns (success) or throws
  /// (failure). The observer never alters control flow — exceptions
  /// from the executor are re-thrown unchanged.
  Future<String> execute(
    ToolCallInfo toolCall,
    ToolExecutionContext ctx,
  ) async {
    final observer = _observer;
    if (observer == null) {
      final tool = lookup(toolCall.name);
      return tool.executor(toolCall, ctx);
    }
    final startedAt = DateTime.now();
    final tool = lookup(toolCall.name);
    String? result;
    Object? error;
    try {
      return result = await tool.executor(toolCall, ctx);
    } on Object catch (e) {
      error = e;
      rethrow;
    } finally {
      observer(
        ToolInvocationEvent(
          toolName: tool.definition.name,
          toolCallId: toolCall.id,
          arguments: toolCall.arguments,
          startedAt: startedAt,
          duration: DateTime.now().difference(startedAt),
          result: result,
          error: error,
        ),
      );
    }
  }

  /// Whether a tool with [name] is registered.
  bool contains(String name) =>
      _tools.containsKey(name) || _tools.containsKey(_aliases[name]);

  /// The number of registered tools.
  int get length => _tools.length;

  /// Whether the registry has no tools.
  bool get isEmpty => _tools.isEmpty;

  /// AG-UI [Tool] definitions for all registered tools.
  ///
  /// Pass this to [SimpleRunAgentInput.tools] so the model knows which
  /// client-side tools are available.
  List<Tool> get toolDefinitions =>
      _tools.values.map((ct) => ct.definition).toList(growable: false);
}
