import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/layout_prefs.dart';

/// One line of text that slides sideways when it doesn't fit, so a long song
/// title can be read whole: it rests at the start for [pause], scrolls at
/// [speed] logical pixels a second until a second copy (after [gap]) takes its
/// place, and starts over. Text that fits stays still. With less motion
/// (Settings › Look & feel › Layout › Motion, or the system's setting) it is cut off with an
/// ellipsis instead.
///
/// Only for a few titles on screen (the player, the lyrics header), never for
/// list rows.
class MarqueeText extends StatefulWidget {
  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.speed = 35,
    this.pause = const Duration(seconds: 2),
    this.gap = 48,
    this.fade = 16,
  });

  final String text;
  final TextStyle? style;

  /// Logical pixels a second.
  final double speed;
  final Duration pause;

  /// Space between the end of the text and the copy that follows it.
  final double gap;

  /// Width of the faded edges while it scrolls.
  final double fade;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();

  /// How often a line of text had to be measured (tests).
  @visibleForTesting
  static int measurements = 0;

  /// Forgets the measured widths (tests).
  @visibleForTesting
  static void clearMeasurements() => _sizes.clear();

  /// Measured size per (text, style, text scale, direction), least recently used first:
  /// the same title is laid out once, not on each build.
  static final _sizes = <(String, TextStyle, double, TextDirection), Size>{};

  static Size _measure(String text, TextStyle style, TextScaler scaler, TextDirection direction) {
    final key = (text, style, scaler.scale(10), direction);
    final known = _sizes.remove(key);
    if (known != null) return _sizes[key] = known;
    measurements++;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: direction,
      textScaler: scaler,
    )..layout();
    final size = Size(painter.width, painter.height);
    painter.dispose();
    _sizes[key] = size;
    if (_sizes.length > 128) _sizes.remove(_sizes.keys.first);
    return size;
  }
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this);

  /// Width of the text the controller is running for; null when still.
  double? _running;

  /// The edge fade, made again only when the width or the left fade changes.
  ui.Shader? _shader;
  (double, bool)? _shaderFor;

  ui.Shader _fadeShader(Rect rect, bool leftFade) {
    final key = (rect.width, leftFade);
    if (_shaderFor == key && _shader != null) return _shader!;
    _shader?.dispose();
    _shaderFor = key;
    final fade = widget.fade / rect.width;
    return _shader = LinearGradient(
      colors: [leftFade ? Colors.transparent : Colors.white, Colors.white, Colors.white, Colors.transparent],
      stops: [0, fade, 1 - fade, 1],
    ).createShader(Rect.fromLTWH(0, 0, rect.width, rect.height));
  }

  @override
  void didUpdateWidget(MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text ||
        old.style != widget.style ||
        old.speed != widget.speed ||
        old.pause != widget.pause ||
        old.gap != widget.gap) {
      _stop();
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _stop() {
    _controller
      ..stop()
      ..value = 0;
    _running = null;
  }

  void _start(double width) {
    if (_running == width) return;
    _running = width;
    final scroll = Duration(microseconds: ((width + widget.gap) / widget.speed * 1e6).round());
    _controller
      ..value = 0
      ..repeat(period: widget.pause + scroll);
  }

  /// How far the text has moved left at controller value [t].
  double _offset(double t, double width) {
    final total = widget.pause.inMicroseconds + (width + widget.gap) / widget.speed * 1e6;
    final moving = (t * total - widget.pause.inMicroseconds) / (total - widget.pause.inMicroseconds);
    return moving <= 0 ? 0 : moving * (width + widget.gap);
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final still = !LayoutPrefs.moves || MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final size = MarqueeText._measure(
          widget.text,
          style,
          MediaQuery.textScalerOf(context),
          Directionality.of(context),
        );
        final width = size.width;
        final height = size.height;

        if (still || !box.hasBoundedWidth || width <= box.maxWidth) {
          if (_running != null) _stop();
          return Text(widget.text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: style);
        }

        // Started after this frame: a ticker shouldn't start mid-build.
        if (_running != width) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _start(width);
          });
        }

        final line = Text(widget.text, maxLines: 1, softWrap: false, style: style);
        final strip = OverflowBox(
          alignment: AlignmentDirectional.centerStart,
          minWidth: 0,
          maxWidth: double.infinity,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              line,
              SizedBox(width: widget.gap),
              line,
            ],
          ),
        );
        return Semantics(
          label: widget.text,
          excludeSemantics: true,
          child: SizedBox(
            width: box.maxWidth,
            height: height,
            // Its own layer: only the moving text repaints, not what is around it.
            child: RepaintBoundary(
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: _controller,
                  child: strip,
                  builder: (context, child) {
                    final dx = _offset(_controller.value, width);
                    return ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (rect) => _fadeShader(rect, dx > 0),
                      child: Transform.translate(offset: Offset(-dx, 0), child: child),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
