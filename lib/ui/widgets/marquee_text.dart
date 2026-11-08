import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/layout_prefs.dart';
import '../../services/ui_beat.dart';
import '../debug_switches.dart';
import 'playing_motion.dart' show PlayingMotion;

/// One line of text that slides sideways when it doesn't fit, so a long song
/// title can be read whole: it rests at the start for [pause], scrolls at
/// [speed] logical pixels a second until a second copy (after [gap]) takes its
/// place, and starts over. Text that fits stays still. With less motion
/// (Settings › Look & feel › Layout › Motion, or the system's setting) it is cut off with an
/// ellipsis instead.
///
/// It draws frames only while it moves: the rest at the start is a timer, so a screen of cards with long titles
/// isn't redrawn all the time. Still not for list rows, where dozens would scroll at once.
///
/// It scrolls [loops] times and then rests at the start until its text changes: a title that slid forever kept
/// the whole window redrawing at the display's rate while nothing else happened (a paused player, a Home page
/// left open), which on a laptop's integrated GPU is a busy CPU and GPU for nothing. [moving] off holds it still
/// with an ellipsis (a card that isn't hovered).
class MarqueeText extends StatefulWidget {
  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.speed = 35,
    this.pause = const Duration(seconds: 2),
    this.gap = 48,
    this.fade = 16,
    this.spans,
    this.moving = true,
    this.loops = 3,
    this.whilePaused = false,
  });

  final String text;

  /// The same [text] in pieces (links, say), drawn instead of the plain string. Measured as [text].
  final List<InlineSpan>? spans;
  final TextStyle? style;

  /// Logical pixels a second.
  final double speed;
  final Duration pause;

  /// Space between the end of the text and the copy that follows it.
  final double gap;

  /// Width of the faded edges while it scrolls.
  final double fade;

  /// False: cut off with an ellipsis and never scrolled, as if motion were off.
  final bool moving;

  /// How many times it scrolls before resting for good (until the text changes); null scrolls forever.
  final int? loops;

  /// Scrolls while [playing] is false too (a hovered card). Otherwise a pause takes it back to the start, where it
  /// rests until the song plays again: a song title sliding over a paused player kept the window drawing.
  final bool whilePaused;

  /// Whether a song plays with the window focused (set once by the app); null, as in tests, counts as playing.
  static ValueListenable<bool>? playing;

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

class _MarqueeTextState extends State<MarqueeText> {
  /// How far through one scroll it is, 0 to 1. Moved on the shared [UiBeat], not a ticker: a ticker drew at the
  /// display's rate (up to 240 times a second) for text moving 35 px a second, in frames of its own.
  final _progress = ValueNotifier<double>(0);
  UiBeatListener? _beat;
  Duration _scrollTime = Duration.zero;

  /// On a page that isn't shown ([TickerMode] off) the scroll holds where it is, and goes on when it is shown.
  bool _shown = true, _resume = false;

  /// 20 times a second in Balanced, on the beats the player's other motion uses; Heavy, 30 (its flower and wave's
  /// rate: every beat, 60, cost twice the frames for a title moving 35 px a second).
  static Duration get _every => DebugSwitches.endlessMarquee
      ? UiBeat.period
      : LayoutPrefs.heavy
      ? PlayingMotion.heavyEvery
      : const Duration(milliseconds: 50);

  /// Width of the text the controller is running for; null when still.
  double? _running;

  /// The rest at the start between two scrolls: a timer, no frames.
  Timer? _rest;

  /// Scrolls finished since it started; at [MarqueeText.loops] it stops.
  int _scrolled = 0;

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
        old.gap != widget.gap ||
        old.moving != widget.moving ||
        old.loops != widget.loops ||
        old.whilePaused != widget.whilePaused) {
      _stop();
    }
  }

  ValueListenable<bool>? _playing;

  bool get _paused => !widget.whilePaused && _playing?.value == false && !DebugSwitches.endlessMarquee;

  @override
  void initState() {
    super.initState();
    _playing = MarqueeText.playing?..addListener(_onPlaying);
  }

  /// Paused: back to the start and still. Playing again: rests, then scrolls on.
  void _onPlaying() {
    if (_running == null) return;
    if (_paused) {
      if (_beat == null && _rest == null && !_resume) return; // done with its loops already
      _rest?.cancel();
      _rest = null;
      _halt();
      _progress.value = 0;
      _resume = true;
    } else if (_resume && _shown) {
      _resume = false;
      _restThenScroll();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shown = TickerMode.valuesOf(context).enabled;
    if (!_shown && _beat != null) {
      _halt();
      _resume = true;
    } else if (_shown && _resume && !_paused) {
      _resume = false;
      if (_running != null) _scroll();
    }
  }

  @override
  void dispose() {
    _playing?.removeListener(_onPlaying);
    _rest?.cancel();
    _halt();
    _shader?.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _halt() {
    _beat?.cancel();
    _beat = null;
  }

  void _stop() {
    _rest?.cancel();
    _rest = null;
    _halt();
    _resume = false;
    _progress.value = 0;
    _running = null;
    _scrolled = 0;
  }

  void _start(double width) {
    if (_running == width) return;
    _stop();
    _running = width;
    _scrollTime = Duration(microseconds: ((width + widget.gap) / widget.speed * 1e6).round());
    _restThenScroll();
  }

  /// Rests at the start for [MarqueeText.pause], scrolls once, and again.
  void _restThenScroll() {
    _rest?.cancel();
    _rest = Timer(widget.pause, () {
      _rest = null;
      if (!mounted || _running == null) return;
      _progress.value = 0;
      if (_shown && !_paused) {
        _scroll();
      } else {
        _resume = true;
      }
    });
  }

  void _scroll() {
    _halt();
    _beat = UiBeat.listen(_every, (elapsed) {
      if (!mounted || _running == null) return _halt();
      final next = _progress.value + elapsed.inMicroseconds / _scrollTime.inMicroseconds;
      if (next < 1) {
        _progress.value = next;
        return;
      }
      _halt();
      _progress.value = 0;
      _scrolled++;
      final loops = widget.loops;
      // Done: it stays at the start, and [_running] keeps the next build from starting it again.
      if (loops != null && _scrolled >= loops && !DebugSwitches.endlessMarquee) return;
      _restThenScroll();
    });
  }

  /// How far the text has moved left at progress [t] (the scroll alone: the rest isn't animated).
  double _offset(double t, double width) => t * (width + widget.gap);

  Widget _line(TextStyle style, {bool ellipsis = false}) {
    final overflow = ellipsis ? TextOverflow.ellipsis : null;
    final spans = widget.spans;
    return spans == null
        ? Text(widget.text, maxLines: 1, softWrap: false, overflow: overflow, style: style)
        : Text.rich(
            TextSpan(children: spans),
            maxLines: 1,
            softWrap: false,
            overflow: overflow,
            style: style,
          );
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final still =
        !LayoutPrefs.moves ||
        MediaQuery.disableAnimationsOf(context) ||
        (!widget.moving && !DebugSwitches.endlessMarquee);
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
          return _line(style, ellipsis: true);
        }

        // Started after this frame: a ticker shouldn't start mid-build.
        if (_running != width) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _start(width);
          });
        }

        final line = _line(style);
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
                  animation: _progress,
                  child: strip,
                  builder: (context, child) {
                    final dx = _offset(_progress.value, width);
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
