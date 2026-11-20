import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/room/thread_view_state.dart';
import 'package:soliplex_frontend/src/stores/run_registry.dart';

import '../../helpers/fakes.dart';

// Run on JavaScript as well as the VM: submission ID allocation must reach
// the provider on both targets, whose integer shift semantics differ.
void main() {
  for (final name in [
    'workbench.program.run_result',
    'submit_intake',
    'submit_form'
  ]) {
    test('$name allocates a submission and starts an action turn', () async {
      final stream = RecordingAgUiStreamClient();
      final connection = ServerConnection(
        serverId: 'server',
        api: FakeSoliplexApi()
          ..nextThreadHistory = ThreadHistory(messages: const [])
          ..nextCreateRun = RunInfo(
            id: 'run',
            threadId: 'thread',
            createdAt: DateTime.utc(2026),
          ),
        agUiStreamClient: stream,
      );
      final runtime = AgentRuntime(
        connection: connection,
        toolRegistryResolver: (_) async => const ToolRegistry(),
        platform: TestPlatformConstraints(),
        logger: testLogger(),
      );
      final registry = RunRegistry(servers: emptyServers());
      final view = ThreadViewState(
        connection: connection,
        auth: AuthSession(refreshService: FakeTokenRefreshService()),
        roomId: 'room',
        threadId: 'thread',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      addTearDown(() async {
        view.dispose();
        registry.dispose();
        await runtime.dispose();
      });
      await Future<void>.delayed(Duration.zero);
      final action = <String, Object?>{
        'name': name,
        'surfaceId': 'surface',
        'sourceComponentId': name.startsWith('submit_') ? 'submit' : 'root',
        'context': name == 'submit_form'
            ? {
                'values': {
                  'name': 'Scenario walrus',
                  'color': ['Blue'],
                  'subscribe': true
                }
              }
            : name == 'submit_intake'
                ? {
                    'question': 'Scenario zebra',
                    'districts': ['north'],
                    'acknowledged': true,
                  }
                : {
                    'side': 'client',
                    'engine': 'monty-1.3.0',
                    'invocationId': 'invocation-1',
                    'chainId': 'invocation-1',
                    'outcome': 'success',
                    'output': '766228',
                  },
      };
      view.sendAction(action, runtime, activityMessageId: 'activity');
      for (var i = 0; i < 100 && stream.inputs.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(stream.inputs, hasLength(1));
      final input = stream.inputs.single;
      final envelope = input.forwardedProps!['a2uiAction'] as Map;
      expect(envelope['submissionId'], matches(r'^submission-\d+-[0-9a-f]+$'));
      expect(envelope['activityMessageId'], 'activity');
      expect(envelope['userAction'], action);
      expect(input.messages!.whereType<UserMessage>(), isEmpty);
    });
  }
}
