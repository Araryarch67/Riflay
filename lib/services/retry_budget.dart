import 'dart:async';

/// A finite retry budget whose backoff can be cancelled immediately.
class RetryBudget {
  RetryBudget(this.delays);
  final List<Duration> delays;
  final _cancelled = Completer<void>();
  int attempts = 0;

  bool get cancelled => _cancelled.isCompleted;
  void cancel() {
    if (!cancelled) _cancelled.complete();
  }

  /// False after cancellation or exhaustion; one call consumes one retry.
  Future<bool> wait() async {
    if (cancelled || attempts >= delays.length) return false;
    final wake = Completer<void>();
    final timer = Timer(delays[attempts++], wake.complete);
    try {
      await Future.any([wake.future, _cancelled.future]);
      return !cancelled;
    } finally {
      timer.cancel();
    }
  }
}
