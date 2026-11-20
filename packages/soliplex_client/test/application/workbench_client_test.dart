import 'dart:convert';
import 'dart:typed_data';

import 'package:soliplex_client/src/application/workbench_client.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/authenticated_http_client.dart';
import 'package:soliplex_client/src/http/http_response.dart';
import 'package:soliplex_client/src/http/http_transport.dart';
import 'package:soliplex_client/src/http/soliplex_http_client.dart';
import 'package:soliplex_client/src/utils/cancel_token.dart';
import 'package:soliplex_client/src/utils/url_builder.dart';
import 'package:test/test.dart';

import '../../../../test/fixtures/workbench/workbench_fixtures.g.dart';

class _CaptureClient implements SoliplexHttpClient {
  String? method;
  Uri? uri;
  Object? body;
  int statusCode = 200;
  Object? responseBody;
  Map<String, String>? headers;
  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    CancelToken? cancelToken,
  }) async {
    this.method = method;
    this.uri = uri;
    this.body = body;
    this.headers = headers;
    final payload = responseBody ??
        <String, Object?>{
          'revision': 1,
          'layout': jsonDecode(workbenchFixtures['layout_tree_v1.json']!),
          'registrations': <Object?>[],
          'records': <Object?>[],
        };
    return HttpResponse(
      statusCode: statusCode,
      bodyBytes: Uint8List.fromList(
        utf8.encode(jsonEncode(payload)),
      ),
    );
  }

  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) =>
      throw UnimplementedError();
  @override
  void close() {}
}

void main() {
  test('uses the legacy scoped snapshot route', () async {
    final capture = _CaptureClient();
    final client = WorkbenchClient(
      transport: HttpTransport(client: capture),
      urlBuilder: UrlBuilder('https://example.test/api/v1'),
    );
    final snapshot = await client.getSnapshot(
      roomId: 'room_a',
      threadId: 'thread_1',
    );
    expect(snapshot.revision, 1);
    expect(capture.method, 'GET');
    expect(
      capture.uri!.path,
      '/api/v1/rooms/room_a/threads/thread_1/workbench',
    );
  });

  test('sends the bearer token through the authenticated transport', () async {
    const token = 'workbench-secret-token-012345';
    final capture = _CaptureClient();
    final transport = HttpTransport(
      client: AuthenticatedHttpClient(capture, () => token),
    );
    addTearDown(transport.close);
    final client = WorkbenchClient(
      transport: transport,
      urlBuilder: UrlBuilder('https://example.test/api/v1'),
    );

    await client.getSnapshot(roomId: 'room_a', threadId: 'thread_1');

    expect(capture.headers?['Authorization'], 'Bearer $token');
  });

  test('maps HTTP failures without exposing the bearer token', () async {
    const token = 'workbench-secret-token-012345';
    final capture = _CaptureClient();
    final transport = HttpTransport(
      client: AuthenticatedHttpClient(capture, () => token),
    );
    addTearDown(transport.close);
    final client = WorkbenchClient(
      transport: transport,
      urlBuilder: UrlBuilder('https://example.test/api/v1'),
    );
    final expectedTypes = <int, Type>{
      401: AuthException,
      403: PermissionDeniedException,
      404: NotFoundException,
      409: ApiException,
      422: ApiException,
    };

    for (final entry in expectedTypes.entries) {
      capture
        ..statusCode = entry.key
        ..responseBody = {'message': 'Echoed Bearer $token'};
      await expectLater(
        client.getSnapshot(roomId: 'room_a', threadId: 'thread_1'),
        throwsA(
          isA<SoliplexException>()
              .having((error) => error.runtimeType, 'type', entry.value)
              .having(
                (error) => error.message,
                'message',
                isNot(contains(token)),
              )
              .having(
                (error) => error.toString(),
                'toString',
                isNot(contains(token)),
              ),
        ),
        reason: 'HTTP ${entry.key}',
      );
    }
  });

  test('maps malformed successful snapshots to a typed response error',
      () async {
    final capture = _CaptureClient()
      ..responseBody = {
        'revision': 1,
        'layout': jsonDecode(workbenchFixtures['layout_tree_v1.json']!),
        'registrations': [1],
        'records': <Object?>[],
      };
    final client = WorkbenchClient(
      transport: HttpTransport(client: capture),
      urlBuilder: UrlBuilder('https://example.test/api/v1'),
    );

    await expectLater(
      client.getSnapshot(roomId: 'room_a', threadId: 'thread_1'),
      throwsA(isA<MalformedResponseException>()),
    );
  });
}
