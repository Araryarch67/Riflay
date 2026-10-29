import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/sleep_timer.dart';

/// A player that records what the timer does to it.
class _Host implements SleepHost {
  @override
  bool playing = true;
  @override
  String? trackId = 'a';
  @override
  Duration? songRemaining;

  final fades = <double>[];
  int pauses = 0;

  @override
  void setFade(double gain) => fades.add(gain);

  @override
  Future<void> pause() async {
    pauses++;
    playing = false;
  }

  double get lastFade => fades.isEmpty ? 1 : fades.last;
}

void main() {
  late DateTime now;
  late _Host host;
  late SleepTimer timer;

  setUp(() {
    now = DateTime(2026, 1, 1, 22, 0);
    host = _Host();
    timer = SleepTimer(now: () => now, restoreDelay: Duration.zero)..attach(host);
  });
  tearDown(() => timer.dispose());

  void at(Duration after) {
    now = DateTime(2026, 1, 1, 22, 0).add(after);
    timer.tick();
  }

  group('countdown', () {
    test('runs from a wall-clock deadline and reports what is left', () {
      timer.start(const Duration(minutes: 30));
      expect(timer.active, isTrue);
      expect(timer.mode, SleepMode.countdown);
      expect(timer.deadline, DateTime(2026, 1, 1, 22, 30));
      expect(timer.remaining, const Duration(minutes: 30));
      now = now.add(const Duration(minutes: 12, seconds: 30));
      expect(timer.remaining, const Duration(minutes: 17, seconds: 30));
    });

    test('keeps full volume until the last 30 seconds, then fades', () {
      timer.start(const Duration(minutes: 30));
      at(const Duration(minutes: 29, seconds: 29));
      expect(host.lastFade, 1);
      expect(host.pauses, 0);
      at(const Duration(minutes: 29, seconds: 45)); // halfway through the fade
      expect(host.lastFade, closeTo(0.5, 0.02));
      at(const Duration(minutes: 29, seconds: 55));
      expect(host.lastFade, lessThan(0.15));
      expect(host.pauses, 0);
    });

    test('fades down without ever going back up', () {
      timer.start(const Duration(minutes: 1));
      var last = 1.0;
      for (var s = 25; s < 60; s++) {
        at(Duration(seconds: s));
        expect(host.lastFade, lessThanOrEqualTo(last + 1e-9), reason: 'at $s s');
        last = host.lastFade;
      }
      expect(last, lessThan(0.05));
    });

    test('pauses at the deadline, then gives the volume back', () async {
      timer.start(const Duration(minutes: 15));
      at(const Duration(minutes: 15));
      await Future<void>.delayed(Duration.zero);
      expect(host.pauses, 1);
      expect(host.playing, isFalse);
      expect(timer.active, isFalse);
      expect(host.fades, contains(0.0));
      expect(host.lastFade, 1, reason: 'the next song starts at the volume the user set');
      // Ticks after it are no-ops.
      at(const Duration(minutes: 16));
      expect(host.pauses, 1);
    });

    test('a late tick (the phone slept) still pauses, once', () async {
      timer.start(const Duration(minutes: 45));
      at(const Duration(minutes: 20));
      at(const Duration(hours: 3)); // nothing ran in between
      await Future<void>.delayed(Duration.zero);
      expect(host.pauses, 1);
      expect(timer.active, isFalse);
    });

    test('does not pause what is already paused, but still ends', () async {
      host.playing = false;
      timer.start(const Duration(minutes: 15));
      at(const Duration(minutes: 15));
      await Future<void>.delayed(Duration.zero);
      expect(host.pauses, 0);
      expect(timer.active, isFalse);
      expect(host.lastFade, 1);
    });

    test('a time of day: today if still ahead, else tomorrow', () {
      timer.startAt(22, 45);
      expect(timer.deadline, DateTime(2026, 1, 1, 22, 45));
      timer.startAt(21, 30);
      expect(timer.deadline, DateTime(2026, 1, 2, 21, 30));
    });
  });

  group('extend and cancel', () {
    test('+10 minutes moves the deadline', () {
      timer.start(const Duration(minutes: 15));
      timer.extend();
      expect(timer.remaining, const Duration(minutes: 25));
      now = now.add(const Duration(minutes: 5));
      timer.extend();
      expect(timer.remaining, const Duration(minutes: 30));
    });

    test('+10 minutes in the middle of the fade brings the volume back gently, not in one step', () {
      timer.start(const Duration(minutes: 1));
      at(const Duration(seconds: 50)); // 10 s left: well into the fade
      final low = host.lastFade;
      expect(low, lessThan(0.3));
      timer.extend();
      expect(host.lastFade, lessThan(low + 0.1), reason: 'no jump back to full volume');
      // Two seconds on it is back.
      for (var ms = 100; ms <= 2500; ms += 100) {
        now = DateTime(2026, 1, 1, 22, 0, 50).add(Duration(milliseconds: ms));
        timer.tick();
      }
      expect(host.lastFade, 1);
      expect(host.pauses, 0);
    });

    test('+10 minutes with no timer starts one', () {
      timer.extend();
      expect(timer.mode, SleepMode.countdown);
      expect(timer.remaining, const Duration(minutes: 10));
    });

    test('cancel stops it for good and eases the volume back up', () async {
      timer.start(const Duration(minutes: 1));
      at(const Duration(seconds: 55));
      expect(host.lastFade, lessThan(0.2));
      timer.cancel();
      expect(timer.active, isFalse);
      expect(timer.remaining, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      expect(host.lastFade, 1);
      at(const Duration(minutes: 5));
      expect(host.pauses, 0);
    });
  });

  group('end of this song', () {
    test('fades over the last seconds of the song and pauses at its end', () async {
      host.songRemaining = const Duration(minutes: 3);
      timer.startEndOfSong();
      expect(timer.mode, SleepMode.endOfSong);
      expect(timer.remaining, const Duration(minutes: 3));
      host.songRemaining = const Duration(seconds: 20);
      timer.tick();
      expect(host.lastFade, 1);
      host.songRemaining = const Duration(seconds: 4);
      timer.tick();
      expect(host.lastFade, closeTo(0.5, 0.05));
      host.songRemaining = const Duration(milliseconds: 60);
      timer.tick();
      await Future<void>.delayed(Duration.zero);
      expect(host.pauses, 1);
      expect(timer.active, isFalse);
    });

    test('a different song playing means it ended (gapless), so it pauses', () async {
      host.songRemaining = const Duration(minutes: 3);
      timer.startEndOfSong();
      host.trackId = 'b';
      host.songRemaining = const Duration(minutes: 4);
      timer.tick();
      await Future<void>.delayed(Duration.zero);
      expect(host.pauses, 1);
    });

    test('repeat one: the same song starting over from its end counts as the end', () async {
      host.songRemaining = const Duration(minutes: 3);
      timer.startEndOfSong();
      host.songRemaining = const Duration(milliseconds: 900);
      timer.tick();
      expect(host.pauses, 0);
      host.songRemaining = const Duration(minutes: 3); // looped
      timer.tick();
      await Future<void>.delayed(Duration.zero);
      expect(host.pauses, 1);
    });

    test('a seek back in the middle of the song does not end it', () {
      host.songRemaining = const Duration(minutes: 1);
      timer.startEndOfSong();
      host.songRemaining = const Duration(minutes: 3);
      timer.tick();
      expect(timer.active, isTrue);
      expect(host.pauses, 0);
    });

    test('+10 minutes turns it into a countdown of the rest of the song plus 10 minutes', () {
      host.songRemaining = const Duration(minutes: 2);
      timer.startEndOfSong();
      timer.extend();
      expect(timer.mode, SleepMode.countdown);
      expect(timer.remaining, const Duration(minutes: 12));
    });
  });

  group('curve and text', () {
    test('the fade curve goes from 1 to 0, gently at both ends', () {
      expect(SleepTimer.fadeCurve(1), 1);
      expect(SleepTimer.fadeCurve(0), 0);
      expect(SleepTimer.fadeCurve(0.5), closeTo(0.5, 1e-9));
      var last = 1.0;
      for (var i = 99; i >= 0; i--) {
        final g = SleepTimer.fadeCurve(i / 100);
        expect(g, lessThanOrEqualTo(last));
        last = g;
      }
      // Slow to start and to finish: the first and last percent change the level very little.
      expect(1 - SleepTimer.fadeCurve(0.99), lessThan(0.001));
      expect(SleepTimer.fadeCurve(0.01), lessThan(0.001));
    });

    test('the time left reads as a clock', () {
      expect(SleepTimer.clock(const Duration(minutes: 29, seconds: 41)), '29:41');
      expect(SleepTimer.clock(const Duration(hours: 1, minutes: 2, seconds: 10)), '1:02:10');
      expect(SleepTimer.clock(const Duration(milliseconds: 100)), '0:01');
      expect(SleepTimer.clock(Duration.zero), '0:00');
    });

    test('the presets are the ones asked for', () => expect(SleepTimer.presets, [15, 30, 45, 60, 90]));
  });
}
