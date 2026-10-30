import 'package:flutter/widgets.dart';

import '../debug_switches.dart';

/// Builds [placeholder] for the first frame and [child] from the next one on.
///
/// Start-up draws the window's frame (title bar, nav, player bar) first and fills the heavy sections in the
/// frames right after it, so the window appears sooner. Once [child] is in, it stays: later rebuilds never
/// bring the placeholder back. A gate that opens in a tree that is already on screen (a page opened later)
/// shows [child] at once: only the very first frame of the app waits.
class FirstFrameGate extends StatefulWidget {
  const FirstFrameGate({super.key, required this.child, this.placeholder = const SizedBox.expand()});

  final Widget child;
  final Widget placeholder;

  /// True once the app has drawn its first frame; set by the gate itself, reset only by tests.
  static bool get opened => _opened;
  static bool _opened = false;

  @visibleForTesting
  static void reset() => _opened = false;

  @override
  State<FirstFrameGate> createState() => _FirstFrameGateState();
}

class _FirstFrameGateState extends State<FirstFrameGate> {
  late bool _open = FirstFrameGate._opened || DebugSwitches.noFirstFrameGate;

  @override
  void initState() {
    super.initState();
    if (_open) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FirstFrameGate._opened = true;
      if (mounted) setState(() => _open = true);
    });
  }

  @override
  Widget build(BuildContext context) => _open ? widget.child : widget.placeholder;
}
