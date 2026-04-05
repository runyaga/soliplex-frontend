import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/ui/chat_input.dart';

void main() {
  testWidgets('send button dispatches text and clears field', (tester) async {
    String? sentText;
    final sessionState = signal<AgentSessionState?>(null);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatInput(
          onSend: (text) => sentText = text,
          onCancel: () {},
          sessionState: sessionState,
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'Hello agent');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sentText, 'Hello agent');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );

    sessionState.dispose();
  });

  testWidgets('send button disabled when text is empty', (tester) async {
    final sessionState = signal<AgentSessionState?>(null);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatInput(
          onSend: (_) {},
          onCancel: () {},
          sessionState: sessionState,
        ),
      ),
    ));

    final sendButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.send),
    );
    expect(sendButton.onPressed, isNull);

    sessionState.dispose();
  });

  testWidgets('shows cancel button when session is running', (tester) async {
    bool cancelCalled = false;
    final sessionState = signal<AgentSessionState?>(AgentSessionState.running);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatInput(
          onSend: (_) {},
          onCancel: () => cancelCalled = true,
          sessionState: sessionState,
        ),
      ),
    ));

    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.byIcon(Icons.send), findsNothing);

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();
    expect(cancelCalled, isTrue);

    sessionState.dispose();
  });

  testWidgets('text field readOnly during active run', (tester) async {
    final sessionState = signal<AgentSessionState?>(AgentSessionState.running);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatInput(
          onSend: (_) {},
          onCancel: () {},
          sessionState: sessionState,
        ),
      ),
    ));

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.readOnly, isTrue);

    sessionState.dispose();
  });

  testWidgets('Enter key sends message', (tester) async {
    String? sentText;
    final sessionState = signal<AgentSessionState?>(null);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatInput(
          onSend: (text) => sentText = text,
          onCancel: () {},
          sessionState: sessionState,
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sentText, 'Hello');

    sessionState.dispose();
  });

  testWidgets('Shift+Enter does not send message', (tester) async {
    String? sentText;
    final sessionState = signal<AgentSessionState?>(null);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatInput(
          onSend: (text) => sentText = text,
          onCancel: () {},
          sessionState: sessionState,
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(sentText, isNull);

    sessionState.dispose();
  });
}
