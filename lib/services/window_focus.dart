import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

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

  /// Starts once the window is shown.
  static Future<void> start() async {
    if (_instance != null) return;
    final focus = _instance = WindowFocus._();
    windowManager.addListener(focus);
    try {
      if (!await windowManager.isFocused()) focus._tell(AppLifecycleState.inactive);
    } catch (e) {
      debugPrint('Window focus unknown: $e');
    }
  }

  @override
  void onWindowFocus() => _tell(AppLifecycleState.resumed);

  @override
  void onWindowBlur() => _tell(AppLifecycleState.inactive);

  /// Only between `resumed` and `inactive`: a hidden or minimized window is the engine's to report.
  void _tell(AppLifecycleState state) {
    final now = WidgetsBinding.instance.lifecycleState;
    if (now != AppLifecycleState.resumed && now != AppLifecycleState.inactive) return;
    if (now == state) return;
    // As the engine says it, so every listener (and AppLifecycleListener's transitions) sees one change.
    ui.channelBuffers.push(
      SystemChannels.lifecycle.name,
      SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
      (_) {},
    );
  }
}
