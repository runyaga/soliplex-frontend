/// Bridge between `soliplex_agent` and `flutter_map`.
///
/// Wraps a long-lived `MapController` in a `MapExtension` so an LLM can
/// drive a live, visible map via `ClientTool`s — fly the camera, drop
/// pins, draw polylines/polygons, run a guided tour — and observe the
/// current viewport via the extension's reactive state signal. Pair with
/// the `MapView` widget anywhere in the host app to render the map.
library;

export 'src/map_extension.dart';
export 'src/map_monty_extension.dart';
export 'src/map_state.dart';
export 'src/map_view.dart';
