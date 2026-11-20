import 'package:flutter/widgets.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_monty_app/workbench_catalogs.dart';

final Set<String> _workbenchRooms =
    const String.fromEnvironment(
          'WORKBENCH_ROOMS',
        )
        .split(',')
        .map((room) => room.trim())
        .where((room) => room.isNotEmpty)
        .toSet();

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

/// Boots the workbench client with the lab catalog for chat surfaces.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installLogSinks();
  installUncaughtErrorLogging();
  final oauthCallback = CallbackParamsCapture.captureNow();
  clearCallbackUrl();
  await runSoliplexShell(() async {
    final flavor = await workbenchFlavor(
      identity: _identity,
      callbackParams: oauthCallback,
      surfaceCatalogs: workbenchCatalogs(isLive: ChatSurfaceOrigin.isLive),
      presentation: WorkbenchRoomAllowlistPresentation(
        rooms: _workbenchRooms,
        host: const ClientWorkbenchPresentation(),
      ),
    );
    return flavor.build();
  });
}
