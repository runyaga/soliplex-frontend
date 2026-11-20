import 'dart:convert';

/// The backend's explicit tool error envelope, or null for ordinary output.
///
/// Older pydantic-ai versions append retry guidance to ModelRetry content.
String? toolResultError(String content) {
  final body = content.split('\n\nFix the errors and try again.').first;
  try {
    final value = jsonDecode(body);
    if (value is Map<String, dynamic> && value['error'] is String) {
      return value['error'] as String;
    }
  } on FormatException {
    // Plain text and partial JSON are valid successful tool output.
  }
  return null;
}
