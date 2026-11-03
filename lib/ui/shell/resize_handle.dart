import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/layout_prefs.dart';
import '../theme.dart';

/// The gap between two desktop panels, as a drag handle: a 1 px divider that takes the accent colour
/// under the pointer. Reports each move through [onDrag] (pixels to the right) and the end through [onEnd],
/// so the shell can save once; a double click calls [onReset].
class ResizeHandle extends StatefulWidget {
  const ResizeHandle({
    super.key,
    required this.label,
    required this.onDrag,
    required this.onEnd,
    required this.onReset,
    this.width = 8,
  });

  /// What it resizes, for screen readers.
  final String label;
  final double width;
  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;
  final VoidCallback onReset;

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  bool _hover = false;
  bool _drag = false;

  @override
  Widget build(BuildContext context) {
    final active = _hover || _drag;
    return Semantics(
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) => setState(() => _drag = true),
          onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
          onHorizontalDragEnd: (_) {
            setState(() => _drag = false);
            widget.onEnd();
          },
          onHorizontalDragCancel: () {
            if (!_drag) return;
            setState(() => _drag = false);
            widget.onEnd();
          },
          onDoubleTap: widget.onReset,
          child: SizedBox(
            width: widget.width,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 1,
                color: active ? AppColors.accent.withValues(alpha: _drag ? 0.9 : 0.6) : Colors.transparent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The widths the two desktop sidebars take in a window [window] wide, whatever was asked for.
/// The pages in between keep at least [minContent]; the panels keep their own minimums.
class SidebarFit {
  const SidebarFit._();

  static const minContent = 480.0;

  /// Window padding (2 x 8) and the gaps between the panels.
  static const _chrome = 16.0 + 8.0;

  static double _room(double window, bool sideOpen) => window - _chrome - (sideOpen ? 8 : 0) - minContent;

  /// The library sidebar's width for [want]; the side panel keeps its minimum when it is open.
  static double left(double want, double window, {required bool sideOpen}) {
    final max = math.min(LayoutPrefs.sidebarMax, _room(window, sideOpen) - (sideOpen ? LayoutPrefs.sidePanelMin : 0));
    return want.clamp(LayoutPrefs.sidebarMin, math.max(LayoutPrefs.sidebarMin, max));
  }

  /// The side panel's width for [want], next to a sidebar [left] wide.
  static double right(double want, double window, {required double left}) {
    final max = math.min(LayoutPrefs.sidePanelMax, _room(window, true) - left);
    return want.clamp(LayoutPrefs.sidePanelMin, math.max(LayoutPrefs.sidePanelMin, max));
  }
}
