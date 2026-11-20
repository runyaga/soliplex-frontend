import 'package:soliplex_client/src/domain/workbench_snapshot.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/http_transport.dart';
import 'package:soliplex_client/src/utils/url_builder.dart';

/// Authenticated transport for room and thread scoped workbench operations.
class WorkbenchClient {
  /// Creates a client for authenticated room and thread workbench requests.
  WorkbenchClient({
    required HttpTransport transport,
    required UrlBuilder urlBuilder,
  })  : _transport = transport,
        _urlBuilder = urlBuilder;

  final HttpTransport _transport;
  final UrlBuilder _urlBuilder;

  /// Fetches a single coherent snapshot and its authenticated registrations.
  Future<WorkbenchSnapshot> getSnapshot({
    required String roomId,
    required String threadId,
  }) async {
    final result = await _transport.request<Map<String, dynamic>>(
      'GET',
      _uri(roomId, threadId),
    );
    try {
      return WorkbenchSnapshot.fromJson(result);
    } on FormatException catch (error) {
      throw MalformedResponseException(
        message: 'Invalid workbench snapshot: ${error.message}',
        originalError: error,
      );
    }
  }

  Uri _uri(String roomId, String threadId) => _urlBuilder.build(
        pathSegments: ['rooms', roomId, 'threads', threadId, 'workbench'],
      );
}
