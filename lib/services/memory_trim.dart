import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../platform/background.dart';
import '../platform/host.dart';
import '../platform/native_calls.dart';
import 'rendering_memory.dart';

/// Hands memory freed by the engine, mpv and FFmpeg back to the OS.
///
/// glibc keeps freed blocks in its per-thread arenas for reuse, so after a song
/// change or a long scroll the process stays at its peak size; `malloc_trim`
/// releases them. On Windows the heap is compacted after a song change, and the
/// working set is emptied while the window is hidden, or once a minute while
/// nobody is using it: emptying it mid-scroll would make every page the next
/// frames touch fault back in (CPU time, and stutter). It runs in a background
/// isolate rather than on the UI thread.
abstract final class MemoryTrim {
  // Not in widget tests either: their fake clock fails on timers left running.
  static final bool _available = (Host.isLinux || Host.isWindows) && !Host.environment.containsKey('FLUTTER_TEST');

  /// How long without a pointer or key event before the window counts as idle.
  static const _idleAfter = Duration(seconds: 8);

  static void _trim({bool workingSet = false}) =>
      inBackground(() => trimProcessMemory(workingSet: workingSet)).ignore();

  static Timer? _soon;
  static Timer? _every;
  static DateTime _lastInput = DateTime.now();
  static bool _listening = false;
  static bool _hidden = false;

  static bool get _idle => DateTime.now().difference(_lastInput) >= _idleAfter;

  static void _input(PointerEvent _) => _lastInput = DateTime.now();

  static bool _key(KeyEvent _) {
    _lastInput = DateTime.now();
    return false;
  }

  static void _listen() {
    if (_listening) return;
    _listening = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_input);
    HardwareKeyboard.instance.addHandler(_key);
  }

  static void _tick() {
    if (Host.isLinux) return _trim();
    if (_hidden || _idle) _trim(workingSet: true);
  }

  /// Trims a few seconds from now (after a song change has settled), and
  /// once a minute from then on.
  static void schedule() {
    if (!_available) return;
    _listen();
    _every ??= Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    _soon?.cancel();
    _soon = Timer(const Duration(seconds: 4), () => _trim(workingSet: Host.isWindows && _idle));
  }

  /// The window was hidden or minimized: nothing is drawn, so cached images and
  /// GPU resources are dropped and the working set goes back to the system
  /// until it is shown again.
  static void hidden() {
    if (!_available || _hidden) return;
    _hidden = true;
    _listen();
    _every ??= Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    _soon?.cancel();
    _soon = Timer(const Duration(seconds: 2), () async {
      await RenderingMemory.release();
      _trim(workingSet: true);
    });
  }

  /// The window is shown again: caches get their normal budgets back.
  static void shown() {
    if (!_hidden) return;
    _hidden = false;
    _soon?.cancel();
    unawaited(RenderingMemory.restore());
  }

  static void stop() {
    _soon?.cancel();
    _every?.cancel();
    _soon = _every = null;
    if (_listening) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_input);
      HardwareKeyboard.instance.removeHandler(_key);
      _listening = false;
    }
  }
}
