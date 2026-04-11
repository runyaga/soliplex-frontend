// ignore_for_file: avoid_print
/// Shared setup for the 50+ experiment suite.
///
/// Each experiment file imports this and calls [Lab.start] to get a session
/// with all plugins wired to both servers (demo + local).
///
/// Usage:
///   import 'exp_helpers.dart';
///   Future<void> main() async {
///     final lab = Lab.start();  // or Lab.start(withSandbox: true)
///     await lab.run('Title', 'Observation', (s) async { ... });
///     await lab.close();
///   }
library;

import 'package:dart_monty/dart_monty.dart';
import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:dart_monty/dart_monty_ffi.dart';
import 'package:fe_plugin_soliplex/fe_plugin_soliplex.dart';
import 'package:soliplex_client/soliplex_client.dart';

export 'package:dart_monty/dart_monty.dart' show MontyResult, MontyValue;
export 'package:dart_monty/dart_monty_bridge.dart' hide ToolCall;
export 'package:fe_plugin_soliplex/fe_plugin_soliplex.dart';
export 'package:soliplex_client/soliplex_client.dart';

/// Central experiment harness.
///
/// [start] builds an [AgentSession] with SoliplexPlugin (demo + local),
/// DinjaTemplatePlugin, MessageBusPlugin, and optionally SandboxPlugin.
class Lab {
  Lab._({
    required this.session,
    required this.demoTransport,
    required this.localTransport,
    required int startNum,
  }) : _expNum = startNum - 1;

  final AgentSession session;
  final HttpTransport demoTransport;
  final HttpTransport localTransport;
  int _expNum;
  int _passed = 0;
  int _failed = 0;
  int _errors = 0;

  /// Build a fully-wired lab session.
  ///
  /// Default server URLs, overridable via environment variables:
  /// - `SOLIPLEX_DEMO_URL` (default: `https://demo.toughserv.com/api/v1`)
  /// - `SOLIPLEX_LOCAL_URL` (default: `http://localhost:8000/api/v1`)
  static const _defaultDemoUrl = 'https://demo.toughserv.com/api/v1';
  static const _defaultLocalUrl = 'http://localhost:8000/api/v1';

  /// [withSandbox] adds [SandboxPlugin] with [MontyFfi] platform factory.
  /// [startNum] offsets experiment numbering (default 1).
  static Lab start({bool withSandbox = false, int startNum = 1}) {
    final demoTransport = HttpTransport(client: DartHttpClient());
    final localTransport = HttpTransport(client: DartHttpClient());
    final demoUrl = UrlBuilder(
      const String.fromEnvironment(
        'SOLIPLEX_DEMO_URL',
        defaultValue: _defaultDemoUrl,
      ),
    );
    final localUrl = UrlBuilder(
      const String.fromEnvironment(
        'SOLIPLEX_LOCAL_URL',
        defaultValue: _defaultLocalUrl,
      ),
    );

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

    final msgBus = MessageBusPlugin();
    final tmpl = DinjaTemplatePlugin();

    final plugins = <MontyPlugin>[soliplex, msgBus, tmpl];

    if (withSandbox) {
      plugins.add(SandboxPlugin(
        platformFactory: () async => MontyFfi(),
        parentPlugins: [soliplex, msgBus, tmpl],
        maxChildren: 16,
        maxDepth: 3,
      ));
    }

    final session = AgentSession(
      sandbox: true,
      os: OsProvider.compose({
        'Path.': MemoryFsProvider(),
        'date.': TimeOsProvider(),
        'os.': EnvOsProvider({
          'EXPERIMENT': '1',
          'SERVER_DEMO': 'demo.toughserv.com',
          'SERVER_LOCAL': 'localhost:8000',
        }),
      }),
      plugins: plugins,
    );

    return Lab._(
      session: session,
      demoTransport: demoTransport,
      localTransport: localTransport,
      startNum: startNum,
    );
  }

  /// Run a single experiment with formatted output.
  Future<void> run(
    String title,
    String observation,
    Future<void> Function(AgentSession s) body,
  ) async {
    _expNum++;
    final n = _expNum.toString().padLeft(2, '0');
    print('');
    print('${"=" * 70}');
    print('EXP $n: $title');
    print('${"=" * 70}');
    print('OBSERVATION: $observation');
    print('');
    try {
      await body(session);
      _passed++;
    } on Exception catch (e, st) {
      _errors++;
      print('  RESULT: ERROR (unhandled exception)');
      print('  EVIDENCE: $e');
      print('  ${st.toString().split('\n').take(5).join('\n  ')}');
    }
  }

  /// Print a summary and close all resources.
  Future<void> close() async {
    print('');
    print('${"=" * 70}');
    print('SUITE COMPLETE — passed: $_passed, failed: $_failed, '
        'errors: $_errors, total: ${_passed + _failed + _errors}');
    print('${"=" * 70}');
    await session.dispose();
    demoTransport.close();
    localTransport.close();
  }
}

// ---------------------------------------------------------------------------
// Result helpers
// ---------------------------------------------------------------------------

/// Check a [MontyResult] and print formatted output.
///
/// Returns `true` if the result was a success (no error).
bool check(MontyResult r, {String? label}) {
  final pfx = label != null ? '  [$label] ' : '  ';
  if (r.error != null) {
    print('${pfx}RESULT: FAIL — ${r.error!.excType}: ${r.error!.message}');
    if (r.error!.lineNumber != null) {
      print('$pfx  Line: ${r.error!.lineNumber}');
    }
    if (r.printOutput?.isNotEmpty ?? false) {
      print('${pfx}STDOUT: ${trunc(r.printOutput!, 200)}');
    }
    return false;
  }
  print('${pfx}RESULT: PASS — ${trunc('${r.value?.dartValue}', 400)}');
  if (r.printOutput?.isNotEmpty ?? false) {
    print('${pfx}STDOUT: ${trunc(r.printOutput!, 200)}');
  }
  return true;
}

/// Truncate [s] to [max] characters.
String trunc(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}...';

/// Escape a string for embedding inside a Python single-quoted string.
String pyEsc(String s) =>
    s.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('\n', '\\n');

/// Escape content for embedding inside Python triple-quoted string (''').
String pyTripleEsc(String s) =>
    s.replaceAll('\\', '\\\\').replaceAll("'''", "\\'\\'\\'");
