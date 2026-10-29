import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// What the sleep timer is waiting for.
enum SleepMode {
  off,

  /// Pauses at a moment in time.
  countdown,

  /// Pauses when the song that was playing ends.
  endOfSong,
}

/// What the sleep timer needs from the player (so it can be tested without one).
abstract interface class SleepHost {
  bool get playing;

  /// Identifies the current song, so a change of song can be told from a seek.
  String? get trackId;

  /// Time left in the current song, null while unknown.
  Duration? get songRemaining;

  /// Scales the volume by [gain] (0-1), without touching the volume the user set.
  void setFade(double gain);

  Future<void> pause();
}

/// "Stop the music in 30 minutes": counts down, fades the volume over the last
/// seconds, pauses, and leaves the volume as it was.
///
/// The deadline is a wall-clock time and every tick works out what is left from
/// it, never by counting ticks. A phone with its screen off, or a computer that
/// slept, delivers timers late or not at all; the next tick then still pauses
/// at the right time (or at once, if the time has passed).
class SleepTimer extends ChangeNotifier {
  SleepTimer({
    DateTime Function()? now,
    this.fade = const Duration(seconds: 30),
    this.songFade = const Duration(seconds: 8),
    this.restoreDelay = const Duration(milliseconds: 400),
  }) : _now = now ?? DateTime.now;

  /// The choices in the menu, in minutes.
  static const presets = [15, 30, 45, 60, 90];

  /// How much "+10 min" adds.
  static const extension = Duration(minutes: 10);

  final DateTime Function() _now;

  /// How long the volume fades down before a countdown ends.
  final Duration fade;

  /// The same before the end of a song ("End of this song"): shorter, so most of the song plays at full volume.
  final Duration songFade;

  /// Time between pausing and giving the volume back, so no sound is left in the output.
  final Duration restoreDelay;

  SleepHost? _host;
  SleepMode _mode = SleepMode.off;
  DateTime? _deadline;
  String? _armedTrack;
  Duration? _lastSongLeft;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  int? _shownSeconds;
  double _gain = 1;
  Timer? _timer;
  Timer? _ramp;

  /// Connects the player. The timer does nothing before.
  void attach(SleepHost host) => _host = host;

  SleepMode get mode => _mode;
  bool get active => _mode != SleepMode.off;

  /// When a countdown ends (null for the others).
  DateTime? get deadline => _mode == SleepMode.countdown ? _deadline : null;

  /// The volume factor right now, 1 when not fading.
  double get fadeGain => _gain;

  /// Time left: until the deadline, or the rest of the song. Null when off or not known yet.
  Duration? get remaining => active ? _left(_now()) : null;

  Duration? _left(DateTime now) {
    switch (_mode) {
      case SleepMode.off:
        return null;
      case SleepMode.countdown:
        final left = _deadline!.difference(now);
        return left.isNegative ? Duration.zero : left;
      case SleepMode.endOfSong:
        final left = _host?.songRemaining;
        if (left == null) return null;
        return left.isNegative ? Duration.zero : left;
    }
  }

  /// Pauses in [after].
  void start(Duration after) {
    if (after <= Duration.zero) return cancel();
    _begin(SleepMode.countdown, _now().add(after));
  }

