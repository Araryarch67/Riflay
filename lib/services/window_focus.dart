import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_visibility.dart';

/// Keeps the app's lifecycle in step with the window's focus on computers.
///
/// Decorations, marquees, the seek bar's pace and Video mode follow `resumed` (in front, focused) against `inactive`
/// (another window has the focus). Windows reports focus changes, but not the state a window opens in: one that
/// starts behind another (launched from a terminal, a link, the startup folder) stayed `resumed`, and Balanced drew
/// 20 frames a second for nobody. The engine also only reports changes from what it last sent, so once the app is
/// told `inactive` here, getting the focus must say `resumed` here too.
class WindowFocus with WindowListener {
  WindowFocus._();

  static WindowFocus? _instance;
  int _revision = 0;

  /// Starts once the window is shown.
  static Future<void> start() async {
    if (_instance != null) return;
    final focus = _instance = WindowFocus._();
    final visibility = DesktopVisibility.instance..start();
    visibility.addListener(focus._visibilityChanged);
    windowManager.addListener(focus);
    await focus._visibilityChanged();
  }

  Future<void> _visibilityChanged() async {
    final revision = ++_revision;
    if (!DesktopVisibility.instance.value) {
      _tell(AppLifecycleState.hidden);
      return;
    }
    try {
      final focused = await windowManager.isFocused();
      if (revision == _revision) _tell(focused ? AppLifecycleState.resumed : AppLifecycleState.inactive);
    } catch (e) {
      debugPrint('Window focus unknown: $e');
      // A restored window can draw even if native focus information isn't available.
      if (revision == _revision && WidgetsBinding.instance.lifecycleState == AppLifecycleState.hidden) {
        _tell(AppLifecycleState.inactive);
      }
    }
  }

  @override
  void onWindowFocus() => _focusChanged(AppLifecycleState.resumed);

  @override
  void onWindowBlur() => _focusChanged(AppLifecycleState.inactive);

  void _focusChanged(AppLifecycleState state) {
    if (!DesktopVisibility.instance.value) return;
    _revision++;
    _tell(state);
  }

  void _tell(AppLifecycleState state) {
    final now = WidgetsBinding.instance.lifecycleState;
    if (now == null || now == AppLifecycleState.detached || now == state) return;
    // As the engine says it, so every listener (and AppLifecycleListener's transitions) sees one change.
    ui.channelBuffers.push(
      SystemChannels.lifecycle.name,
      SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
      (_) {},
    );
  }
}
