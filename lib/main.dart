import 'package:flutter/widgets.dart';

import 'package:soliplex_agent_maps/soliplex_agent_maps.dart'
    show MapMontyExtension;
import 'package:soliplex_agent_monty/soliplex_agent_monty.dart';
import 'package:soliplex_frontend/flavors.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_frontend/src/maps_singleton.dart';

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
  final callbackParams = CallbackParamsCapture.captureNow();
  clearCallbackUrl();
  runSoliplexShell(
    await standard(
      callbackParams: callbackParams,
      extraExtensions: () async => [
        if (_montyEnabled)
          MontyRuntimeExtension(
            extensions: MontyExtensionSet([
              ...MontyExtensionSet.standard().all,
              // Python externals to drive the same map the ClientTool
              // surface drives. Shares the singleton MapExtension.
              MapMontyExtension(mapExtension),
            ]),
          ),
        // Singleton instance shared across sessions so the map widget
        // and the LLM-driven controller persist.
        mapExtension,
      ],
    ),
  );
}
