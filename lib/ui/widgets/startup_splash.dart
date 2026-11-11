import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_logo.dart';

/// Shows the app mark briefly while the library loads, once per launch.
class StartupSplash extends StatefulWidget {
  const StartupSplash({super.key, required this.ready, required this.child});

  final Future<void> ready;
  final Widget child;

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash> {
  Timer? _timer;
  bool _loaded = false;
  bool _elapsed = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) => _finished
      ? widget.child
      : ColoredBox(
          color: AppColors.of(context).background,
          child: Center(
            child: Semantics(label: 'Riflay', image: true, child: const AppLogo(size: 96)),
          ),
        );
}
