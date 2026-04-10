import 'package:soliplex_agent/soliplex_agent.dart';

class SendError {
  const SendError(
    this.error, {
    this.reason,
    this.unsentText,
  });

  final Object error;
  final FailureReason? reason;
  final String? unsentText;
}
