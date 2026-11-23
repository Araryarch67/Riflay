import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../platform/background.dart';
import '../platform/host.dart';
import '../platform/native_calls.dart';
import 'rendering_memory.dart';

/// Hands memory freed by the engine, mpv and FFmpeg back to the OS.
///
/// glibc keeps freed blocks in its per-thread arenas for reuse, so after a song
/// change or a long scroll the process stays at its peak size; `malloc_trim`
/// releases them. On Windows trimming waits until the window is hidden:
/// compacting the heap or emptying the working set while video or lyrics
/// animate makes the next frames fault those pages back in (CPU and stutter).
/// Linux pages the app out the
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
  /// asks (~0.5 s of CPU for a couple of hundred MB) and what the song needs faults straight back in, so it is done
  /// once per time away. Windows only moves its pages to the standby list, so it keeps emptying the working set each
  /// minute.
  static bool _pagedOut = false;

  static void _trim({bool workingSet = false}) {
    // A visible Windows player is actively using its textures, glyphs and
    // decoder buffers even without mouse input. Compacting/paging it out then
    // faults those pages straight back in on the next video/lyric frame.
    if (Host.isWindows && !_hidden) return;
    if (workingSet && Host.isLinux) {
      if (_pagedOut) {
        workingSet = false;
      } else {
        _pagedOut = true;
      }
    }
    final pageOut = workingSet && !_software;
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
  static bool get _away =>
      _hidden || (!Host.isWindows && _idle && !_focused && DateTime.now().difference(_unfocusedAt) >= _unfocusedFor);

  /// Linux: how long another window must have had the focus before the app is paged out. Paging out compresses
  /// ~200 MB into zram (~0.6 s of CPU) and what plays faults back in: after 8 s, a glance at another window or a
  /// few switches a minute paid that each time. Left behind for a minute it is worth it; minimized, at once.
  static const _unfocusedFor = Duration(seconds: 60);
  static DateTime _unfocusedAt = DateTime.now();

  /// Empties the working set while idle or hidden: Windows, and Linux, where btop and the system monitor showed a
  /// window left playing behind others at its peak. Off on Linux with `RIFLAY_NO_PAGE_OUT`.
  static final bool _pagesOut = Host.isWindows || (Host.isLinux && !const bool.fromEnvironment('RIFLAY_NO_PAGE_OUT'));

  static void _input(PointerEvent _) => _lastInput = DateTime.now();

  static bool _key(KeyEvent _) {
    _lastInput = DateTime.now();
    return false;
  }

  static void _listen() {
    // Windows only trims when hidden: it needs no idle tracking.
    if (Host.isWindows) return;
    if (_listening) return;
    _listening = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_input);
    HardwareKeyboard.instance.addHandler(_key);
  }

  static void _tick() => _trim(workingSet: _pagesOut && _away && !_software);

  /// Windows without a graphics card (WARP, see [windowsSoftwareRendering]): the drawing's textures are in this
  /// process's own memory. Emptying the working set (and Skia's cache) while minimized paged all of them out, and
  /// showing the window again froze it while the processor faulted them back in and drew everything again; music
  /// playing behind a minimized window was paged out each minute too. There the heap is compacted and nothing more.
  static bool get _software => _softwareRendering ??= windowsSoftwareRendering();
  static bool? _softwareRendering;

  /// Empties the working set once the window is idle, looking again every [_idleAfter] until it is.
  static void _whenIdle() {
    if (Host.isWindows && !_hidden) return;
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
      if (_pagesOut && !_away && !Host.isWindows) _soon = Timer(_idleAfter, _whenIdle);
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
      if (_software) return _trim();
      await RenderingMemory.release();
      _trim(workingSet: _pagesOut);
    });
  }

  /// Whether the window has the focus. On Linux, losing it pages the app out once another window has had the focus
  /// for [_unfocusedFor]: someone working in another window while a song plays.
  static void focus(bool focused) {
    if (!_available || focused == _focused) return;
    _focused = focused;
    if (focused) _pagedOut = false;
    if (focused || !Host.isLinux || !_pagesOut || _hidden) return;
    _unfocusedAt = DateTime.now();
    _listen();
    _soon?.cancel();
    _soon = Timer(_unfocusedFor, _whenIdle);
  }

  /// The window is shown again: caches get their normal budgets back (the mini player's smaller ones).
  static void shown() {
    if (!_hidden) return;
    _hidden = false;
    _pagedOut = false;
    _soon?.cancel();
    unawaited(_mini ? RenderingMemory.mini() : RenderingMemory.restore());
  }

  static bool _mini = false;
  static Timer? _miniSoon;

  /// The window became the mini player (true), or the full window again. The app stays alive under the mini
  /// player but draws nothing there: once its music video has let go of its player, the pages' images and GPU
  /// resources go and the working set is handed back, once (the mini player's few pages come straight back).
  static void mini(bool on) {
    if (!_available || on == _mini) return;
    _mini = on;
    _miniSoon?.cancel();
    if (!on) {
      if (!_hidden) unawaited(RenderingMemory.restore());
      return;
    }
    _miniSoon = Timer(const Duration(seconds: 4), () async {
      if (!_mini || _hidden) return;
      await RenderingMemory.mini();
      final pageOut = _pagesOut && !_software;
      inBackground(() => trimProcessMemory(workingSet: pageOut)).ignore();
    });
  }

  /// Another performance mode was picked. Its budgets apply now, not as things come and go: the decoded images
  /// kept off screen go (those on screen are decoded again at the new mode's size), Skia's cache is emptied down to
  /// the new budget, and the process heap is compacted. A lighter mode also hands the working set back once, so the
  /// memory the system shows drops with it (what is in use faults back in; once, not every minute).
  static void performanceChanged({required bool lighter}) {
    if (!_available) return;
    PaintingBinding.instance.imageCache.clear();
    unawaited(() async {
      await RenderingMemory.release();
      await (_mini ? RenderingMemory.mini() : RenderingMemory.restore());
      // After the frames that drop and decode again, so what is trimmed stays trimmed.
      await Future<void>.delayed(const Duration(seconds: 2));
      final pageOut = lighter && (Host.isWindows || _pagesOut) && !_software;
      inBackground(() => trimProcessMemory(workingSet: pageOut)).ignore();
    }());
  }

  static void stop() {
    _soon?.cancel();
    _miniSoon?.cancel();
    _every?.cancel();
    _soon = _every = null;
    if (_listening) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_input);
      HardwareKeyboard.instance.removeHandler(_key);
      _listening = false;
    }
  }
}
