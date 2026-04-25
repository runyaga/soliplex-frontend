// Native (non-web) implementations. Throw so the executors catch and
// return a JSON error payload to the LLM.

Future<String> renderFiglet(
  String text, {
  String? font,
  String? horizontalLayout,
  String? verticalLayout,
  int? width,
  bool? whitespaceBreak,
}) {
  throw UnsupportedError('figlet.js is only available on web');
}

Future<List<String>> listFiglets() {
  throw UnsupportedError('figlet.js is only available on web');
}

Future<Map<String, Object?>> figletMetadata(String font) {
  throw UnsupportedError('figlet.js is only available on web');
}
