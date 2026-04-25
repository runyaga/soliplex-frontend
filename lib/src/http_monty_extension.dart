// HTTP host functions for Monty Python scripts.
//
// Exposes `http_get(url, headers?)` returning the response body as a
// string — Python uses `json.loads(...)` to decode JSON. Add to the
// MontyExtensionSet alongside the standard set so both terminal and
// LLM-tool runtimes can fetch.
//
// Browser caveat: Flutter Web cannot bypass CORS. APIs that don't send
// `Access-Control-Allow-Origin: *` (or whatever the page's origin is)
// will fail with a network error visible in the browser console — not
// a Python error. Test target URLs in the browser first or proxy
// through your own backend.

// HostFunction wraps closures that hold per-extension state (here, a
// shared http.Client), so the constructor can't be const.
// ignore_for_file: prefer_const_constructors, avoid_redundant_argument_values

import 'dart:async';
import 'dart:convert';

import 'package:dart_monty/dart_monty_bridge.dart'
    show
        HostFunction,
        HostFunctionSchema,
        HostParam,
        HostParamType,
        MontyExtension;
import 'package:http/http.dart' as http;

/// Bridges a [http.Client] into a `dart_monty` runtime so Python scripts
/// can call HTTP endpoints.
///
/// ```python
/// import json
/// body = http_get("https://api.example.com/things", headers={"Accept": "application/json"})
/// things = json.loads(body)
/// ```
class HttpMontyExtension extends MontyExtension {
  HttpMontyExtension({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Per-call timeout. Configurable later if needed; start strict so a
  /// hung server can't pin the runtime forever.
  static const _timeout = Duration(seconds: 15);

  @override
  String get namespace => 'http';

  @override
  String? get systemPromptContext =>
      'HTTP externals available in Python: '
      'http_get(url, headers?) -> str (response body). '
      'Decode JSON with json.loads(). '
      'Browser sandbox: subject to CORS — only public APIs that send '
      "'Access-Control-Allow-Origin' headers will succeed.";

  @override
  Future<void> onDispose() async {
    _client.close();
    await super.onDispose();
  }

  @override
  List<HostFunction> get functions => [
        HostFunction(
          schema: HostFunctionSchema(
            name: 'http_get',
            description:
                'Performs an HTTP GET. Returns the response body as a '
                'string. Use json.loads(body) to decode JSON. Throws on '
                'non-2xx status, network error, or timeout (15s).',
            params: const [
              HostParam(
                name: 'url',
                type: HostParamType.string,
                description: 'Absolute URL including scheme.',
              ),
              HostParam(
                name: 'headers',
                type: HostParamType.map,
                isRequired: false,
                description:
                    'Optional dict of header name -> value. Strings only.',
              ),
            ],
          ),
          handler: (args, ctx) async {
            final url = args['url']! as String;
            final rawHeaders = args['headers'];
            final headers = <String, String>{};
            if (rawHeaders is Map) {
              for (final entry in rawHeaders.entries) {
                headers[entry.key.toString()] = entry.value.toString();
              }
            }
            final res = await _client
                .get(Uri.parse(url), headers: headers)
                .timeout(_timeout);
            if (res.statusCode < 200 || res.statusCode >= 300) {
              throw _HttpException(
                'http_get: ${res.statusCode} ${res.reasonPhrase ?? ''} '
                '($url)',
              );
            }
            return res.body;
          },
        ),
        HostFunction(
          schema: HostFunctionSchema(
            name: 'http_get_json',
            description:
                'Convenience wrapper around http_get that decodes the '
                'response body as JSON and returns the parsed value '
                'directly. Throws on non-2xx, network error, timeout, '
                'or invalid JSON.',
            params: const [
              HostParam(
                name: 'url',
                type: HostParamType.string,
                description: 'Absolute URL including scheme.',
              ),
              HostParam(
                name: 'headers',
                type: HostParamType.map,
                isRequired: false,
              ),
            ],
          ),
          handler: (args, ctx) async {
            final url = args['url']! as String;
            final rawHeaders = args['headers'];
            final headers = <String, String>{
              'Accept': 'application/json',
            };
            if (rawHeaders is Map) {
              for (final entry in rawHeaders.entries) {
                headers[entry.key.toString()] = entry.value.toString();
              }
            }
            final res = await _client
                .get(Uri.parse(url), headers: headers)
                .timeout(_timeout);
            if (res.statusCode < 200 || res.statusCode >= 300) {
              throw _HttpException(
                'http_get_json: ${res.statusCode} '
                '${res.reasonPhrase ?? ''} ($url)',
              );
            }
            return jsonDecode(res.body);
          },
        ),
      ];
}

/// Local exception type so Python sees a clean message instead of a
/// generic ClientException string.
class _HttpException implements Exception {
  _HttpException(this.message);
  final String message;
  @override
  String toString() => message;
}
