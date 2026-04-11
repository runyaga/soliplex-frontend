// Standalone JS-compiled demo, not a package:test file.
// ignore_for_file: avoid_print, lines_longer_than_80_chars, avoid_catches_without_on_clauses, discarded_futures, cast_nullable_to_non_nullable, prefer_single_quotes
/// REPL Session Demo with Soliplex + all plugins.
///
/// Build:
///   dart compile js test/integration/repl_session_soliplex_demo.dart \
///     -o test/integration/web/repl_session_soliplex_demo.dart.js
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:dart_monty/dart_monty.dart';
import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:dart_monty/src/bridge/bridge/bridge_event.dart';
import 'package:dart_monty/src/bridge/plugins/message_bus_plugin.dart';
import 'package:dart_monty/src/bridge/plugins/template_plugin.dart';
import 'package:fe_plugin_soliplex/fe_plugin_soliplex.dart';
import 'package:soliplex_client/soliplex_client.dart';

// ---------------------------------------------------------------------------
// JS interop
// ---------------------------------------------------------------------------

@JS('window.ReplDemo')
external set _replDemo(JSObject obj);

@JS('window._onReady')
external void _jsOnReady();

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

late ReplSession _session;

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

Future<String> _apiRun(String code) async {
  try {
    final result = await _session.run(code);
    return jsonEncode(_resultToJson(result));
  } catch (e) {
    return jsonEncode({'ok': false, 'error': e.toString()});
  }
}

Future<String> _apiReset() async {
  try {
    await _session.dispose();
    _createSession();
    return jsonEncode({'ok': true});
  } catch (e) {
    return jsonEncode({'ok': false, 'error': e.toString()});
  }
}

// ---------------------------------------------------------------------------
// Session factory
// ---------------------------------------------------------------------------

void _createSession() {
  final demoTransport = HttpTransport(client: DartHttpClient());
  final demoUrl = UrlBuilder('https://demo.toughserv.com/api/v1');

  final localTransport = HttpTransport(client: DartHttpClient());
  final localUrl = UrlBuilder('http://localhost:8000/api/v1');

  final soliplex = SoliplexPlugin(connections: {
    'demo': SoliplexConnection(
      api: SoliplexApi(transport: demoTransport, urlBuilder: demoUrl),
      streamClient: AgUiStreamClient(
        httpTransport: demoTransport,
        urlBuilder: demoUrl,
      ),
    ),
    'local': SoliplexConnection(
      api: SoliplexApi(transport: localTransport, urlBuilder: localUrl),
      streamClient: AgUiStreamClient(
        httpTransport: localTransport,
        urlBuilder: localUrl,
      ),
    ),
  });

  final tmpl = DinjaTemplatePlugin();
  final msgBus = MessageBusPlugin();

  _session = ReplSession(
    plugins: [soliplex, tmpl, msgBus],
  );
}

// ---------------------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> _resultToJson(MontyResult result) {
  if (result.isError) {
    return {
      'ok': false,
      'error': result.error?.message ?? 'Unknown error',
      'print_output': result.printOutput,
    };
  }
  return {
    'ok': true,
    'value': result.value?.dartValue,
    'print_output': result.printOutput,
  };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

Future<void> main() async {
  print('[ReplDemo+Soliplex] Starting...');

  _createSession();

  final api = <String, JSFunction>{
    'run': ((JSString code) =>
            _apiRun(code.toDart).then((r) => r.toJS).toJS)
        .toJS,
    'reset': (() => _apiReset().then((r) => r.toJS).toJS).toJS,
  }.jsify();
  _replDemo = api as JSObject;

  print('[ReplDemo+Soliplex] API exposed on window.ReplDemo');

  try {
    _jsOnReady();
  } catch (_) {
    print('[ReplDemo+Soliplex] Ready (no _onReady callback)');
  }
}
