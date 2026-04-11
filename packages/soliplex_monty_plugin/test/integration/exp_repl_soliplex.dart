// ignore_for_file: avoid_print
/// REPL + SoliplexPlugin integration test.
///
/// Uses ReplSession instead of AgentSession — proves that the native
/// Rust REPL with persistent heap works with real Soliplex server calls.
///
/// Run: dart test test/integration/exp_repl_soliplex.dart
library;

import 'package:dart_monty/dart_monty.dart';
import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:fe_plugin_soliplex/fe_plugin_soliplex.dart';
import 'package:soliplex_client/soliplex_client.dart';

Future<void> main() async {
  print('=== REPL + SoliplexPlugin Integration ===\n');

  // Setup connections
  final demoTransport = HttpTransport(client: DartHttpClient());
  final demoUrl = UrlBuilder('https://demo.toughserv.com/api/v1');

  final soliplex = SoliplexPlugin(connections: {
    'demo': SoliplexConnection(
      api: SoliplexApi(transport: demoTransport, urlBuilder: demoUrl),
      streamClient: AgUiStreamClient(
        httpTransport: demoTransport,
        urlBuilder: demoUrl,
      ),
    ),
  });

  final tmpl = DinjaTemplatePlugin();
  final msgBus = MessageBusPlugin();

  // Create ReplSession with real plugins
  final session = ReplSession(
    plugins: [soliplex, tmpl, msgBus],
  );

  var passed = 0;
  var failed = 0;

  Future<void> exp(String name, Future<void> Function() body) async {
    try {
      await body();
      passed++;
      print('  PASS: $name');
    } catch (e) {
      failed++;
      print('  FAIL: $name — $e');
    }
  }

  // --- Experiment 1: List servers ---
  await exp('list_servers', () async {
    final r = await session.run("soliplex_list_servers()");
    print('    servers: ${r.value}');
    assert(r.value != null, 'should return server list');
  });

  // --- Experiment 2: List rooms ---
  await exp('list_rooms', () async {
    final r = await session.run("soliplex_list_rooms('demo')");
    print('    rooms: ${r.value}');
    assert(r.value != null, 'should return room list');
  });

  // --- Experiment 3: State persists — store servers, use in next call ---
  await exp('state_persists', () async {
    await session.run("servers = soliplex_list_servers()");
    final r = await session.run("type(servers)");
    print('    type: ${r.value}');
  });

  // --- Experiment 4: Store rooms, use in template ---
  await exp('rooms_to_template', () async {
    await session.run("rooms = soliplex_list_rooms('demo')");
    final r = await session.run(
      "tmpl_render(template='Found {{ n }} rooms', context={'n': len(rooms)})",
    );
    print('    rendered: ${r.value}');
    assert(r.value != null, 'should render template');
  });

  // --- Experiment 5: Get room details ---
  await exp('get_room', () async {
    await session.run("rooms = soliplex_list_rooms('demo')");
    await session.run("import json");
    // rooms is a JSON string, parse it
    await session.run("room_list = json.loads(rooms)");
    final r = await session.run("len(room_list)");
    print('    room_count: ${r.value}');
  });

  // --- Experiment 6: New thread (real SSE conversation) ---
  await exp('new_thread', () async {
    // Get first room
    await session.run("rooms_json = soliplex_list_rooms('demo')");
    await session.run("import json");
    await session.run("all_rooms = json.loads(rooms_json)");
    await session.run("room_id = all_rooms[0]['id']");

    final r = await session.run(
      "result = soliplex_new_thread('demo', room_id, 'Hello! What documents do you have?')",
    );
    print('    result: ${r.value}');
  });

  // --- Experiment 7: Reply to thread ---
  await exp('reply_thread', () async {
    await session.run("import json");
    await session.run("parsed = json.loads(result)");
    await session.run("tid = parsed['thread_id']");

    final r = await session.run(
      "reply = soliplex_reply_thread('demo', room_id, tid, 'Tell me more about the first document.')",
    );
    print('    reply: ${r.value}');
  });

  // --- Experiment 8: Mix msg_bus + soliplex ---
  await exp('cross_plugin', () async {
    await session.run("msg_send('log', 'started soliplex test')");
    await session.run("servers = soliplex_list_servers()");
    await session.run("msg_send('log', servers)");
    final r = await session.run("msg_recv('log')");
    print('    log msg: ${r.value}');
  });

  // --- Experiment 9: Template with soliplex data ---
  await exp('template_with_data', () async {
    final r = await session.run(
      "tmpl_render(template='Talked to room {{ rid }}', context={'rid': room_id})",
    );
    print('    rendered: ${r.value}');
  });

  // --- Experiment 10: Error handling ---
  await exp('error_handling', () async {
    final r = await session.run(
      "try:\n    soliplex_list_rooms('nonexistent')\nexcept Exception as e:\n    err = str(e)\nerr",
    );
    print('    error: ${r.value}');
  });

  print('\n=== Results: $passed passed, $failed failed ===');

  await session.dispose();
  demoTransport.close();
}
