import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/execution_timeline.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late Signal<ExecutionEvent?> events;
  late ExecutionTracker tracker;

  setUp(() {
    events = Signal<ExecutionEvent?>(null);
    tracker = ExecutionTracker(executionEvents: events);
  });

  tearDown(() => tracker.dispose());

  testWidgets('renders nothing for empty timeline', (tester) async {
    await tester.pumpWidget(wrap(ExecutionTimeline(tracker: tracker)));
    await tester.pump();

    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('header counts step + nested activities', (tester) async {
    events.value = const ClientToolExecuting(
      toolName: 'execute_skill',
      toolCallId: 'tc-1',
    );
    events.value = const ActivitySnapshot(
      messageId: 'bwrap:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'execute_script', 'args': '{}'},
      timestamp: 100,
    );
    events.value = const ActivitySnapshot(
      messageId: 'bwrap:call_2',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'list_environments', 'args': '{}'},
      timestamp: 101,
    );

    await tester.pumpWidget(wrap(ExecutionTimeline(tracker: tracker)));
    await tester.pump();

    expect(find.text('3 events'), findsOneWidget);
  });

  testWidgets('singular label when only one event', (tester) async {
    events.value = const ThinkingStarted();

    await tester.pumpWidget(wrap(ExecutionTimeline(tracker: tracker)));
    await tester.pump();

    expect(find.text('1 event'), findsOneWidget);
  });

  testWidgets('tap expands to show step and nested activity', (tester) async {
    events.value = const ClientToolExecuting(
      toolName: 'execute_skill',
      toolCallId: 'tc-1',
    );
    events.value = const ActivitySnapshot(
      messageId: 'bwrap:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'execute_script', 'args': '{}'},
      timestamp: 100,
    );

    await tester.pumpWidget(wrap(ExecutionTimeline(tracker: tracker)));
    await tester.pump();

    expect(find.text('execute_skill'), findsNothing);
    expect(find.text('execute_script'), findsNothing);

    await tester.tap(find.text('2 events'));
    await tester.pump();

    expect(find.text('execute_skill'), findsOneWidget);
    expect(find.text('execute_script'), findsOneWidget);
  });

  testWidgets('activity row expands to show script source', (tester) async {
    events.value = const ClientToolExecuting(
      toolName: 'execute_skill',
      toolCallId: 'tc-1',
    );
    events.value = const ActivitySnapshot(
      messageId: 'bwrap:call_1',
      activityType: 'skill_tool_call',
      content: {
        'tool_name': 'execute_script',
        'args': '{"script":"print(42)"}',
      },
      timestamp: 100,
    );

    await tester.pumpWidget(wrap(ExecutionTimeline(tracker: tracker)));
    await tester.pump();
    await tester.tap(find.text('2 events'));
    await tester.pump();

    expect(find.text('print(42)'), findsNothing);

    await tester.tap(find.text('execute_script'));
    await tester.pump();

    expect(find.text('print(42)'), findsOneWidget);
  });

  testWidgets('activity with no args has no source chevron', (tester) async {
    events.value = const ActivitySnapshot(
      messageId: 'bwrap:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'noop', 'args': '{}'},
      timestamp: 100,
    );

    await tester.pumpWidget(wrap(ExecutionTimeline(tracker: tracker)));
    await tester.pump();
    await tester.tap(find.text('1 event'));
    await tester.pump();

    // Only the header chevron should be visible, not a per-row one.
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('generic args fall back to JSON preview', (tester) async {
    events.value = const ActivitySnapshot(
      messageId: 'rag:call_1',
      activityType: 'skill_tool_call',
      content: {
        'tool_name': 'lookup',
        'args': '{"doc_id":"abc"}',
      },
      timestamp: 100,
    );

    await tester.pumpWidget(wrap(ExecutionTimeline(tracker: tracker)));
    await tester.pump();
    await tester.tap(find.text('1 event'));
    await tester.pump();
    await tester.tap(find.text('lookup'));
    await tester.pump();

    expect(find.textContaining('"doc_id"'), findsOneWidget);
  });

  testWidgets('completed step shows check_circle icon', (tester) async {
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );
    events.value = const ServerToolCallCompleted(
      toolCallId: 'tc-1',
      result: 'ok',
    );

    await tester.pumpWidget(wrap(ExecutionTimeline(tracker: tracker)));
    await tester.pump();
    await tester.tap(find.text('1 event'));
    await tester.pump();

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('orphan activity rendered when no active step', (tester) async {
    events.value = const ActivitySnapshot(
      messageId: 'bwrap:call_1',
      activityType: 'skill_tool_call',
      content: {
        'tool_name': 'execute_script',
        'args': '{"script":"x=1"}',
      },
      timestamp: 100,
    );

    await tester.pumpWidget(wrap(ExecutionTimeline(tracker: tracker)));
    await tester.pump();
    await tester.tap(find.text('1 event'));
    await tester.pump();

    expect(find.text('execute_script'), findsOneWidget);
  });
}
