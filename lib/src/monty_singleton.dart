/// Factory for the app's standard [MontyExtensionSet].
///
/// Returns a **fresh** set on every call. This is required because each
/// [MontyRuntime] takes lifecycle ownership of its extension list and
/// disposes them — the same extension instances cannot be shared across
/// multiple runtimes (e.g. a session-attached runtime AND a terminal
/// dialog runtime would both try to dispose the same `EventLoopExtension`,
/// and whichever runs second would fail with "Cannot execute on a
/// disposed EventLoopExtension").
///
/// Used by:
/// - Session-attached [MontyRuntimeExtension] (LLM tool path) — fresh per session
/// - Terminal panel (direct user-pasted code path) — fresh per dialog open
///
/// The map externals always reference the same [mapExtension] singleton,
/// so Python code from any caller drives the same on-screen map even
/// though each [MapMontyExtension] wrapper is itself fresh.
///
/// Lives only when `MONTY_ENABLED=true`; never imported with the flag off.
library;

import 'package:soliplex_agent_maps/soliplex_agent_maps.dart'
    show MapMontyExtension;
import 'package:soliplex_agent_monty/soliplex_agent_monty.dart'
    show MontyExtensionSet;

import 'http_monty_extension.dart';
import 'maps_singleton.dart';

/// Constructs a fresh [MontyExtensionSet] for a single [MontyRuntime].
///
/// Narration host functions are no longer registered here — `NarrationPlugin`
/// declares them via `hostFunctions` and the bridge in
/// `soliplex_agent_monty` (Phase 2 step 9) synthesizes the corresponding
/// `MontyExtension` automatically at session attach.
MontyExtensionSet makeMontyExtensionSet() => MontyExtensionSet([
      ...MontyExtensionSet.standard().all,
      MapMontyExtension(mapExtension),
      HttpMontyExtension(),
    ]);
