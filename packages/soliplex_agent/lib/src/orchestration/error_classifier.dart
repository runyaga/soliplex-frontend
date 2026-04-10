import 'package:soliplex_agent/src/models/failure_reason.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// Maps an error to a [FailureReason] for state machine transitions.
///
/// Handles both `SoliplexException` hierarchy (from REST calls)
/// and `AgUiError` hierarchy (from AG-UI streaming).
FailureReason classifyError(Object error) {
  if (error is AuthException) return FailureReason.authExpired;
  if (error is NetworkException) {
    // Both timeout and connection loss are technically networkLost in the UI.
    return FailureReason.networkLost;
  }
  if (error is ApiException) return _classifyStatus(error.statusCode);
  if (error is TransportError) return _classifyStatus(error.statusCode);
  return FailureReason.internalError;
}

FailureReason _classifyStatus(int? status) {
  if (status == null) return FailureReason.serverError;
  if (status == 401 || status == 403) return FailureReason.authExpired;
  if (status == 429) return FailureReason.rateLimited;
  if (status == 502 || status == 503 || status == 504) {
    return FailureReason.transientServerError;
  }
  return FailureReason.serverError;
}
