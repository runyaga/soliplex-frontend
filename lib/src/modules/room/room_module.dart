import 'dart:async' show Stream;

import 'package:go_router/go_router.dart';
import 'package:soliplex_monty_plugin/soliplex_monty_plugin.dart'
    show NotifyEvent, RoomEnvironmentRegistry;

import '../../core/shell_config.dart';
import '../auth/require_connected_server.dart';
import '../auth/server_manager.dart';
import 'agent_runtime_manager.dart';
import 'document_selections.dart';
import 'run_registry.dart';
import 'ui/debug_console_screen.dart';
import 'ui/room_info_screen.dart';
import 'ui/room_screen.dart';

ModuleContribution roomModule({
  required ServerManager serverManager,
  required AgentRuntimeManager runtimeManager,
  required RunRegistry registry,
  bool enableDocumentFilter = false,
  Stream<NotifyEvent>? notifyStream,
  RoomEnvironmentRegistry? envRegistry,
  Future<String> Function(String serverId, String roomId, String code)?
      replExecutor,
}) {
  final documentSelections = DocumentSelections();
  return ModuleContribution(
    routes: [
      GoRoute(
        path: '/room/:serverAlias/:roomId/info',
        redirect: (context, state) => requireConnectedServer(
          serverManager,
          state.pathParameters['serverAlias'],
        ),
        pageBuilder: (context, state) {
          final alias = state.pathParameters['serverAlias']!;
          final entry = serverManager.entryByAlias(alias)!;
          return NoTransitionPage(
            child: RoomInfoScreen(
              serverEntry: entry,
              roomId: state.pathParameters['roomId']!,
              toolRegistryResolver: runtimeManager.toolRegistryResolver,
            ),
          );
        },
      ),
      _buildRoute(
        '/room/:serverAlias/:roomId',
        serverManager,
        runtimeManager,
        registry,
        enableDocumentFilter,
        documentSelections,
        notifyStream,
      ),
      _buildRoute(
        '/room/:serverAlias/:roomId/thread/:threadId',
        serverManager,
        runtimeManager,
        registry,
        enableDocumentFilter,
        documentSelections,
        notifyStream,
      ),
      if (envRegistry != null)
        _buildDebugRoute(serverManager, envRegistry, replExecutor),
    ],
  );
}

GoRoute _buildRoute(
  String path,
  ServerManager serverManager,
  AgentRuntimeManager runtimeManager,
  RunRegistry registry,
  bool enableDocumentFilter,
  DocumentSelections documentSelections,
  Stream<NotifyEvent>? notifyStream,
) {
  return GoRoute(
    path: path,
    redirect: (context, state) => requireConnectedServer(
      serverManager,
      state.pathParameters['serverAlias'],
    ),
    pageBuilder: (context, state) {
      final alias = state.pathParameters['serverAlias']!;
      final entry = serverManager.entryByAlias(alias)!;
      return NoTransitionPage(
        child: RoomScreen(
          serverEntry: entry,
          roomId: state.pathParameters['roomId']!,
          threadId: state.pathParameters['threadId'],
          runtimeManager: runtimeManager,
          registry: registry,
          enableDocumentFilter: enableDocumentFilter,
          documentSelections: documentSelections,
          notifyStream: notifyStream,
        ),
      );
    },
  );
}

GoRoute _buildDebugRoute(
  ServerManager serverManager,
  RoomEnvironmentRegistry envRegistry,
  Future<String> Function(String, String, String)? replExecutor,
) {
  return GoRoute(
    path: '/room/:serverAlias/:roomId/debug',
    redirect: (context, state) => requireConnectedServer(
      serverManager,
      state.pathParameters['serverAlias'],
    ),
    pageBuilder: (context, state) {
      final alias = state.pathParameters['serverAlias']!;
      final entry = serverManager.entryByAlias(alias)!;
      final roomId = state.pathParameters['roomId']!;
      final pythonExecutor = replExecutor == null
          ? null
          : (String code) => replExecutor(entry.serverId, roomId, code);
      return NoTransitionPage(
        child: DebugConsoleScreen(
          serverEntry: entry,
          roomId: roomId,
          envRegistry: envRegistry,
          pythonExecutor: pythonExecutor,
        ),
      );
    },
  );
}
