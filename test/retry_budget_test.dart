import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/retry_budget.dart';

void main() {
  test('nested failures share a finite budget', () async {
    final budget = RetryBudget(List.filled(8, Duration.zero));
    for (var i = 0; i < 8; i++) {
      expect(await budget.wait(), isTrue);
    }
    expect(await budget.wait(), isFalse);
    expect(budget.attempts, 8);
  });

  test('cancellation interrupts a long backoff immediately', () async {
    final budget = RetryBudget([const Duration(hours: 1)]);
    final waiting = budget.wait();
    budget.cancel();
    expect(await waiting.timeout(const Duration(seconds: 1)), isFalse);
    expect(await budget.wait(), isFalse);
  });
}
