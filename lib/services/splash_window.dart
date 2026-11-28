import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../platform/host.dart';
import 'layout_prefs.dart';

/// The frameless, see-through desktop intro. Windows uses the runner's island
/// mode. Linux already has an alpha channel and keeps the same mapped window
/// through the handoff to let the compositor manage its placement.
abstract final class SplashWindow {
  /// The intro window's size, in logical pixels: room for the mark, its shock ring and the wordmark, drawn
  /// `DesktopIntro.desktopScale` times larger here, and for it to grow as it leaves.
  static const size = Size(780, 630);

  /// While the intro window is up: the frame paints no background or title bar.
  static final active = ValueNotifier(false);

  static const _channel = MethodChannel('riflay/window');
  static final _appShown = Completer<void>();

  /// Completes once the app's own window is up, at once when there was no intro window. What needs the window's
  /// taskbar button (Windows' thumbnail buttons) waits for it: the intro window has none.
  static Future<void> get appShown => active.value && !Host.isLinux ? _appShown.future : Future<void>.value();
  static Size _appSize = const Size(1280, 820);
  static Size _appMinimum = const Size(320, 420);

  /// Whether this launch opens in the intro window: Windows or Linux with full motion (Reduced, Off and Lightweight
  /// open the app directly, with the plain mark).
  static bool get wanted => (Host.isWindows || Host.isLinux) && LayoutPrefs.effectiveMotion == Motion.full;

  /// Turns the not yet shown window into the intro window. False if the runner couldn't clear it: the app then opens
  /// at [appSize] as usual (the intro plays inside it).
  static Future<bool> open({required Size appSize, required Size appMinimum}) async {
    if (Host.isLinux) {
      active.value = true;
      return true;
    }
    _appSize = appSize;
    _appMinimum = appMinimum;
    try {
      await windowManager.setResizable(false);
      await windowManager.setSkipTaskbar(true);
      if (Host.isWindows) {
        // After setResizable: it drops the resize frame without a frame change, which setSwitcherVisible applies.
        // The island's region is measured last, on the final frame, or a strip of the window's border shows.
        await _channel.invokeMethod('setSwitcherVisible', false);
        await _channel.invokeMethod('setIsland', [0.0, 0.0, size.width, size.height]);
      }
      active.value = true;
      return true;
    } catch (e) {
      debugPrint('Intro window not made, opening the app window: $e');
      await _toApp();
      return false;
    }
  }

  /// Shows the intro window once its first frame is drawn (never an empty rectangle before it).
  static Future<void> show() async {
    if (!active.value || Host.isLinux) return;
    try {
      await windowManager.show();
    } catch (e) {
      debugPrint('Intro window not shown: $e');
    }
  }

  /// After the intro, bring back the app's frame. Keeping Linux mapped lets the
  /// compositor deliver the frame that replaces the intro.
  static Future<void> close() async {
    if (!active.value) return;
    if (!Host.isLinux) {
      try {
        await windowManager.hide();
      } catch (e) {
        debugPrint('Intro window not hidden: $e');
      }
      await _toApp();
    }
    active.value = false;
  }

  static Future<void> _toApp() async {
    try {
      if (Host.isWindows) {
        await _channel.invokeMethod('setSwitcherVisible', true);
        await _channel.invokeMethod('setIsland', <double>[]);
      }
    } catch (e) {
      debugPrint('Intro window not cleared: $e');
    }
    try {
      await windowManager.setSkipTaskbar(false);
      await windowManager.setResizable(true);
      await windowManager.setMinimumSize(_appMinimum);
      await windowManager.setSize(_appSize);
      await windowManager.center();
    } catch (e) {
      debugPrint('App window not restored after the intro: $e');
    }
  }

  /// Shows the app's window (the system's own opening animation plays) and gives it the focus.
  static Future<void> reveal() async {
    if (Host.isLinux) return;
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('App window not shown after the intro: $e');
    }
    // The shell makes the taskbar button a moment after the window shows.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!_appShown.isCompleted) _appShown.complete();
  }
}
