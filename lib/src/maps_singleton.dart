import 'package:soliplex_agent_maps/soliplex_agent_maps.dart';

/// App-level singleton `MapExtension`. Constructed once at startup and
/// returned from `extraExtensions` for every session, so the underlying
/// `MapController` and reactive state survive session boundaries. Both
/// `lib/main.dart` and `lib/src/modules/room/ui/room_screen.dart`
/// import this to share the same instance.
///
/// This is the v0 wiring described in
/// `docs/plans/message-containers.md`. v1 will replace it with a typed
/// container registry; for now this single global keeps the demo
/// scope small.
final MapExtension mapExtension = MapExtension();
