import 'dart:async';

import 'package:flutter/material.dart';

/// A bar that, while [enabled], slides out of sight towards its [edge] and comes back while the pointer is over the
/// place where it sits (or something in it has focus, such as the search box). Off, it is simply [child]; the widget
/// tree is the same either way, so the bar keeps its state when the mode changes.
///
/// Used by the desktop expanded player: the title bar and the player bar give the cover the whole window.
class AutoHideBar extends StatefulWidget {
  const AutoHideBar({
    super.key,
    required this.child,
    required this.edge,
    required this.enabled,
    this.hideAfter = const Duration(milliseconds: 900),
    this.firstShow = const Duration(milliseconds: 2500),
    this.shown,
  });

  /// Told whether the bar is in sight, for what makes room for it while it is (the expanded player's top row).
  final ValueNotifier<bool>? shown;

  final Widget child;

  /// [AxisDirection.up] for a bar at the top, [AxisDirection.down] for one at the bottom.
  final AxisDirection edge;
  final bool enabled;

  /// How long it stays after the pointer leaves.
  final Duration hideAfter;

  /// How long it shows on its own when it is enabled, so it is seen to be there.
  final Duration firstShow;

  static const slideIn = Duration(milliseconds: 260);
  static const slideOut = Duration(milliseconds: 420);

  @override
  State<AutoHideBar> createState() => _AutoHideBarState();
}

class _AutoHideBarState extends State<AutoHideBar> {
  bool _hovered = false;
  bool _focused = false;
  bool _lingering = false;
  Timer? _timer;

  bool get _shown => !widget.enabled || _hovered || _focused || _lingering;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _linger(widget.firstShow);
  }

  @override
  void didUpdateWidget(AutoHideBar old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !old.enabled) _linger(widget.firstShow);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Stays shown for [time], then hides unless the pointer or focus is still there.
  void _linger(Duration time) {
    _timer?.cancel();
    _lingering = true;
    _timer = Timer(time, () {
      if (mounted) setState(() => _lingering = false);
    });
  }

  void _hover(bool on) {
    if (!widget.enabled || on == _hovered) return;
    setState(() {
      _hovered = on;
      if (!on) _linger(widget.hideAfter);
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final report = widget.shown;
    if (report != null && report.value != shown) {
      // After this frame: the listeners rebuild, which they may not do while this one builds.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) report.value = _shown;
      });
    }
    final still = MediaQuery.disableAnimationsOf(context);
    final time = still ? Duration.zero : (shown ? AutoHideBar.slideIn : AutoHideBar.slideOut);
    final away = widget.edge == AxisDirection.up ? const Offset(0, -1) : const Offset(0, 1);
    return MouseRegion(
      // Over the bar's place, hidden or not; what lies under it still gets the pointer.
      hitTestBehavior: HitTestBehavior.translucent,
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (on) {
          if (on == _focused) return;
          setState(() {
            _focused = on;
            if (!on && widget.enabled) _linger(widget.hideAfter);
          });
        },
        child: AnimatedSlide(
          offset: shown ? Offset.zero : away,
          duration: time,
          curve: shown ? Curves.easeOutCubic : Curves.easeInCubic,
          child: AnimatedOpacity(
            opacity: shown ? 1 : 0,
            duration: time,
            curve: shown ? Curves.easeOut : Curves.easeIn,
            // Slid away, its seek bar and motion stop: they kept drawing at full rate under an invisible bar.
            child: IgnorePointer(
              ignoring: !shown,
              child: TickerMode(enabled: shown, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
