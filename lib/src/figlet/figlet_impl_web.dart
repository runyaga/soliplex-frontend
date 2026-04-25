import 'dart:async';
import 'dart:js_interop';

@JS('figlet')
external JSFiglet get _figlet;

extension type JSFiglet(JSObject _) implements JSObject {
  external void text(String input, JSAny? options, JSFunction callback);
  external void fontList(JSFunction callback);
  external void metadata(String font, JSFunction callback);
}

/// Renders text via `figlet.text(...)`.
Future<String> renderFiglet(
  String text, {
  String? font,
  String? horizontalLayout,
  String? verticalLayout,
  int? width,
  bool? whitespaceBreak,
}) {
  final completer = Completer<String>();
  final cb = ((JSAny? err, JSString? data) {
    if (completer.isCompleted) return;
    if (err != null) {
      completer.completeError('figlet error: ${err.dartify()}');
      return;
    }
    completer.complete(data?.toDart ?? '');
  }).toJS;

  final opts = <String, Object?>{};
  if (font != null) opts['font'] = font;
  if (horizontalLayout != null) opts['horizontalLayout'] = horizontalLayout;
  if (verticalLayout != null) opts['verticalLayout'] = verticalLayout;
  if (width != null) opts['width'] = width;
  if (whitespaceBreak != null) opts['whitespaceBreak'] = whitespaceBreak;

  _figlet.text(text, opts.isEmpty ? null : opts.jsify(), cb);
  return completer.future;
}

/// Lists available font names via `figlet.fontList(...)`.
Future<List<String>> listFiglets() {
  final completer = Completer<List<String>>();
  final cb = ((JSAny? err, JSArray<JSString>? data) {
    if (completer.isCompleted) return;
    if (err != null) {
      completer.completeError('figlet error: ${err.dartify()}');
      return;
    }
    final fonts =
        data?.toDart.map((s) => s.toDart).toList(growable: false) ?? const [];
    completer.complete(fonts);
  }).toJS;
  _figlet.fontList(cb);
  return completer.future;
}

/// Returns metadata for one font via `figlet.metadata(...)`.
///
/// figlet.js callback signature is `(err, options, headerComment)` where
/// `options` is the parsed `.flf` header (height, hardBlank, layout, etc.)
/// and `headerComment` is the freeform author/credit text.
Future<Map<String, Object?>> figletMetadata(String font) {
  final completer = Completer<Map<String, Object?>>();
  final cb = ((JSAny? err, JSAny? options, JSString? comment) {
    if (completer.isCompleted) return;
    if (err != null) {
      completer.completeError('figlet error: ${err.dartify()}');
      return;
    }
    final dartOptions = options?.dartify();
    completer.complete({
      'options': dartOptions,
      'comment': comment?.toDart ?? '',
    });
  }).toJS;
  _figlet.metadata(font, cb);
  return completer.future;
}
