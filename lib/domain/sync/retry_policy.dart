import 'dart:math';

class RetryPolicy {
  const RetryPolicy({
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.maxAttempts = 8,
  });

  final Duration initialDelay;
  final Duration maxDelay;
  final int maxAttempts;

  bool shouldRetry(int attempt) => attempt < maxAttempts;

  Duration delayFor(int attempt) {
    final exponent = min(attempt, 20);
    final millis = initialDelay.inMilliseconds * (1 << exponent);
    return Duration(milliseconds: min(millis, maxDelay.inMilliseconds));
  }
}

class PendingOperation {
  const PendingOperation({
    required this.id,
    required this.entityId,
    required this.payload,
    required this.attempts,
    required this.createdAt,
    this.lastError,
  });

  final int id;
  final String entityId;
  final Map<String, dynamic> payload;
  final int attempts;
  final DateTime createdAt;
  final String? lastError;
}
