import 'dart:async';
import 'dart:math' as math;

import '../ui/debug_switches.dart';

/// One clock for everything on screen that moves by itself: the seek bars, the
/// karaoke fill and the audio-reactive views.
///
/// Each used to run its own timer. On a 144-240 Hz display their ticks rarely
/// fell in the same vsync, so two 60 fps timers asked for up to 120 frames a
/// second, each one a full pass on the GPU. Driven by this one 60 Hz timer,
/// whatever changes in a beat is drawn in a single frame. Views that need less
/// take every second or fourth beat ([UiBeatListener.period]), counted on one
/// clock: two 20 fps views and a seek bar ticking 8 times a second land on the
/// same beats and draw 20 frames a second, not one set each. Each frame costs the
/// window's own work too (on Linux the main thread spends far more on a frame than
/// Dart does), so frames that coincide are what keeps a playing song cheap.
class UiBeat {
  UiBeat._();

  /// 60 Hz: the most any view here is drawn at.
  static const period = Duration(microseconds: 16667);

  static final _listeners = <UiBeatListener>[];
  static Timer? _timer;
  static int _last = 0;

  /// Calls [onBeat] about every [every] (rounded to whole beats; at least one)
  /// with the time since its last call, until [UiBeatListener.cancel].
  static UiBeatListener listen(Duration every, void Function(Duration elapsed) onBeat) {
    final l = UiBeatListener._(every, onBeat);
    _listeners.add(l);
    _timer ??= Timer.periodic(period, _beat);
    return l;
  }

  /// Beats between calls for [every]: whole beats, and from three on a multiple of three, so every view slower
  /// than 20 fps fires on beats a 20 fps view fires on too.
  static int beatsFor(Duration every) {
    // Half a beat early is on time: a 33 ms view fires on every second beat, not every third.
    final n = math.max(1, ((every.inMicroseconds + period.inMicroseconds ~/ 2) ~/ period.inMicroseconds));
    return n < 3 || DebugSwitches.unalignedBeats ? n : (n / 3).round() * 3;
  }

  static void _beat(Timer t) {
    // Beats the timer could not keep up with still count, so motion keeps its speed.
    final elapsed = period * (t.tick - _last);
    _last = t.tick;
    for (final l in List.of(_listeners)) {
      if (!l._active) continue;
      l._waited += elapsed;
      final n = beatsFor(l.period);
      // On the shared count (a missed beat can't make a view skip its turn); unaligned, its own.
      final due = DebugSwitches.unalignedBeats
          ? l._waited + period ~/ 2 >= period * n
          : t.tick % n == 0 || l._waited >= period * n;
      if (due) {
        final waited = l._waited;
        l._waited = Duration.zero;
        l._onBeat(waited);
      }
    }
  }

  /// Views listening now (tool/cpu.sh prints it: a paused player should have none, or the timer keeps waking).
  static int get listeners => _listeners.length;

  static void _remove(UiBeatListener l) {
    _listeners.remove(l);
    if (_listeners.isEmpty) {
      _timer?.cancel();
      _timer = null;
      _last = 0;
    }
  }
}

/// A view's place on [UiBeat].
class UiBeatListener {
  UiBeatListener._(this.period, this._onBeat);

  /// How often it wants a call.
  Duration period;
  final void Function(Duration elapsed) _onBeat;
  Duration _waited = Duration.zero;
  bool _active = true;

  void cancel() {
    if (!_active) return;
    _active = false;
    UiBeat._remove(this);
  }
}
