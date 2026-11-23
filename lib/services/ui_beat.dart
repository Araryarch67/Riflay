import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';

import '../ui/debug_switches.dart';

/// One clock for everything on screen that moves by itself: the seek bars, the
/// karaoke fill and the audio-reactive views.
///
/// One shared 60 Hz timer, so whatever changes in a beat is drawn in a single frame: separate timers rarely share a
/// vsync on a 144-240 Hz display and multiply full GPU passes (and, on Linux, the window's own per-frame work).
/// Slower views take every second or fourth beat ([UiBeatListener.period]) on the same count, so their frames coincide.
class UiBeat {
  UiBeat._();

  /// 60 Hz: the most any view here is drawn at.
  static const period = Duration(microseconds: 16667);

  static final _listeners = <UiBeatListener>[];
  static Timer? _timer;
  static int _last = 0;

  /// Beats counted since the clock started, across restarts of [_timer] (views fire on multiples of it).
  static int _count = 0;

  /// Beats between two firings of [_timer]: as many as the busiest view allows. A seek bar ticking once a second
  /// alone wakes the app once a second, not 60 times (each wake-up is the Dart thread's own work, ~5% of a core).
  static int _stride = 1;

  static final _frameListeners = <FrameCallback>{};
  static int? _frameCallback;
  static Duration? _lastFrame;

  /// Shares the display's actual frame clock for visible, time-sensitive painting.
  static VoidCallback listenFrames(FrameCallback onFrame) {
    _frameListeners.add(onFrame);
    _scheduleFrame();
    return () {
      _frameListeners.remove(onFrame);
      if (_frameListeners.isNotEmpty) return;
      if (_frameCallback case final id?) SchedulerBinding.instance.cancelFrameCallbackWithId(id);
      _frameCallback = null;
      _lastFrame = null;
    };
  }

  static void _scheduleFrame() {
    if (_frameListeners.isEmpty || _frameCallback != null) return;
    _frameCallback = SchedulerBinding.instance.scheduleFrameCallback((time) {
      _frameCallback = null;
      final elapsed = time - (_lastFrame ?? time - period);
      _lastFrame = time;
      for (final listener in List.of(_frameListeners)) {
        if (_frameListeners.contains(listener)) listener(elapsed);
      }
      _scheduleFrame();
    });
  }

  /// Calls [onBeat] about every [every] (rounded to whole beats; at least one)
  /// with the time since its last call, until [UiBeatListener.cancel].
  static UiBeatListener listen(Duration every, void Function(Duration elapsed) onBeat) {
    final l = UiBeatListener._(every, onBeat);
    _listeners.add(l);
    _restride();
    return l;
  }

  /// Beats between calls for [every]: whole beats, and from three on a multiple of three, so every view slower
  /// than 20 fps fires on beats a 20 fps view fires on too.
  static int beatsFor(Duration every) {
    // Half a beat early is on time: a 33 ms view fires on every second beat, not every third.
    final n = math.max(1, ((every.inMicroseconds + period.inMicroseconds ~/ 2) ~/ period.inMicroseconds));
    return n < 3 || DebugSwitches.unalignedBeats ? n : (n / 3).round() * 3;
  }

  /// Starts the timer, or starts it again at a new [_stride] when the busiest view's pace changed.
  static void _restride() {
    if (_listeners.isEmpty) return;
    final stride = DebugSwitches.unalignedBeats ? 1 : _listeners.map((l) => beatsFor(l.period)).reduce(math.min);
    if (_timer != null && stride == _stride) return;
    _timer?.cancel();
    _stride = stride;
    _last = 0;
    _timer = Timer.periodic(period * stride, _beat);
  }

  static void _beat(Timer t) {
    // Beats the timer could not keep up with still count, so motion keeps its speed.
    final beats = (t.tick - _last) * _stride;
    _last = t.tick;
    _count += beats;
    final elapsed = period * beats;
    for (final l in List.of(_listeners)) {
      if (!l._active) continue;
      l._waited += elapsed;
      final n = beatsFor(l.period);
      // On the shared count (a missed beat can't make a view skip its turn); unaligned, its own.
      final due = DebugSwitches.unalignedBeats
          ? l._waited + period ~/ 2 >= period * n
          : _count % n == 0 || l._waited >= period * n;
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
      _count = 0;
    } else {
      _restride();
    }
  }
}

/// A view's place on [UiBeat].
class UiBeatListener {
  UiBeatListener._(this._period, this._onBeat);

  /// How often it wants a call.
  Duration get period => _period;
  Duration _period;
  set period(Duration value) {
    if (value == _period) return;
    _period = value;
    if (_active) UiBeat._restride();
  }

  final void Function(Duration elapsed) _onBeat;
  Duration _waited = Duration.zero;
  bool _active = true;

  void cancel() {
    if (!_active) return;
    _active = false;
    UiBeat._remove(this);
  }
}
