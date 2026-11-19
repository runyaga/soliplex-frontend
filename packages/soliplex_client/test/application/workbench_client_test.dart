import 'dart:convert';
import 'dart:typed_data';

import 'package:soliplex_client/src/application/workbench_client.dart';
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
    return HttpResponse(
      statusCode: 200,
      bodyBytes: Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'revision': 1,
            'layout': jsonDecode(workbenchFixtures['layout_tree_v1.json']!),
            'registrations': <Object?>[],
            'records': <Object?>[],
          }),
        ),
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
  test('uses scoped authenticated snapshot and action routes', () async {
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
    await client.postAction(
      roomId: 'r',
      threadId: 't',
      envelope: {'v': 1, 'submissionId': 'id'},
    );
    expect(capture.method, 'POST');
    expect(capture.uri!.path, '/api/v1/rooms/r/threads/t/workbench/actions');
    expect(capture.body, '{"v":1,"submissionId":"id"}');
  });
}
