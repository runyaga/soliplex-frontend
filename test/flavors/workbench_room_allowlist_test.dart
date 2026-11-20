import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkbenchClient;
import 'package:soliplex_frontend/soliplex_frontend.dart';

void main() {
  testWidgets('hosts listed rooms and leaves unlisted rooms as chat',
      (tester) async {
    final host = _TestWorkbenchHost();
    final presentation = WorkbenchRoomAllowlistPresentation(
      rooms: const {'workbench', 'workbench-e4b'},
      host: host,
    );
    const chat = SizedBox(key: ValueKey('standard-chat'));
    final client = _UnusedWorkbenchClient();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: presentation.buildHost(
          roomId: 'workbench-e4b',
          threadId: 'thread-1',
          chat: chat,
          client: client,
          surfaceBuilder: (_, __) => const SizedBox.shrink(),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('workbench-host')), findsOneWidget);
    expect(host.calls, 1);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: presentation.buildHost(
          roomId: 'a2ui-lab',
          threadId: 'thread-2',
          chat: chat,
          client: client,
          surfaceBuilder: (_, __) => const SizedBox.shrink(),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('standard-chat')), findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-host')), findsNothing);
    expect(host.calls, 1);
  });
}

class _TestWorkbenchHost implements WorkbenchPresentation {
  int calls = 0;

  @override
  Widget buildHost({
    required String roomId,
    required String threadId,
    required Widget chat,
    required WorkbenchClient client,
    required Widget Function(String activityMessageId, String surfaceId)
        surfaceBuilder,
  }) {
    calls++;
    return const SizedBox(key: ValueKey('workbench-host'));
  }
}

class _UnusedWorkbenchClient implements WorkbenchClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
