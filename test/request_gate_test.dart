import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/request_gate.dart';

void main() {
  tearDown(RequestGate.resetAll);
  test('Retry-After supports seconds, HTTP dates and waits over two minutes', () {
    final now = DateTime.utc(2026, 11, 18, 10);
    expect(RequestGate.retryAfter('300'), 300);
    expect(RequestGate.retryAfter('Wed, 18 Nov 2026 10:05:00 GMT', now: now), 300);
    expect(RequestGate.retryAfter('Wed, 18 Nov 2026 09:00:00 GMT', now: now), 0);
    expect(RequestGate.retryAfter('invalid'), isNull);
    expect(RequestGate.retryAfter('-1'), isNull);
    final gate = RequestGate.of('service.test')..limited(300);
    expect(gate.coolUntil!.difference(DateTime.now()).inSeconds, greaterThan(290));
  });
  test('already queued requests recheck a newly received cooldown', () async {
    final gate = RequestGate.of('service.test');
    await gate.turn();
    final watch = Stopwatch()..start();
    final waiting = [gate.turn(), gate.turn()];
    await Future<void>.delayed(const Duration(milliseconds: 30));
    gate.limited(1);
    await Future.wait(waiting);
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(1200));
  });
}
