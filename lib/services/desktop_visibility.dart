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

  @override
  void onWindowMinimize() {
    _minimized = true;
    _sync();
  }

  @override
  void onWindowRestore() {
    _minimized = false;
    _sync();
  }

  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'hide') _hidden = true;
    if (eventName == 'show') _hidden = false;
    _sync();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
