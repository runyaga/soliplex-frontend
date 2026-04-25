# Integrating JavaScript Libraries as LLM Tools

How we wired `figlet.js` into the chat as a `render_figlet` tool —
including everything we learned the hard way about Flutter Web fonts,
markdown code-blocks, and language-tag dispatch. Use this as the
template for the next browser-side JS library.

## TL;DR

1. Drop the JS library into `web/index.html` (CDN `<script>` tag plus a
   shim if it leaves things on a lexical-const that `globalThis` cannot
   see).
2. Build a `SessionExtension` in `lib/src/<libname>/` exposing one or
   more `ClientTool`s. Use a conditional import on
   `dart.library.js_interop` for the `_web.dart` / `_stub.dart` split.
3. Have the tool return its result **already wrapped in a fenced code
   block** with a custom language tag (e.g. ` ```figlet `). Tool
   description tells the LLM to embed it verbatim.
4. Register a custom widget in `lib/src/modules/room/ui/markdown/code_block_builder.dart`
   for that language tag (see `_FigletBlock` next to `_SvgCodeBlock`).
5. Bundle a real monospace TTF in `pubspec.yaml` if the output relies on
   column alignment — CanvasKit ignores `fontFamily: 'monospace'`.
6. Wire `FigletExtension()` (or whatever) into `extraExtensions` in
   `lib/main.dart`.

## What lives where (real anchors)

| Concern | Location |
| --- | --- |
| `render_figlet` tool registration | `lib/src/figlet/figlet_extension.dart` |
| JS interop binding | `lib/src/figlet/figlet_impl_web.dart` |
| Native stub | `lib/src/figlet/figlet_impl_stub.dart` |
| Conditional import pattern | `packages/soliplex_logging/lib/src/sinks/console_sink.dart:7` |
| Reference Monty tool | `packages/soliplex_agent_monty/lib/src/monty_runtime_extension.dart:48` |
| `extraExtensions` hook | `lib/main.dart:30` (consumed in `lib/src/flavors/standard.dart`) |
| Custom-extension docs | `CLAUDE.md` — section "Adding custom client-side session extensions" |
| Markdown renderer | `lib/src/modules/room/ui/markdown/flutter_markdown_plus_renderer.dart` |
| Code-fence registry | `lib/src/modules/room/ui/markdown/code_block_builder.dart:24,31` |
| Web entry point | `web/index.html` (scripts before `</body>`) |
| Bundled font | `fonts/RobotoMono-Regular.ttf` + `pubspec.yaml` `flutter:fonts:` |

## Part 1 — Loading the JS library in the browser

### CDN tag

`web/index.html`, before `</body>`:

```html
<script src="https://cdn.jsdelivr.net/npm/figlet@1.7.0/lib/figlet.min.js"></script>
```

Vendor it under `web/` and reference relatively for offline /
reproducible builds.

### Shim for lexical-const exports

**figlet.js v1.7.x trap.** The minified bundle starts with
`"use strict"; const figlet = (() => {...})()`. A top-level `const` in a
classic `<script>` is a *lexical* global — visible to other scripts as a
bare identifier `figlet`, but **not** a property of `globalThis` /
`window`. `dart:js_interop`'s `@JS('figlet')` resolves via
`globalThis.figlet`, so without help it gets `null` and throws
`type 'Null' is not a subtype of type 'JSObject'` on first use.

The fix is a tiny inline shim right after the library tag:

```html
<script>
  // figlet.min.js declares `const figlet = ...` at script-top, which is
  // lexical (not on window). Dart's @JS('figlet') needs a globalThis
  // property, so we copy it explicitly.
  window.figlet = figlet;
  figlet.defaults({ fontPath: 'https://cdn.jsdelivr.net/npm/figlet@1.7.0/fonts' });
</script>
```

Whenever you add a new JS library, **check whether it attaches to
`window`**. UMD bundles with the `"undefined" != typeof module && (module.exports = X)` tail
do not in browser. `let` / `const` / strict-mode top-level vars don't
either. If in doubt: `console.log(window.libName)` after the tag — if
`undefined`, you need a shim.

## Part 2 — Dart side: the SessionExtension

### Public extension class — `lib/src/figlet/figlet_extension.dart`

```dart
import 'dart:convert';

import 'package:soliplex_agent/soliplex_agent.dart';
// ignore: implementation_imports
import 'package:soliplex_agent/src/tools/tool_execution_context.dart'
    show ToolExecutionContext;

import 'figlet_impl_stub.dart'
    if (dart.library.js_interop) 'figlet_impl_web.dart' as impl;

class FigletExtension extends SessionExtension {
  @override
  String get namespace => 'figlet';

  @override
  Future<void> onAttach(AgentSession session) async {}

  @override
  void onDispose() {}

  @override
  List<ClientTool> get tools => [
        ClientTool.simple(
          name: 'render_figlet',
          description: '...',          // see "Tool description" below
          parameters: const {
            'type': 'object',
            'properties': {
              'text': {'type': 'string'},
              'font': {'type': 'string'},
            },
            'required': ['text'],
          },
          executor: _execute,
        ),
      ];

  Future<String> _execute(ToolCallInfo call, ToolExecutionContext _) async {
    // ... parse, call impl.renderFiglet, return JSON-encoded `output` ...
  }
}
```

Key conventions:

- **Errors → JSON, not throws.** Throwing inside an executor produces
  `status: failed` and the LLM unconditionally retries. Returning
  `{"error": "..."}` lets the LLM decide. (Project memory:
  `feedback_python_error_as_output`.)
- **Always return JSON.** Even when the tool conceptually returns a
  string, encode it: `jsonEncode({'output': '...'})`. Consumers parse
  uniformly.
- **`namespace` is bookkeeping.** The LLM only sees `ClientTool.name` —
  pick names that won't collide (`render_figlet`, not `render`).

### Web impl — `lib/src/figlet/figlet_impl_web.dart`

```dart
import 'dart:async';
import 'dart:js_interop';

@JS('figlet')
external JSFiglet get _figlet;

extension type JSFiglet(JSObject _) implements JSObject {
  external void text(String input, JSAny? options, JSFunction callback);
}

Future<String> renderFiglet(String text, String? font) {
  final completer = Completer<String>();
  final cb = ((JSAny? err, JSString? data) {
    if (completer.isCompleted) return;
    if (err != null) {
      completer.completeError('figlet error: ${err.dartify()}');
      return;
    }
    completer.complete(data?.toDart ?? '');
  }).toJS;
  final options = font == null ? null : <String, String>{'font': font}.jsify();
  _figlet.text(text, options, cb);
  return completer.future;
}
```

Pattern notes:

- **`extension type` over `@anonymous` classes** for typed JS objects —
  this is the modern `dart:js_interop` API.
- **Type the callback parameters narrowly** (`JSString?` not `JSAny?`)
  to avoid the
  `invalid_runtime_check_with_js_interop_types` analyzer warning that
  would force you into `.isA<JSString>()`.
- Browser-side JS callbacks → `Completer<T>` so the executor can
  `await`.
- Always convert explicitly: `.toJS`, `.toDart`, `.jsify()`,
  `.dartify()`.

### Native stub — `lib/src/figlet/figlet_impl_stub.dart`

```dart
Future<String> renderFiglet(String text, String? font) {
  throw UnsupportedError('figlet.js is only available on web');
}
```

The `try/catch` in the executor turns this into
`{"error": "Unsupported operation: ..."}` so the LLM gets a completed
call on macOS/iOS/Android instead of a crash.

### Conditional import gates the JS code out of native

```dart
import 'figlet_impl_stub.dart'
    if (dart.library.js_interop) 'figlet_impl_web.dart' as impl;
```

`dart.library.js_interop` is the right gate — it's a compile-time
constant. `kIsWeb` is a runtime check; using it means the JS-binding
file still compiles on macOS, even if the runtime path never executes.
The `if (dart.library.js_interop)` form lets the entire `_web.dart`
file disappear from native builds.

### Wire-up — `lib/main.dart`

```dart
extraExtensions: () async => [
  if (_montyEnabled)
    MontyRuntimeExtension(extensions: MontyExtensionSet.standard()),
  FigletExtension(),
],
```

No flavor fork, no compile-time flag needed: the conditional import
already gates the JS bindings, and the stub keeps the API total on
native.

## Part 3 — Code-block rendering (the hard part)

Default behavior for ` ```...``` ` in a chat message:

1. `flutter_markdown_plus` parses the message.
2. The fence's class becomes `language-X`.
3. `CodeBlockBuilder.visitElementAfter`
   (`lib/src/modules/room/ui/markdown/code_block_builder.dart:17`)
   runs.
4. For unknown languages it falls through to `_CodeBlock` →
   `flutter_highlight`'s `HighlightView`, which **wraps each token in a
   span**. For ASCII art that breaks visual column alignment.

That's the wrong path for figlet.

### The fence registry pattern

`CodeBlockBuilder.visitElementAfter` already special-cases `svg`. Add a
sibling `if` for any language whose content is not real source code:

```dart
if (language == 'figlet') {
  return Semantics(
    label: 'Figlet ASCII art',
    child: _FigletBlock(code: code, codeStyle: this.preferredStyle),
  );
}
```

`code` here is `element.textContent`, which **does** preserve fence
content whitespace (we proved this with a debug print — see "Lessons"
below). No need for sentinel characters or workarounds.

`_FigletBlock` is a small widget: a "figlet" label, a copy button, and
a `SingleChildScrollView` wrapping a `Text` with the bundled monospace
font.

### Why a custom widget vs. relying on the default

| Concern | Default (`HighlightView`) | Custom (`_FigletBlock`) |
| --- | --- | --- |
| Token spans | Yes — breaks column alignment | No — single `Text` |
| Syntax highlight | Tries `language-X` against highlight.js | None |
| Font size | Inherits 14pt from renderer | Bumped to 18pt for figlet |
| Horizontal scroll | Yes | Yes |

For SVG we go further: `_SvgCodeBlock` toggles between rendered preview
and source. Each new language tag is an opportunity for a tailored
widget.

### Have the tool pre-wrap the output

```dart
return jsonEncode({'output': '```figlet\n$rendered\n```'});
```

Two reasons:

1. The LLM cannot accidentally choose a different fence (or no fence)
   if the wrap is already there.
2. The tool description can say "embed `output` verbatim" with one
   meaning. Less ambiguity, fewer prompt-engineering knobs.

Tool description (the one that's actually in
`figlet_extension.dart`):

> Renders ASCII-art banner text using the figlet.js library… IMPORTANT:
> the `output` field already contains a complete fenced code block
> tagged `figlet`. Embed it verbatim in your response — do NOT
> re-wrap, re-indent, summarize, or add any prose inside the fence. The
> chat renders the `figlet` fence with a custom widget that needs the
> whitespace preserved exactly.

## Part 4 — Flutter Web fonts (the *really* hard part)

We lost about an hour to this. Save yourself.

### `fontFamily: 'monospace'` is theatre on CanvasKit

CanvasKit is the default Flutter Web renderer. It ships its own font
manager and **does not see system fonts**. Setting
`fontFamily: 'monospace'` does not resolve to Menlo / Courier / etc. —
it falls through to whatever Skia has loaded, which is typically Roboto
plus Noto: both proportional. Even with
`fontFamilyFallback: ['Courier New', 'Courier']`, CanvasKit still has
no way to resolve those names, so they're inert.

Symptoms:

- Columns drift across rows.
- Apparent "rendered twice" effect when `height: 1.0` lets the bottom of
  one row's `_` collide with the top of the next row's `_`.
- Looks visually similar to a real monospace font at first glance, so
  easy to misdiagnose as a content bug.

### The fix: bundle a TTF

`pubspec.yaml`:

```yaml
flutter:
  fonts:
    - family: RobotoMono
      fonts:
        - asset: fonts/RobotoMono-Regular.ttf
```

Then use it:

```dart
final figletStyle = TextStyle(
  fontFamily: 'RobotoMono',
  fontSize: 18,
  height: 1.2,
  letterSpacing: 0,
  color: theme.colorScheme.onSurface,
);
```

`height: 1.2` (not `1.0`) — gives breathing room so adjacent rows do
not visually merge. `letterSpacing: 0` is defensive; many themes set a
nonzero value.

The TTF lives in `fonts/RobotoMono-Regular.ttf` (~126KB) — Apache 2.0,
fetched from `googlefonts/RobotoMono` GitHub raw. Bundled is more
reliable than `google_fonts` package for primary chat rendering: no
network dependency on first launch, no flicker.

## Part 5 — Lessons learned (debugging journey)

### Don't blame layers without instrumenting

We spent time speculating that markdown was stripping leading
whitespace from line 1 of figlet output. It wasn't. The widget-side
debug print proved `element.textContent` arrived with the original
whitespace intact. **Add the print before adding the workaround.**

The reusable debug-print pattern, dropped temporarily into the widget:

```dart
print(
  '[figlet-debug] received ${code.length} chars, '
  'lines=${code.split('\n').length}, '
  'leadingChars(line0)=${_visualizeLeading(code.split('\n').first)}',
);
```

Where `_visualizeLeading` substitutes `°` for spaces so the count is
visible in console output.

### Pasted text is unreliable evidence

The user pasted "what the copy button copies" into our chat several
times. Each paste lost line 1's leading whitespace — but it was the
chat's own UI doing the trimming, not anything in the app. **Trust
debug prints, screenshots of the running app, or `pbpaste | xxd`. Not
text the user typed back at you.**

### "Looks rendered twice" → almost always vertical line collision

`Text` with `height: 1.0` on a font whose ascender/descender extend
beyond `em` will overlap rows. It looks like a double render. The fix
is `height: 1.2` (or higher), not chasing duplicate draws in the
widget tree.

## Generalising — checklist for the next JS library

- [ ] CDN tag (or vendored asset) in `web/index.html`.
- [ ] Lexical-const shim if the library doesn't attach to `window` —
      verify with `console.log(window.libName)` after the tag.
- [ ] `_web.dart` impl with `@JS('global_name')` + typed `extension type`.
- [ ] `_stub.dart` mirroring the impl signatures, throwing
      `UnsupportedError`.
- [ ] Conditional import using `dart.library.js_interop`.
- [ ] Tool description is explicit about platform-only-ness AND about
      how the LLM should present the result (verbatim? code-fenced?).
- [ ] If output is non-prose (ASCII art, diagram, etc.), pre-wrap in
      `\`\`\`<lang>\n...\n\`\`\`` and add the language case to
      `code_block_builder.dart`.
- [ ] If column alignment matters, ensure a real monospace TTF is
      bundled (`pubspec.yaml` `fonts:`).
- [ ] Run `flutter analyze`; resolve js_interop type-check warnings by
      narrowing callback parameter types (`JSString?` etc.) instead of
      `is JSString`.
- [ ] Smoke-test on `flutter run -d chrome --profile` (web) and
      `flutter run -d macos` (native) — the native run should produce
      `{"error": "Unsupported operation: ..."}` rather than crashing.

## Open questions / deferred

- **A shared `soliplex_agent_js_tools` package** — defer until a second
  JS-backed tool exists. No premature abstraction.
- **A runtime "drop web-only tools on native" guard** — probably not.
  The LLM benefits from knowing the tool exists but is unavailable
  here, so it can apologise rather than silently fail.
- **Disable `softWrap` only for figlet, or for any custom fence?** —
  `_FigletBlock` does this in its `Text`. If we add many fence
  renderers, factor out a `MonoFenceBlock(language:, code:)` shared
  base.
- **Why the chat sometimes shows two `render_figlet` tool-call tiles
  per turn** — under investigation; may be a UI dedup gap in
  `ToolCallsExtension`, not a real duplicate call. Tracked separately.