  /// Pauses at [when] (a time of day, today or tomorrow, whichever comes next).
  void startAt(int hour, int minute) {
    final now = _now();
    var at = DateTime(now.year, now.month, now.day, hour, minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    _begin(SleepMode.countdown, at);
  }

  /// Pauses when the song now playing ends.
  void startEndOfSong() {
    _begin(SleepMode.endOfSong, null);
    _armedTrack = _host?.trackId;
    _lastSongLeft = _host?.songRemaining;
  }

  /// "+10 min". Starts a countdown if the timer was off or waiting for a song's end.
  void extend([Duration by = extension]) {
    if (_mode == SleepMode.countdown) {
      _deadline = _deadline!.add(by);
      _shownSeconds = null;
      tick();
    } else {
      final base = _mode == SleepMode.endOfSong ? (_left(_now()) ?? Duration.zero) : Duration.zero;
      start(base + by);
    }
  }

  /// Turns the timer off; a fade in progress eases back up instead of jumping.
  void cancel() {
    if (_mode == SleepMode.off) return;
    _mode = SleepMode.off;
    _deadline = null;
    _armedTrack = null;
    _timer?.cancel();
    _easeBack();
    notifyListeners();
  }

  void _begin(SleepMode mode, DateTime? deadline) {
    _mode = mode;
    _deadline = deadline;
    _armedTrack = null;
    _lastSongLeft = null;
    _shownSeconds = null;
    _lastTick = _now();
    _ramp?.cancel();
    notifyListeners();
    tick();
  }

  /// Works out what is left from the clock and acts on it. Called by its own
  /// timer; public so a test can step a fake clock.
  @visibleForTesting
  void tick() {
    _timer?.cancel();
    final host = _host;
    if (_mode == SleepMode.off || host == null) return;
    final now = _now();
    final dt = now.difference(_lastTick);
    _lastTick = now;

    if (_mode == SleepMode.endOfSong && _songEnded(host)) {
      unawaited(_finish());
      return;
    }
    final left = _left(now);
    if (left != null && left <= _margin) {
      unawaited(_finish());
      return;
    }
    final window = _mode == SleepMode.countdown ? fade : songFade;
    final target = left == null || left >= window ? 1.0 : fadeCurve(left.inMicroseconds / window.inMicroseconds);
    _setGain(_slew(target, dt));

    final seconds = left?.inSeconds;
    if (seconds != _shownSeconds) {
      _shownSeconds = seconds;
      notifyListeners();
    }
    _timer = Timer(_nextTick(left, window), tick);
  }

  /// A song's end counts when the end is this close.
  static const _margin = Duration(milliseconds: 120);

  /// Whether the song armed by [startEndOfSong] is over: another song is playing, or
  /// (repeat one) the same song started again from near its end.
  bool _songEnded(SleepHost host) {
    final id = host.trackId;
    if (_armedTrack != null && id != null && id != _armedTrack) return true;
    _armedTrack ??= id;
    final left = host.songRemaining;
    final before = _lastSongLeft;
    _lastSongLeft = left;
    return left != null &&
        before != null &&
        before < const Duration(milliseconds: 1500) &&
        left > before + const Duration(seconds: 2);
  }

  Duration _nextTick(Duration? left, Duration window) {
    if (left == null) return const Duration(seconds: 1);
    // Fading: smooth steps. Otherwise wake when the shown second changes, or when the fade is due.
    if (left <= window + const Duration(seconds: 1)) return const Duration(milliseconds: 100);
    final toSecond = left.inMilliseconds % 1000 + 30;
    final toFade = (left - window).inMilliseconds;
    return Duration(milliseconds: math.max(50, math.min(math.min(toSecond, toFade), 1000)));
  }

  /// Heard as a steady, gentle fade: slow at the start and at the very end.
  /// [remaining] is the share of the fade still to go (1 at its start, 0 at the end).
  static double fadeCurve(double remaining) {
    final x = remaining.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  /// Down follows the curve; up (after "+10 min") takes two seconds, so it never steps.
  double _slew(double target, Duration dt) {
    if (target <= _gain) return target;
    final up = dt.inMicroseconds / const Duration(seconds: 2).inMicroseconds;
    return math.min(target, _gain + math.max(up, 0.001));
  }

  void _setGain(double gain) {
    if ((gain - _gain).abs() < 0.002 && gain != 1 && gain != 0) return;
    _gain = gain;
    _host?.setFade(gain);
  }

  Future<void> _finish() async {
    final host = _host;
    _mode = SleepMode.off;
    _deadline = null;
    _armedTrack = null;
    _timer?.cancel();
    notifyListeners();
    if (host == null) return;
    _gain = 0;
    host.setFade(0);
    try {
      if (host.playing) await host.pause();
    } catch (e) {
      debugPrint('Sleep timer could not pause: $e');
    } finally {
      // The next time the music plays it is at the volume the user set.
      if (restoreDelay > Duration.zero) await Future<void>.delayed(restoreDelay);
      if (_mode == SleepMode.off) {
        _gain = 1;
        host.setFade(1);
      }
    }
  }

  void _easeBack() {
    _ramp?.cancel();
    if (_gain >= 1) return;
    _ramp = Timer.periodic(const Duration(milliseconds: 100), (t) {
      _gain = math.min(1, _gain + 0.05);
      _host?.setFade(_gain);
      if (_gain >= 1) t.cancel();
    });
  }

  /// "29:41", "1:02:10".
  static String clock(Duration d) {
    final s = (d.inMilliseconds / 1000).ceil();
    final h = s ~/ 3600, m = s % 3600 ~/ 60, sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ramp?.cancel();
    _host?.setFade(1);
    super.dispose();
  }
}
