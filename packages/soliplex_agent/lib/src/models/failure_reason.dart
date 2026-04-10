/// Why an agent run failed.
///
/// Every error the orchestrator encounters is classified into one of
/// these categories. The sealed `AgentResult` hierarchy carries this
/// classification so callers can handle each scenario exhaustively.
enum FailureReason {
  /// Server returned an error event in the AG-UI stream.
  serverError,

  /// Auth token expired or was rejected (401/403).
  authExpired,

  /// Network lost — SSE stream ended without a terminal event.
  networkLost,

  /// Server returned 429 Too Many Requests.
  rateLimited,

  /// Tool execution failed (all retries exhausted).
  toolExecutionFailed,

  /// Server returned a transient error (502, 503, 504).
  ///
  /// UI should suggest retry as the server might recover.
  transientServerError,

  /// Internal error in the orchestrator itself.
  internalError,

  /// Run was cancelled by the caller.
  cancelled,
}
