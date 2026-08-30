import 'package:flutter_test/flutter_test.dart';
import 'package:syncflow/domain/sync/retry_policy.dart';

void main() {
  const policy = RetryPolicy();

  test('gecikme üstel olarak artar', () {
    expect(policy.delayFor(0), const Duration(seconds: 2));
    expect(policy.delayFor(1), const Duration(seconds: 4));
    expect(policy.delayFor(2), const Duration(seconds: 8));
    expect(policy.delayFor(3), const Duration(seconds: 16));
  });

  test('gecikme üst sınırı aşmaz', () {
    expect(policy.delayFor(10), const Duration(minutes: 5));
    expect(policy.delayFor(64), const Duration(minutes: 5));
  });

  test('deneme sayısı sınırı uygulanır', () {
    expect(policy.shouldRetry(7), isTrue);
    expect(policy.shouldRetry(8), isFalse);
  });
}
