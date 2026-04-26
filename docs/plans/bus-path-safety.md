# Bus path safety — design space

## 1. Problem statement

The v1 bus (`packages/soliplex_client/lib/src/application/state_bus.dart`)
stores `Map<String, dynamic>` and (per the redesign plan) accepts
writes as RFC 6902 JSON Patch operations addressed by string paths
like `/ui/map/markers/-`. Internal JSON shape is settled for v1 —
wire-format compatibility with AG-UI `StateSnapshotEvent` /
`StateDeltaEvent` is the load-bearing constraint. The gap:
client-authored paths (`MapPlugin`, `NarrationPlugin`, future plugins)
are typo-prone strings whose failures surface at runtime when
`_setAtPath` traverses the document and silently no-ops or logs at
level 900. Server-emitted paths cannot be type-checked client-side and
are out of scope. Reads already type-safe via `StateProjection`
returning typed values; the asymmetry is on writes. We want
compile-time safety on client-authored paths *if the cost-benefit
makes sense* — and we should not pretend that's a solved problem in
Dart.

## 2. Approach evaluations

### 2.1 Constants for paths

```dart
abstract final class BusPaths {
  static const uiMapMarkers = '/ui/map/markers';
  static const uiMapMarkersAppend = '/ui/map/markers/-';
  static const uiHudBanner = '/ui/hud/status_banner';
}
bus.applyDelta([JsonPatchOp.add(BusPaths.uiMapMarkersAppend, marker)]);
```

**Pipeline**: compile-time deduplication; runtime semantics unchanged.
**Ergonomics**: trivial — autocomplete on `BusPaths.`, jump-to-definition shows every path. Zero learning curve.
**Coverage**: catches transcription typos *at the call site* (`BusPaths.uiMapMarkrs` is a compile error). Does **not** catch (a) typos in the constant value itself (only one place to get wrong, but a typo there propagates everywhere), (b) type mismatches at the leaf (constants are `String`, no leaf-type info), (c) structural mistakes (using an array `add` on a non-list path).
**Cost**: ~50 LOC for an exhaustive enum-like file. Zero deps. ~5 min/path to add.
**Compatibility**: zero changes to v1; pure addition. Coexists with raw strings during migration.
**Verdict**: 80% of the typo problem solved at 5% of the cost of anything else. Honest baseline.

### 2.2 Path builder DSL

```dart
final op = BusPath.ui.map.markers.append(marker); // returns JsonPatchOp
final op2 = BusPath.ui.hud.statusBanner.replace('warning');
```

