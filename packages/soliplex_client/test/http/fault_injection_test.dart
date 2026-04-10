import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart' hide CancelToken;
import 'package:soliplex_client/src/http/agui_stream_client.dart';
import 'package:soliplex_client/src/http/http_response.dart';
import 'package:soliplex_client/src/http/http_transport.dart';
import 'package:soliplex_client/src/utils/cancel_token.dart';
import 'package:soliplex_client/src/utils/url_builder.dart';
import 'package:test/test.dart';

class MockHttpClient extends Mock implements http.Client {}
class FakeBaseRequest extends Fake implements http.BaseRequest {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeBaseRequest());
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  group('Fault Injection Tests', () {
    late MockHttpClient mockClient;
    late DartHttpClient dartClient;
    late HttpTransport transport;
    late AgUiStreamClient aguiClient;
    const baseUrl = 'https://api.test/v1';

    setUp(() {
      mockClient = MockHttpClient();
      dartClient = DartHttpClient(client: mockClient);
      transport = HttpTransport(client: dartClient);
      aguiClient = AgUiStreamClient(
        httpTransport: transport,
        urlBuilder: UrlBuilder(baseUrl),
      );
    });

    group('Transient 5xx Errors', () {
      final transientCodes = [502, 503, 504];

      for (final code in transientCodes) {
        test('HttpTransport throws ApiException for $code', () async {
          when(() => mockClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              Stream.value([]),
              code,
              reasonPhrase: 'Transient Error',
            ),
          );

          expect(
            () => transport.request('GET', Uri.parse('$baseUrl/test')),
            throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'statusCode', code),
            ),
          );
        });

        test('AgUiStreamClient throws ApiException for $code on connect', () async {
          when(() => mockClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              Stream.value([]),
              code,
              reasonPhrase: 'Transient Error',
            ),
          );

          expect(
            () => aguiClient.runAgent('test', const SimpleRunAgentInput()).toList(),
            throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'statusCode', code),
            ),
          );
        });
      }
    });

    group('Mid-stream SSE Corruption', () {
      test('AgUiStreamClient skips malformed JSON and continues', () async {
        final sseBody = StringBuffer()
          ..writeln('data: {"type": "RUN_STARTED", "threadId": "t1", "runId": "r1"}')
          ..writeln()
          ..writeln('data: {corrupt: json}') // Invalid JSON
          ..writeln()
          ..writeln('data: {"type": "RUN_FINISHED", "threadId": "t1", "runId": "r1"}')
          ..writeln();

        when(() => mockClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(sseBody.toString())),
            200,
            headers: {'content-type': 'text/event-stream'},
          ),
        );

        final events = await aguiClient.runAgent('test', const SimpleRunAgentInput()).toList();

        expect(events, hasLength(2));
        expect(events[0], isA<RunStartedEvent>());
        expect(events[1], isA<RunFinishedEvent>());
      });

      test('AgUiStreamClient skips truncated JSON in batch', () async {
        // A batch where one item is truncated/invalid
        final sseBody = StringBuffer()
          ..writeln('data: [{"type": "RUN_STARTED", "threadId": "t1", "runId": "r1"}, {"type": "INVALID') 
          ..writeln();

        when(() => mockClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(sseBody.toString())),
            200,
            headers: {'content-type': 'text/event-stream'},
          ),
        );

        // This should log an error but not throw, yielding whatever it could parse before corruption
        // In this case, json.decode will fail for the whole string if it's not a valid JSON array.
        final events = await aguiClient.runAgent('test', const SimpleRunAgentInput()).toList();
        expect(events, isEmpty);
      });
    });

    group('Abrupt Connection Drops', () {
      test('HttpTransport throws NetworkException on SocketException mid-request', () async {
        when(() => mockClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.fromIterable([
              utf8.encode('{"part": 1}'),
              throw const SocketException('Connection reset by peer'),
            ]),
            200,
          ),
        );

        expect(
          () => transport.request('GET', Uri.parse('$baseUrl/test')),
          throwsA(isA<NetworkException>().having((e) => e.message, 'message', contains('Connection reset by peer'))),
        );
      });

      test('AgUiStreamClient propagates NetworkException mid-stream', () async {
         final controller = StreamController<List<int>>();
         
         when(() => mockClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            controller.stream,
            200,
            headers: {'content-type': 'text/event-stream'},
          ),
        );

        final eventStream = aguiClient.runAgent('test', const SimpleRunAgentInput());
        
        // Add one good event
        controller.add(utf8.encode('data: {"type": "RUN_STARTED", "threadId": "t1", "runId": "r1"}\n\n'));
        
        // Fail the stream
        controller.addError(const SocketException('Broken pipe'));
        unawaited(controller.close());

        expect(
          () => eventStream.toList(),
          throwsA(isA<NetworkException>().having((e) => e.message, 'message', contains('Broken pipe'))),
        );
      });
    });
  });
}
