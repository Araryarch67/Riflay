import 'dart:async';

import 'package:flutter/material.dart';

import '../../platform/host.dart';
import '../../services/layout_prefs.dart';
import '../../services/splash_window.dart';
import '../theme.dart';
import 'app_logo.dart';
import 'desktop_intro.dart';

/// Shows the app mark while the library loads, once per launch: on native apps with full motion the animated
/// [DesktopIntro] (in its own see-through window where [SplashWindow] made one), otherwise the plain mark briefly.
class StartupSplash extends StatefulWidget {
  const StartupSplash({super.key, required this.ready, required this.child, this.intro});

  final Future<void> ready;
  final Widget child;

  /// Whether to play the animated intro; by default on native apps with full motion (Reduced, Off and
  /// Lightweight keep the plain mark).
  final bool? intro;

  static bool get _introByDefault => !Host.isWeb && LayoutPrefs.effectiveMotion == Motion.full;

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash> {
  // Decided once: a setting changing mid-launch mustn't swap one splash for the other.
  // The intro window always plays the intro: it is what turns the window back into the app's.
  late final bool _window = SplashWindow.active.value;
  late final bool _intro = _window || (widget.intro ?? StartupSplash._introByDefault);
  Timer? _timer;
  bool _loaded = false;
  bool _elapsed = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    if (_intro) return;
    widget.ready.then((_) {
      _loaded = true;
      _finish();
    }).ignore(); // The startup caller owns load errors.
    // Count from the first visible frame, including on a fast launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _timer = Timer(const Duration(milliseconds: 500), () {
        _elapsed = true;
        _finish();
      });
    });
  }

  void _finish() {
    if (mounted && _loaded && _elapsed && !_finished) setState(() => _finished = true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_intro) {
      return DesktopIntro(
        ready: widget.ready,
        transparent: _window,
        onFirstFrame: _window ? SplashWindow.show : null,
        beforeApp: _window ? SplashWindow.close : null,
        afterApp: _window ? SplashWindow.reveal : null,
        child: widget.child,
      );
    }
    return _finished
        ? widget.child
        : ColoredBox(
            color: AppColors.of(context).background,
            child: Center(
              child: Semantics(label: 'Riflay', image: true, child: const AppLogo(size: 96)),
            ),
          );
  }
}