**Pipeline**: compile-time. Each `.foo` is a getter on a typed builder; typos are method-not-found errors.
**Ergonomics**: high once authored — fluent, IDE-discoverable. Adds an authoring tax: someone has to write `MapPathBuilder`, `HudPathBuilder`, etc., and keep them in sync with the projection-side reader code (a problem already present with the constant approach).
**Coverage**: catches typos and *can* catch leaf-type mismatches (typed terminal: `markers.append(MarkerData m)` rejects strings). Can encode structural awareness (array-typed nodes expose `append`/`insertAt`, map-typed nodes don't). Strongest of the lightweight options.
**Cost**: ~30–60 LOC per plugin's path tree, hand-written. Pattern is uniform; could be templated. No deps.
**Compatibility**: layers on top of `applyDelta(List<JsonPatchOp>)`. The builder returns a `JsonPatchOp`; the bus accepts the op as before. Zero internal changes.
**Verdict**: best ergonomics-per-LOC for plugin-author authored paths. Recommend pairing with 2.1 (constants for ad-hoc cases the builder doesn't model).

### 2.3 Lenses / functional optics

A `Lens<S, A>` is a `(S → A, S → A → S)` pair. Composed lenses give a
typed pointer into nested structure. Pub.dev has `lens` (3 likes, last
update 2021), `optics_dart` (8 likes, dormant). There is no actively
maintained, production-grade Dart optics library.

**Pipeline**: compile-time via type composition.
**Ergonomics**: poor for this use case. Lenses excel over **typed** state trees (think Redux + TypeScript Immer); they don't naturally bridge `Map<String, dynamic>` because there's no static type to compose against. You'd be writing lenses against a phantom typed model that doesn't exist at runtime — duplicating the projection-side reader logic.
**Coverage**: full structural + leaf-type if the typed model is real. But the typed model isn't real in v1; constraint 1 ("bus stays JSON-shape") explicitly rules it out.
**Cost**: high. Either adopt a dormant package (risk) or hand-roll. Plus, if the typed model existed we wouldn't have the path problem in the first place.
**Compatibility**: poor. Lenses presuppose the architecture we explicitly didn't pick.
**Verdict**: wrong tool. Lenses are the right answer in a world where state is statically typed; v1 commits to dynamic state for AG-UI compatibility.

### 2.4 Phantom types on path values

```dart
final class JsonPath<T> {
  final String path;
  const JsonPath(this.path);
}
const markersAppend = JsonPath<MarkerData>('/ui/map/markers/-');
JsonPatchOp.add<T>(JsonPath<T> path, T value); // type-checked
```

**Pipeline**: compile-time on the value side; the path string itself is still authored by hand.
**Ergonomics**: a small upgrade over 2.1 — leaf-type checks at write site. `JsonPatchOp.add(markersAppend, "wrong")` is a compile error.
**Coverage**: catches leaf-type mismatches (the actual original-poster pain when a refactor changes `MarkerData`'s shape). Does **not** catch path-string typos in the const declaration. Doesn't model array-vs-map structural distinctions unless you split the type (`JsonPath<T>` vs `JsonArrayPath<T>`).
**Cost**: ~30 LOC (`JsonPath`, generic `JsonPatchOp.add/replace/remove`). Trivial.
**Compatibility**: layers cleanly. Constants from 2.1 become `JsonPath<T>` constants for free.
**Verdict**: cheap multiplier on 2.1. Worth doing alongside.

### 2.5 Code generation from state schema

Define schema once (Dart classes or YAML), `build_runner` emits typed
path constants + typed write helpers. Pattern proven by `freezed`,
`json_serializable`.

**Pipeline**: build-time codegen; compile-time on emitted output.
**Ergonomics**: best when it works — schema is single source of truth. Authoring tax is real: schema lives in one place, evolves with the agent server, and codegen must run on every CI and dev-laptop checkout. `build_runner` adds 2–10s to every cold build; soliplex doesn't currently use it (no `freezed`/`json_serializable`).
**Coverage**: full when schema is honest. Catches typos, leaf-types, structural mistakes. Risk: schema drift from server reality (server-side AG-UI emits whatever it emits; the schema is a client-side fiction).
**Cost**: high. Designing the schema syntax, writing the generator, integrating `build_runner`, training contributors. Easily a 3–5 day investment for the generator alone.
**Compatibility**: requires schema discipline soliplex doesn't have today. The plan's "Bus schema validation at applyDelta boundary" follow-on is the runtime cousin of this; the static + runtime story should land together if it lands at all.
**Verdict**: heaviest weight, highest ceiling. Premature for v1. Reasonable if/when AG-UI schema stabilizes and multi-team contribution emerges.

### 2.6 Hybrid: plugin-owned paths with typed write methods

```dart
class MapPlugin extends SessionExtension {
  void addMarker(MarkerData m) =>
    bus.applyDelta([JsonPatchOp.add('/ui/map/markers/-', m.toJson())]);
}
mapPlugin.addMarker(marker); // callers never see paths
```

**Pipeline**: compile-time on the public API; path strings live exactly once, inside the plugin that owns the path's namespace.
**Ergonomics**: best for downstream consumers — they call typed methods, never strings. Plugin author still hand-writes the path once. Aligns with the redesign's existing "plugin-owned" architecture (each `SessionExtension` already owns its slice of state).
**Coverage**: typos in the plugin internal call are still possible but localized to one file with a sharply narrowed surface area. Leaf-type checked by method signature. Structural correctness becomes the plugin author's contract test.
**Cost**: low. Folds into the existing `MapPlugin`/`NarrationPlugin` shape the plan already describes. Zero new abstractions; one method per logical write.
**Compatibility**: the redesign **already implies this** — Phase 1 step 4 makes `NarrationController` read-only and routes writes through `NarrationPlugin`; step 5 same for `MapPlugin`. The path-safety question is "what's the surface inside the plugin" — and the answer is "as small as we want."
**Verdict**: this is the architecturally-aligned answer. The path-safety question collapses to "give plugins typed write methods (which the redesign was going to do anyway), and stop pretending downstream code should see paths at all."

### 2.7 Annotation + custom_lint rule

```dart
@BusPath('/ui/map/markers/-')
void addMarker(MarkerData m) { /* ... */ }
```

A custom lint validates `@BusPath` arguments against a schema declared
elsewhere (YAML, Dart const map, etc.). The plan already commits to
`custom_lint` (Enforcement layer 3 in the redesign).

**Pipeline**: lint-time, surfaced in IDE on save and in CI. Not strictly compile-time but earlier than runtime.
**Ergonomics**: invisible until violated. Authoring an annotation is one extra line.
**Coverage**: catches typos against whatever schema is the source of truth — and we don't have one. Without a schema this devolves into 2.1 with extra steps.
**Cost**: medium (writing the lint rule), plus all the schema-maintenance cost from 2.5.
**Compatibility**: piggybacks on existing custom_lint infrastructure.
**Verdict**: only worth it once a schema exists for other reasons (runtime validation, server contract testing). On its own, doesn't earn its keep.

### 2.8 Considered and rejected

- **Dart macros** — preview as of 2026, not production-stable. Ruled out.
- **Existing pub packages** (`json_patch` 0.4.x, `json_pointer`) — runtime-only utilities; no compile-time path machinery exists in the Dart ecosystem at the time of writing.
- **External DSL** (a tiny path-parser as a generator input) — same drawbacks as 2.5 plus a parser.

## 3. Recommendation

**Layer three things, all small. Skip the heavy machinery.**

1. **Adopt 2.6 (plugin-owned typed write methods) as the architectural answer.** The redesign already does this implicitly — make it explicit. Plugin classes (`MapPlugin`, `NarrationPlugin`, `ExecutionStepsPlugin`) expose typed methods (`addMarker`, `appendNarration`, `recordStep`); paths live inside the plugin file and nowhere else. Downstream code never types a path. This collapses 80% of the typo surface for free.

2. **Adopt 2.1 + 2.4 (typed `JsonPath<T>` constants)** *inside* each plugin for the residual paths. ~40 LOC of infrastructure, ~5 min per path. Catches typos at call sites within the plugin and adds leaf-type checks via phantom generic.

3. **Defer 2.5 / 2.7 (codegen + schema lint).** The honest answer for v1: the cost-benefit doesn't justify it yet. Revisit when (a) the AG-UI server schema stabilizes such that a client-side schema isn't immediately stale, *and* (b) a non-trivial number of plugins (>5) exist whose path collisions justify centralizing. Until then, the plan's "Bus schema validation at applyDelta boundary" runtime follow-on covers the remaining gap with logging — typos still surface, just not at compile time, and the projection layer's structural defensiveness (every projection already does `if (ui is! Map) return const [];`) means a typo'd write produces an empty projection, not a crash.

**Be explicit about the limit.** Compile-time safety on derived
structural paths in Dart is genuinely hard because the underlying
state is `Map<String, dynamic>` by deliberate choice (constraint 1).
Every approach above either (a) accepts that and protects only the
call site, or (b) reintroduces a static type model and pays the
schema-maintenance cost. There is no free magic. The "best" answer is
the one that minimizes path-string surface area, not one that tries to
type-check the strings themselves.

## 4. Migration path (if recommendation lands)

Assumes recommendation 1+2. Order matches Phase 1 step ordering in the
redesign.

1. **Add `JsonPath<T>` and generic `JsonPatchOp` constructors** in `packages/soliplex_client/lib/src/application/`. ~40 LOC, one new file. Lands as part of the same PR that introduces `applyDelta` itself (the redesign plan doesn't show a current `JsonPatchOp` type — it'll be authored fresh).
2. **In Phase 1 step 4 (`NarrationPlugin`)**: define `_paths` private constants in the plugin file as `JsonPath<T>` instances; add typed write methods (`appendBlock`, `replaceBlock`, etc.) that consume those constants. ~20 LOC added to the plugin. Downstream `ClientTool` executors call the typed methods.
3. **In Phase 1 step 5 (`MapPlugin`)**: same pattern. Larger surface — ballpark 8–12 typed methods, ~80 LOC of plugin-internal path constants and helpers.
4. **In Phase 1 step 6 (`ExecutionTracker` → bus)**: same pattern for `/_meta/steps`. ~15 LOC.
5. **Phase 1 step 7 (mutators removed)**: with all public render-target mutators gone, plugin packages are the only place `bus.applyDelta` calls happen, *by virtue of where the plugin code physically lives* (Layer 2 package boundaries). The "force authoring into plugin files" guarantee comes from package structure, not from a lint. **The lint that would have flagged stray `bus.applyDelta` calls outside plugin files is moved to the post-v1 follow-on lint suite** — see `reactive-bus-redesign.md` Open follow-ons.

**Total migration**: ~200 LOC of new code across already-planned PRs,
zero new dependencies, zero new build steps. Does not change the v1
plan's phasing or risk profile.

If 2.5 (codegen) lands later, the typed methods from this migration
become its consumers — no regression, codegen just generates the
`JsonPath<T>` constants instead of hand-writing them.
