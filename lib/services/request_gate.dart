import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// A server asked for fewer requests (HTTP 429 or 503), with how long to wait if it said.
class SourceBusy implements Exception {
  const SourceBusy([this.seconds]);
  final int? seconds;
  @override
  String toString() => 'HTTP 429/503 (busy${seconds == null ? '' : ', retry after $seconds s'})';
}

/// One service's requests, sent as one well-behaved client: a small gap between them, and once the service says
/// "too many" (429), a pause for every request to it at once, not each part of the app retrying on its own (that
/// kept Monochrome's limit on). The song being played goes first ([turn]'s `urgent`), ahead of songs got ready.
class RequestGate {
  RequestGate._(this.host);

  final String host;

  static final _all = <String, RequestGate>{};

  /// The gate of [host], made on first ask.
  static RequestGate of(String host) => _all.putIfAbsent(host, () => RequestGate._(host));

  /// Whether some service is pausing for its limit now (Smart merge's badge turns red).
  static final anyBusy = ValueNotifier<bool>(false);

  static void _syncAny() => anyBusy.value = _all.values.any((g) => g.cooling);

  /// Forgets every pause (tests, through [MergedDownload.forgetAll]).
  static void resetAll() {
    for (final g in _all.values) {
      g._timer?.cancel();
    }
    _all.clear();
    anyBusy.value = false;
  }

  /// Between two requests that aren't urgent.
  static const gap = Duration(milliseconds: 250);

  DateTime? _coolUntil;
  int _strikes = 0;
  DateTime _next = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _timer;

  bool get cooling => _coolUntil != null && DateTime.now().isBefore(_coolUntil!);

  /// When the pause ends (null: none).
  DateTime? get coolUntil => cooling ? _coolUntil : null;

  /// Waits for this request's turn: after the pause, and [gap] after the previous request unless [urgent].
  Future<void> turn({bool urgent = false}) async {
    while (true) {
      final now = DateTime.now();
      if (_coolUntil case final until? when now.isBefore(until)) {
        await Future<void>.delayed(until.difference(now));
        continue;
      }
      if (urgent || !now.isBefore(_next)) {
        _next = now.add(gap);
        return;
      }
      final wait = _next.difference(now);
      _next = _next.add(gap);
      await Future<void>.delayed(wait);
      return;
    }
  }

  /// The service said "too many": every request to it waits [seconds] (its Retry-After), or 15, 30, 60, then 120 s.
  void limited([int? seconds]) {
    _strikes++;
    final wait = seconds != null
        ? Duration(seconds: seconds.clamp(1, 120))
        : Duration(seconds: math.min(120, 15 << math.min(_strikes - 1, 3)));
    final until = DateTime.now().add(wait);
    if (_coolUntil == null || until.isAfter(_coolUntil!)) _coolUntil = until;
    debugPrint('Request gate: $host is limiting requests, pausing ${wait.inSeconds} s');
    _timer?.cancel();
    _timer = Timer(_coolUntil!.difference(DateTime.now()), _syncAny);
    _syncAny();
  }

  /// A request went through: the next limit starts from the shortest pause again.
  void ok() {
    if (cooling) return;
    _strikes = 0;
  }
}
