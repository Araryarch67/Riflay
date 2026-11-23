import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../platform/host.dart';

/// Window presence, independent of focus. window_manager consumes Windows'
/// minimize message before Flutter can always translate it into `hidden`.
class DesktopVisibility extends ValueNotifier<bool> with WindowListener {
  DesktopVisibility() : super(true);

  static final instance = DesktopVisibility();
  bool _hidden = false;
  bool _minimized = false;
  bool _started = false;

  void start() {
    if (_started || !(Host.isWindows || Host.isLinux || Host.isMacOS)) return;
    _started = true;
    windowManager.addListener(this);
  }

  void stop() {
    if (!_started) return;
    windowManager.removeListener(this);
    _started = false;
  }

  void _sync() => value = !_hidden && !_minimized;

  /// A window minimized while maximized comes back with "maximize", not "restore" (window_manager reports the state it
  /// returns to). Waiting for "restore" alone left the app believing it was still minimized: no frames, the video and
  /// animations stopped, as if frozen.
  @visibleForTesting
  void handle(String eventName) {
    switch (eventName) {
      case 'minimize':
        _minimized = true;
      case 'hide':
        _hidden = true;
      case 'show':
        _hidden = false;
      case 'restore' || 'maximize' || 'unmaximize' || 'enter-full-screen' || 'leave-full-screen':
        _minimized = false;
      default:
        return;
    }
    _sync();
  }

  @override
  void onWindowEvent(String eventName) => handle(eventName);

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
