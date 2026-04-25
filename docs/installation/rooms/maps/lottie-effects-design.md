# Lottie Effect Animations — Integration Design

Status: design proposal, not yet implemented. Targets `packages/soliplex_agent_maps`.

## 1. Why Lottie at all

Image overlays already cover "drop a sprite at lat/lng" via `Marker(child: Image.network)`, including animated GIFs (`gaplessPlayback: true`) — fine for helicopters, vehicles, and looping stickers. Lottie complements GIFs for short-lived *effect* animations: explosions, smoke, muzzle flashes, radar sweeps, sparkles, fireworks. Vector-clean at any zoom and rotation, typically 5–30 KB JSON vs 200 KB–2 MB GIFs, alpha-clean (no fringing on map tiles), and cheaply tintable. Lottie is the right shape for "play an FX once at this coordinate, then disappear"; image overlays remain the right shape for "this sprite lives here".

## 2. Package

- `lottie: ^3.0.0` from pub.dev — MIT licensed (xvrh fork).
- No API keys, no native deps, Flutter Web compatible (renders via Skia/CanvasKit).
- JSON sources: [lottiefiles.com](https://lottiefiles.com) (most clips CC0 or "free with attribution") or custom After Effects exports via Bodymovin. Vet a small set and either bundle them under `packages/soliplex_agent_maps/assets/lottie/` or pin specific CDN URLs in the built-in registry.

## 3. Data shape

Parallel to `ImageOverlayData`:

```dart
@immutable
class LottieEffectData {
  final String id;
  final String url;          // network URL or 'asset:packages/.../foo.json'
  final double lat;
  final double lng;
  final double widthPx;
  final double heightPx;
  final bool loop;           // default false for effects, true for ambient
  final int? durationMs;     // null -> use the file's intrinsic duration
  final int? playCount;      // null + loop=true -> infinite; null + loop=false -> 1
  final double opacity;
  final double rotation;
  final int? createdAtMs;    // wall-clock so the renderer can auto-remove
}
```

Lives in `map_state.dart` next to `ImageOverlayData`. Mirrors `copyWith` / `toJson` conventions.

## 4. Render shape

Inside `map_view.dart`, add a `MarkerLayer` block alongside the existing image-overlay layer:

```dart
if (effects.isNotEmpty)
  MarkerLayer(
    markers: [
      for (final fx in effects)
        Marker(
          key: ValueKey('lottie:${fx.id}'),
          point: LatLng(fx.lat, fx.lng),
          width: fx.widthPx,
          height: fx.heightPx,
          alignment: Alignment.center,
          child: LottieBuilder.network(
            fx.url,
            repeat: fx.loop,
            // duration override + onLoaded -> auto-remove for one-shots
          ),
        ),
    ],
  ),
```

Asset URLs (`asset:...`) route through `LottieBuilder.asset`. The widget owns its own `AnimationController`; when the entry leaves the `_effects` signal it unmounts and disposes naturally.

## 5. Python tool surface

Two functions registered by `MapMontyExtension`:

- **`map_play_effect(name, lat, lng, duration_ms=None, width=96, height=96)`** — pick from a built-in registry: `explosion`, `smoke`, `fire`, `muzzle_flash`, `radar_sweep`, `beacon`, `fireworks`, `rain`, `sparkle`. Each name maps to a vetted LottieFiles URL or bundled asset. One-shot by default.
- **`map_add_lottie(url, lat, lng, loop=True, width=96, height=96, duration_ms=None, play_count=None)`** — escape hatch for any Lottie JSON URL. Persistent by default. Returns the id so Python can call `map_remove_lottie(id)` later.

Both live under the `map_` namespace alongside `map_add_image`. `map_play_effect` is the only one likely worth exposing as an `LlmCallable` directly, since its registry is small enough to enumerate in the description.

## 6. One-shot vs persistent

- `map_play_effect` defaults to *one-shot*: `loop=false`, `play_count=1`. The renderer auto-removes the entry from `_effects` once `durationMs` (or the file's intrinsic duration) elapses, scheduled via a `Timer` keyed on `createdAtMs`.
- `map_add_lottie` defaults to *persistent*: `loop=true`, no auto-remove. Lives until `map_remove_lottie(id)` or `map_clear_markers()` (which should also clear `_effects` for symmetry with image overlays).

Either default can be overridden — `map_play_effect("beacon", lat, lng, duration_ms=0)` keeps a beacon indefinitely; `map_add_lottie(url, lat, lng, loop=False)` does a custom one-shot.

## 7. Implementation steps

1. Add `lottie: ^3.0.0` to `packages/soliplex_agent_maps/pubspec.yaml`; run `pub get`.
2. Add `LottieEffectData` to `lib/src/map_state.dart`, mirroring `ImageOverlayData` (immutable, `copyWith`, `toJson`).
3. In `lib/src/map_extension.dart`, add `_effects` signal, typed `addLottie` / `playEffect` / `removeLottie` methods, and a `_effectsRegistry` map. Include `effectCount` in aggregated `state`. One-shot auto-remove uses `Future.delayed` guarded by a generation token so `clearAll()` cancels pending removals.
4. In `lib/src/map_view.dart`, add a `MarkerLayer` for `_effects` after `PolylineLayer` and before the pin `MarkerLayer`. Watch via `extension.effects.watch(context)`.
5. In `lib/src/map_monty_extension.dart`, register the two `HostFunction`s and extend `systemPromptContext`.

## 8. Risks / open questions

- **Web bundle size** — `lottie` adds ~140 KB min+gzip. Measure against the `MONTY_ENABLED` budget; gate behind `MAPS_LOTTIE_ENABLED` if tight.
- **CORS on remote JSON** — LottieFiles' CDN is permissive; third-party hosts may not be. `errorBuilder` should fall back to a material icon (e.g. `Icons.flash_on`) so a failed fetch isn't invisible.
- **Concurrent effects perf** — each `LottieBuilder` runs its own `AnimationController`. 50+ simultaneous effects on CanvasKit can drop frames. Mitigations: cap `_effects` length (~32, evict oldest), share cached `LottieComposition` for named effects, document the cap.
- **Attribution** — some LottieFiles clips require it. Bundle JSON and list authors in `LICENSE-3RD-PARTY.md` or a `lottie_attributions.dart` constant; one-time curation cost.
- **Asset vs network** — ship the registry as bundled assets (deterministic, offline-capable, no CORS surprises); reserve network URLs for `map_add_lottie`. Revisit once stable.
