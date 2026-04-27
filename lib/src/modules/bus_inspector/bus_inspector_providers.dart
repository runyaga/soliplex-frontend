import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bus_inspector.dart';

/// Riverpod handle for the app-singleton [BusInspector].
///
/// The default throws — `BusInspectorAppModule` overrides this with
/// the singleton constructed in the flavor entry point. UI surfaces
/// that want to show the bus inspector from outside the inspector
/// route can `ref.watch(busInspectorProvider)`.
final busInspectorProvider = Provider<BusInspector>(
  (_) => throw UnimplementedError('must be overridden by busInspectorModule'),
);
