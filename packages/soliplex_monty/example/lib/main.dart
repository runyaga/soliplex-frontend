import 'package:flutter/widgets.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

/// The Soliplex logo, bundled by soliplex_frontend as a package asset.
final AppIdentity _identity = AppIdentity(
  appName: 'Soliplex',
  logoLight: Image.asset(
    'assets/branding/soliplex/logo_1024.png',
    package: 'soliplex_frontend',
    width: 64,
    height: 64,
  ),
);

/// Boots the standard client with the lab catalog for chat surfaces.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installLogSinks();
  installUncaughtErrorLogging();
  final oauthCallback = CallbackParamsCapture.captureNow();
  clearCallbackUrl();
  await runSoliplexShell(() async {
    final flavor = await standardFlavor(
      identity: _identity,
      callbackParams: oauthCallback,
      surfaceCatalogs: [labCatalog(isLive: ChatSurfaceOrigin.isLive)],
    );
    return flavor.build();
  });
}
