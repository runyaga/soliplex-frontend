import 'package:flutter/widgets.dart';

import 'package:soliplex_agent_maps/soliplex_agent_maps.dart' show MapPlugin;
import 'package:soliplex_agent_monty/soliplex_agent_monty.dart';
import 'package:soliplex_agent_widgets/soliplex_agent_widgets.dart'
    show NarrationPlugin;
import 'package:soliplex_frontend/flavors.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_frontend/src/maps_singleton.dart';
import 'package:soliplex_frontend/src/monty_singleton.dart';

/// Compile-time flag gating the on-device Python runtime.
///
/// Build the monty-enabled variant with:
///
/// ```sh
/// flutter build macos --dart-define=MONTY_ENABLED=true
/// ```
///
/// When `false` (default), `MontyRuntimeExtension` is never constructed
/// and the `dart_monty` bytes tree-shake out of the release binary.
const _montyEnabled = bool.fromEnvironment(
  'MONTY_ENABLED',
  // ignore: avoid_redundant_argument_values
  defaultValue: false,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: avoid_print
  print('[boot] MONTY_ENABLED=$_montyEnabled');
  final callbackParams = CallbackParamsCapture.captureNow();
  clearCallbackUrl();
  runSoliplexShell(
    await standard(
      callbackParams: callbackParams,
      extraExtensions: () async => [
        if (_montyEnabled)
          MontyRuntimeExtension(extensions: makeMontyExtensionSet()),
        // Singleton instance shared across sessions so the map widget
        // and the LLM-driven controller persist.
        mapExtension,
        // Phase 1 step 4b/5 — bus-write plugins. Each declares LLM
        // tools (narrate_say; set_site / clear_sites / move_convoy_to)
        // whose executors write the per-thread StateBus. Existing
        // projections pick the writes up and forward them into the
        // singleton render targets. See
        // docs/plans/reactive-bus-redesign.md.
        NarrationPlugin(),
        MapPlugin(),
      ],
    ),
  );
}
