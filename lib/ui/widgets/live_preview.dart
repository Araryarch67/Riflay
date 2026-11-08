import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/appearance.dart';
import '../../services/layout_prefs.dart';
import '../debug_switches.dart';

/// The real widgets an option changes, laid out at [canvas] (a phone's Now Playing, a tab bar) and drawn small: how
/// they look now, in Settings.
///
/// It stands still ([TickerMode] off, animations off, no hero flights, no pointer), so a preview on screen asks
/// for no frames and leases nothing (no visualizer bank, no music video); a change to Layout or Appearance builds
/// it afresh, as an implicit animation frozen part-way would show the old look. Covers decode at the size drawn.
/// `RIFLAY_MOVING_PREVIEWS` lets it move, to tell whether a bug is the freezing's.
class LivePreview extends StatefulWidget {
  const LivePreview({super.key, required this.canvas, required this.child});

  /// The size the widgets are laid out at; an infinite height takes the child's own.
  final Size canvas;
  final Widget child;

  /// Whether [context] is inside a preview: what would start a player or a native surface draws its still
  /// picture instead.
  static bool of(BuildContext context) => context.getInheritedWidgetOfExactType<_InPreview>() != null;

  @override
  State<LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<LivePreview> {
  final _looks = Listenable.merge([LayoutPrefs.instance, Appearance.instance]);
  var _version = 0;

  @override
  void initState() {
    super.initState();
    _looks.addListener(_changed);
  }

  @override
  void dispose() {
    _looks.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() => _version++);

  @override
  Widget build(BuildContext context) {
    final moving = DebugSwitches.movingPreviews;
    final canvas = widget.canvas;
    return LayoutBuilder(
      builder: (context, box) {
        var scale = box.maxWidth / canvas.width;
        if (canvas.height.isFinite && box.maxHeight.isFinite) scale = math.min(scale, box.maxHeight / canvas.height);
        final mq = MediaQuery.of(context);
        final inner = MediaQuery(
          data: mq.copyWith(
            size: Size(canvas.width, canvas.height.isFinite ? canvas.height : mq.size.height),
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.zero,
            viewInsets: EdgeInsets.zero,
            devicePixelRatio: mq.devicePixelRatio * math.min(1, scale),
            disableAnimations: !moving,
          ),
          child: SizedBox(
            width: canvas.width,
            height: canvas.height.isFinite ? canvas.height : null,
            child: moving ? widget.child : KeyedSubtree(key: ValueKey(_version), child: widget.child),
          ),
        );
        return RepaintBoundary(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: ExcludeFocus(
                child: HeroMode(
                  enabled: false,
                  child: TickerMode(
                    enabled: moving,
                    child: _InPreview(
                      child: SizedBox(
                        width: canvas.width * scale,
                        height: canvas.height.isFinite ? canvas.height * scale : null,
                        child: FittedBox(fit: BoxFit.contain, alignment: Alignment.topCenter, child: inner),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InPreview extends InheritedWidget {
  const _InPreview({required super.child});

  @override
  bool updateShouldNotify(_InPreview oldWidget) => false;
}
