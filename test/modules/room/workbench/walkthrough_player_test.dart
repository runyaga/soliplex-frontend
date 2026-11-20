import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/walkthrough_player.dart';

Map<String, dynamic> step(int n, {String status = 'running'}) => {
      'id': 'tour_test',
      'step': n,
      'status': status,
      'title': 'A chart',
      'text': 'See a chart',
      'delayMs': 5000,
      'effect': 'none',
      'nodes': <String, Object?>{},
    };

void main() {
  testWidgets('fake clock paces one acknowledged step at a time',
      (tester) async {
    final player = WalkthroughPlayer();
    addTearDown(player.dispose);
    final actions = <String>[];
    var effects = 0;
    player.send = (name, _) => actions.add(name);
    player.perform = (_) async {
      effects++;
    };
    player.authorize();
    player.observe(step(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 4999));
    expect(actions, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(actions, ['next']);
    await tester.pump(const Duration(seconds: 6));
    expect(actions, ['next']);
    player.observe(step(1));
    await tester.pump();
    player.observe(step(1));
    player.observe(step(0));
    expect(effects, 2, reason: 'redelivery cannot replay effects');
    await tester.pump(const Duration(seconds: 5));
    expect(actions, ['next', 'next']);
    player.stop();
  });

  testWidgets('visible Stop cancels timers and already queued effects',
      (tester) async {
    final player = WalkthroughPlayer();
    addTearDown(player.dispose);
    final actions = <String>[];
    player.send = (name, _) => actions.add(name);
    player.authorize();
    player.observe(step(0));
    await tester.pumpWidget(MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(body: WalkthroughControls(player: player))));
    await tester.tap(find.text('Stop walkthrough'));
    await tester.pump(const Duration(seconds: 20));
    expect(actions, ['stop']);
    expect(player.active, isFalse);
    player.observe(step(1));
    await tester.pump(const Duration(seconds: 20));
    expect(actions, ['stop']);
  });

  testWidgets('typing a message stops the tour immediately', (tester) async {
    final player = WalkthroughPlayer();
    addTearDown(player.dispose);
    final actions = <String>[];
    player.send = (name, _) => actions.add(name);
    player.authorize();
    player.observe(step(0));
    await tester.pump();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TextField(onChanged: player.draftChanged))));
    await tester.enterText(find.byType(TextField), 'Wait');
    await tester.pump(const Duration(seconds: 10));
    expect(player.active, isFalse);
    expect(actions, ['stop']);
  });

  testWidgets('reload never grants consent or executes any saved step',
      (tester) async {
    final player = WalkthroughPlayer();
    addTearDown(player.dispose);
    var effects = 0;
    player.perform = (_) async {
      effects++;
    };
    player.send = (name, context) => fail('Replay sent an action');
    for (var n = 0; n < 17; n++) {
      player.observe(step(n));
    }
    await tester.pump(const Duration(minutes: 3));
    expect(effects, 0);
    expect(player.active, isFalse);
  });

  testWidgets('Pause Resume and Next preserve pacing', (tester) async {
    final player = WalkthroughPlayer();
    addTearDown(player.dispose);
    final actions = <String>[];
    player.send = (name, _) => actions.add(name);
    player.authorize();
    player.observe(step(0));
    await tester.pump();
    player.togglePause();
    await tester.pump(const Duration(seconds: 10));
    expect(actions, isEmpty);
    player.togglePause();
    await tester.pump(const Duration(seconds: 4));
    expect(actions, isEmpty);
    player.next();
    expect(actions, ['next']);
    player.observe(step(1, status: 'complete'));
    await tester.pump(const Duration(seconds: 30));
    expect(actions, ['next']);
  });
}
