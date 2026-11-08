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
/// frames touch fault back in (CPU time, and stutter). Linux pages the app out the
/// same way (`MADV_PAGEOUT`), while hidden or left alone behind another window.
/// Android frees its allocator's spare pages after a song change and once a minute, and in the background drops
/// decoded covers too: Android closes the apps holding the most memory first, and a low-end phone ended the music.
/// It runs in a background isolate rather than on the UI thread.
abstract final class MemoryTrim {
  // Not in widget tests either: their fake clock fails on timers left running.
  static final bool _available =
      (Host.isLinux || Host.isWindows || (Host.isAndroid && !const bool.fromEnvironment('RIFLAY_NO_ANDROID_TRIM'))) &&
      !Host.environment.containsKey('FLUTTER_TEST');

  /// How long without a pointer or key event before the window counts as idle.
  static const _idleAfter = Duration(seconds: 8);

  /// Linux: paged out since the window was last in use. Paging out compresses the pages into zram on the thread that
  /// asks (~0.5 s of CPU for a couple of hundred MB), and what the song needs faults straight back in: repeated every
  /// minute away, it was a spike btop showed every minute. Once per time away is enough. Windows only moves its pages
  /// to the standby list, so it keeps emptying the working set each minute.
  static bool _pagedOut = false;

  static void _trim({bool workingSet = false}) {
    if (workingSet && Host.isLinux) {
      if (_pagedOut) {
        workingSet = false;
      } else {
        _pagedOut = true;
      }
    }
    final pageOut = workingSet;
    inBackground(() => trimProcessMemory(workingSet: pageOut)).ignore();
  }

  static Timer? _soon;
  static Timer? _every;
  static DateTime _lastInput = DateTime.now();
  static bool _listening = false;
  static bool _hidden = false;

  static bool get _idle => DateTime.now().difference(_lastInput) >= _idleAfter;

  /// Another window has the focus (or this one does: true). See [focus].
  static bool _focused = true;

  /// Nobody is using the window: hidden, or untouched for a while; on Linux also with another window in front, so
  /// lyrics read without the mouse don't fault back in every minute.
  static bool get _away => _hidden || (_idle && (Host.isWindows || !_focused));

  /// Empties the working set while idle or hidden: Windows, and Linux, where btop and the system monitor showed a
  /// window left playing behind others at its peak. Off on Linux with `RIFLAY_NO_PAGE_OUT`.
  static final bool _pagesOut = Host.isWindows || (Host.isLinux && !const bool.fromEnvironment('RIFLAY_NO_PAGE_OUT'));

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

  static void _tick() => _trim(workingSet: _pagesOut && _away);

  /// Empties the working set once the window is idle, looking again every [_idleAfter] until it is.
  static void _whenIdle() {
    if (_away) return _trim(workingSet: _pagesOut);
    // Linux, back in front: the next time it loses the focus starts this again ([focus]).
    if (Host.isLinux && _focused && !_hidden) return;
    _soon = Timer(_idleAfter, _whenIdle);
  }

  /// Trims a few seconds from now (after a song change has settled), and
  /// once a minute from then on.
  static void schedule() {
    if (!_available) return;
    _listen();
    _every ??= Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    _soon?.cancel();
    _soon = Timer(const Duration(seconds: 4), () {
      _trim(workingSet: _pagesOut && _away);
      // Still in use: the working set goes back once nobody has touched the window for a while, not at the next
      // minute (after a start or a song change it stood near its peak, ~190 MB on Windows, for up to a minute).
      if (_pagesOut && !_away) _soon = Timer(_idleAfter, _whenIdle);
    });
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
      _trim(workingSet: _pagesOut);
    });
  }

  /// Whether the window has the focus. On Linux, losing it pages the app out once it has been left alone for
  /// [_idleAfter]: someone looking at btop or the system monitor, or working in another window, while a song plays.
  static void focus(bool focused) {
    if (!_available || focused == _focused) return;
    _focused = focused;
    if (focused) _pagedOut = false;
    if (focused || !Host.isLinux || !_pagesOut || _hidden) return;
    _listen();
    _soon?.cancel();
    _soon = Timer(_idleAfter, _whenIdle);
  }

  /// The window is shown again: caches get their normal budgets back.
  static void shown() {
    if (!_hidden) return;
    _hidden = false;
    _pagedOut = false;
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
