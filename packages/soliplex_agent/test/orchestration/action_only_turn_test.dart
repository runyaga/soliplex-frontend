import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/orchestration/run_orchestrator.dart';
import 'package:soliplex_client/soliplex_client.dart' show appendUserMessage;
import 'package:test/test.dart';

class _Logger extends Mock implements Logger {}

class _Connection extends Mock implements ServerConnection {}

const ThreadKey _key = (serverId: 'server', roomId: 'room', threadId: 'thread');

/// Answers each run with the next scripted event list.
class _Provider implements AgentLlmProvider {
  _Provider([List<List<BaseEvent>>? script])
      : _script = script ?? [_answer('run')];

  final List<List<BaseEvent>> _script;
  final inputs = <SimpleRunAgentInput>[];

  @override
  Future<LlmRunHandle> startRun({
    required ThreadKey key,
    required SimpleRunAgentInput input,
    String? existingRunId,
    String? parentRunId,
    CancelToken? cancelToken,
    void Function(ReconnectStatus)? onReconnectStatus,
  }) async {
    final events = _script[inputs.length];
    inputs.add(input);
    final runId = (events.first as RunStartedEvent).runId;
    return LlmRunHandle(
      runId: runId,
      events: Stream.fromIterable(
        events.map((event) => DecodedEvent(event, const {})),
      ),
    );
  }

  @override
  LlmRunHandle followRun({
    required ThreadKey key,
    required String runId,
    CancelToken? cancelToken,
    void Function(ReconnectStatus)? onReconnectStatus,
  }) =>
      throw UnsupportedError('No follow fixture');
}

List<BaseEvent> _answer(String runId) => [
      RunStartedEvent(threadId: 'thread', runId: runId),
      const TextMessageStartEvent(messageId: 'answer'),
      const TextMessageContentEvent(messageId: 'answer', delta: 'Fixed'),
      const TextMessageEndEvent(messageId: 'answer'),
      RunFinishedEvent(threadId: 'thread', runId: runId),
    ];

List<BaseEvent> _clientToolCall(String runId) => [
      RunStartedEvent(threadId: 'thread', runId: runId),
      const ToolCallStartEvent(toolCallId: 'tc-1', toolCallName: 'probe'),
      const ToolCallArgsEvent(toolCallId: 'tc-1', delta: '{}'),
      const ToolCallEndEvent(toolCallId: 'tc-1'),
      RunFinishedEvent(threadId: 'thread', runId: runId),
    ];

void main() {
  final action = {
    'userAction': {
      'name': 'python_failed',
      'surfaceId': 'dojo-python',
      'sourceComponentId': 'repl',
      'context': {
        'result': {'ok': false, 'attempt': 1, 'chainId': 'c1'},
      },
      'timestamp': '2026-11-19T00:00:00Z',
    },
  };

  ThreadHistory priorHistory() {
    final prior = appendUserMessage(
      const Conversation(threadId: 'thread'),
      TextMessage.create(
        id: 'question',
        user: ChatUser.user,
        text: 'Make a game',
      ),
    );
    return ThreadHistory(
      messages: prior.messages,
      transcript: prior.transcript,
    );
  }

  RunOrchestrator orchestratorFor(
    _Provider provider, {
    ToolRegistry tools = const ToolRegistry(),
  }) {
    final orchestrator = RunOrchestrator(
      llmProvider: provider,
      toolRegistry: tools,
      logger: _Logger(),
      forwardedProps: () => {'bandwidth': 'low'},
    );
    addTearDown(orchestrator.dispose);
    return orchestrator;
  }

  test('an action turn sends the action and no user message', () async {
    final provider = _Provider();
    final history = priorHistory();
    final result = await orchestratorFor(provider).runToCompletion(
      key: _key,
      userMessage: const [],
      toolExecutor: (_) async => [],
      cachedHistory: history,
      a2uiAction: action,
    ) as CompletedState;
    expect(provider.inputs.single.messages, history.transcript.messages);
    expect(provider.inputs.single.forwardedProps, {
      'bandwidth': 'low',
      'a2uiAction': {...action, 'afterMessageId': 'question'},
    });
    final users = result.conversation.messages
        .whereType<TextMessage>()
        .where((message) => message.user == ChatUser.user);
    expect(users.map((message) => message.id), ['question']);
  });

  test('a continuation resends the same action once', () async {
    final provider = _Provider([_clientToolCall('run-1'), _answer('run-2')]);
    final tools = const ToolRegistry().register(
      ClientTool(
        definition: const Tool(name: 'probe', description: 'Probe'),
        executor: (_, __) async => 'ok',
      ),
    );
    await orchestratorFor(provider, tools: tools).runToCompletion(
      key: _key,
      userMessage: const [],
      toolExecutor: (pending) async => [
        for (final call in pending)
          call.copyWith(status: ToolCallStatus.completed, result: 'ok'),
      ],
      cachedHistory: priorHistory(),
      a2uiAction: action,
    );
    expect(provider.inputs, hasLength(2));
    for (final input in provider.inputs) {
      final props = input.forwardedProps! as Map<String, dynamic>;
      expect(props['a2uiAction'], {...action, 'afterMessageId': 'question'});
      expect(input.messages!.whereType<UserMessage>(), hasLength(1));
    }
  });

  test('normal turns still append their visible user message', () async {
    final provider = _Provider();
    final result = await orchestratorFor(provider).runToCompletion(
      key: _key,
      userMessage: const [TextPart('Next question')],
      toolExecutor: (_) async => [],
      cachedHistory: priorHistory(),
    ) as CompletedState;
    expect(provider.inputs.single.forwardedProps, {'bandwidth': 'low'});
    expect(
      result.conversation.messages
          .whereType<TextMessage>()
          .where((message) => message.user == ChatUser.user),
      hasLength(2),
    );
  });

  test('an action without a name fails before any run starts', () async {
    final provider = _Provider();
    final result = await orchestratorFor(provider).runToCompletion(
      key: _key,
      userMessage: const [],
      toolExecutor: (_) async => [],
      a2uiAction: const {'userAction': <String, Object?>{}},
    );
    expect(result, isA<FailedState>());
    expect(provider.inputs, isEmpty);
  });

  test('runtime rejects action prompts and actions without a thread', () async {
    final connection = _Connection();
    when(() => connection.serverId).thenReturn('server');
    final runtime = AgentRuntime(
      connection: connection,
      llmProvider: _Provider(),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      platform: const WebPlatformConstraints(),
      logger: _Logger(),
    );
    addTearDown(runtime.dispose);
    await expectLater(
      runtime.spawn(roomId: 'room', prompt: const [], a2uiAction: action),
      throwsArgumentError,
    );
    await expectLater(
      runtime.spawn(
        roomId: 'room',
        threadId: 'thread',
        prompt: const [TextPart('not an action')],
        a2uiAction: action,
      ),
      throwsArgumentError,
    );
  });
}
