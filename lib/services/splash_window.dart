import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../platform/host.dart';
import 'layout_prefs.dart';

/// The desktop launch's frameless, see-through intro window: only the animated mark floats on the desktop, then the
/// window turns into the app's own (sized, framed, opaque or as Appearance says) and appears.
///
/// Windows and Linux. Windows clears the window through the runner's island mode (`setIsland`, the same clear window
/// the mini player's island uses); Linux windows already have an alpha channel. macOS plays the intro inside the
/// normal window, where the see-through mode always blurs what is behind it.
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
  static Future<void> get appShown => active.value ? _appShown.future : Future<void>.value();
  static Size _appSize = const Size(1280, 820);
  static Size _appMinimum = const Size(320, 420);

  /// Whether this launch opens in the intro window: Windows or Linux with full motion (Reduced, Off and Lightweight
  /// open the app directly, with the plain mark).
  static bool get wanted => (Host.isWindows || Host.isLinux) && LayoutPrefs.effectiveMotion == Motion.full;

  /// Turns the not yet shown window into the intro window. False if the runner couldn't clear it: the app then opens
  /// at [appSize] as usual (the intro plays inside it).
  static Future<bool> open({required Size appSize, required Size appMinimum}) async {
    _appSize = appSize;
    _appMinimum = appMinimum;
    try {
      if (Host.isWindows) {
        await _channel.invokeMethod('setSwitcherVisible', false);
        await _channel.invokeMethod('setIsland', [0.0, 0.0, size.width, size.height]);
      }
      await windowManager.setResizable(false);
      await windowManager.setSkipTaskbar(true);
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
    if (!active.value) return;
    try {
      await windowManager.show();
    } catch (e) {
      debugPrint('Intro window not shown: $e');
    }
  }

  /// After the intro: hides the window and gives it back the app's frame, size and place. [reveal] shows it once the
  /// app has drawn its first frame.
  static Future<void> close() async {
    if (!active.value) return;
    try {
      await windowManager.hide();
    } catch (e) {
      debugPrint('Intro window not hidden: $e');
    }
    await _toApp();
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
