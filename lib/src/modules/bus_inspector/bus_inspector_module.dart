import 'package:go_router/go_router.dart';

import '../../core/app_module.dart';
import 'bus_inspector.dart';
import 'bus_inspector_providers.dart';
import 'ui/bus_inspector_screen.dart';

/// Mounts the bus inspector route at `/diagnostics/bus`, alongside
/// the existing `/diagnostics/network` route exposed by
/// `DiagnosticsAppModule`.
class BusInspectorAppModule extends AppModule {
  BusInspectorAppModule({required this.inspector});

  final BusInspector inspector;

  @override
  String get namespace => 'bus_inspector';

  @override
  ModuleRoutes build() => ModuleRoutes(
        overrides: [busInspectorProvider.overrideWithValue(inspector)],
        routes: [
          GoRoute(
            path: '/diagnostics/bus',
            builder: (context, state) =>
                BusInspectorScreen(inspector: inspector),
          ),
        ],
      );

  @override
  Future<void> onDispose() async => inspector.dispose();
}
