import 'dart:math' as math;
import 'dart:ui' show Tangent;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme.dart';
import 'app_logo.dart';

/// The shared launch intro: the mark's four pieces slam together, the mark punches and shakes with a ring, a glint
/// sweeps it and the wordmark settles in, then the whole thing zooms out of the way. About 1.8 s; a click or any key
/// skips to the end. If the library is still loading the mark breathes until it is ready.
///
/// [transparent]: drawn straight on a see-through window ([SplashWindow]); otherwise on the theme's background.
/// [beforeApp] runs once the intro is gone and before [child] is built (the window turns into the app's);
/// [afterApp] after [child]'s first frame.
class DesktopIntro extends StatefulWidget {
  /// How much larger it is drawn alone on the desktop ([transparent]) than over the app's own background.
  static const desktopScale = 1.5;

  const DesktopIntro({
    super.key,
    required this.ready,
    required this.child,
    this.transparent = false,
    this.onFirstFrame,
    this.beforeApp,
    this.afterApp,
  });

  final Future<void> ready;
  final Widget child;
  final bool transparent;
  final VoidCallback? onFirstFrame;
  final Future<void> Function()? beforeApp;
  final VoidCallback? afterApp;

  /// From the first frame to the app, when the library is already loaded.
  static const length = Duration(milliseconds: _end);

  @override
  State<DesktopIntro> createState() => _DesktopIntroState();
}

// The timeline, in milliseconds. Each piece's outline is drawn as if by a pen (one after another), then filled in
// (again one after another) as its outline fades; the last fill is the impact.
const _drawFor = 900.0, _drawEvery = 90.0; // a piece's outline, and how far behind the next one starts
const _fillFrom = 700.0, _fillFor = 340.0, _fillEvery = 90.0;
const _impact = _fillFrom + 3 * _fillEvery + _fillFor; // the last piece is filled in
const _hold = 1900; // fully formed; waits here for the library
const _end = 2250;
const _markSize = 150.0;

class _DesktopIntroState extends State<DesktopIntro> with TickerProviderStateMixin {
  late final _clock = AnimationController(vsync: this, duration: DesktopIntro.length);
  AnimationController? _breath;
  final _focus = FocusNode(debugLabel: 'intro');
  bool _loaded = false, _exiting = false, _done = false;

  static const _holdAt = _hold / _end;

  @override
  void initState() {
    super.initState();
    widget.ready.then((_) {
      _loaded = true;
      _maybeExit();
    }).ignore(); // The startup caller owns load errors.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onFirstFrame?.call();
      _clock.animateTo(_holdAt).whenCompleteOrCancel(_maybeExit);
    });
  }

  void _skip() {
    if (_exiting || _clock.value >= _holdAt) return;
    _clock.value = _holdAt; // cancels the run in progress, which calls [_maybeExit]
  }

  void _maybeExit() {
    if (!mounted || _exiting || _clock.value < _holdAt) return;
    if (!_loaded) {
      if (_breath != null) return;
      final breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
      setState(() => _breath = breath..repeat(reverse: true));
      return;
    }
    _breath?.stop();
    setState(() => _exiting = true);
    _clock.animateTo(1).whenCompleteOrCancel(_toApp);
  }

  Future<void> _toApp() async {
    if (!mounted || _done) return;
    await widget.beforeApp?.call();
    if (!mounted) return;
    setState(() => _done = true);
    if (widget.afterApp != null) WidgetsBinding.instance.addPostFrameCallback((_) => widget.afterApp!());
  }

  @override
  void dispose() {
    _clock.dispose();
    _breath?.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keyed so the app keeps its state when the intro on top of it goes.
    final app = KeyedSubtree(key: const ValueKey('app'), child: widget.child);
    if (_done) return Stack(fit: StackFit.expand, children: [app]);
    final colors = AppColors.of(context);
    final breath = _breath;
    final intro = Focus(
      key: const ValueKey('intro'),
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        _skip();
        return KeyEventResult.handled;
      },
      child: Semantics(
        label: 'Riflay',
        image: true,
        onTapHint: AppLocalizations.of(context).introSkip,
        onTap: _skip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _skip,
          child: AnimatedBuilder(
            animation: breath == null ? _clock : Listenable.merge([_clock, breath]),
            builder: (context, _) {
              final ms = _clock.value * _end;
              final exit = Curves.easeInCubic.transform(_seg(ms, _hold.toDouble(), _end.toDouble()));
              final body = Center(
                child: Transform.scale(
                  // Alone on the desktop it is drawn larger: the window around it is all there is to see.
                  scale: (widget.transparent ? DesktopIntro.desktopScale : 1) * (1 + 0.14 * exit),
                  child: SizedBox(
                    width: 360,
                    height: 360,
                    child: CustomPaint(
                      painter: _IntroPainter(
                        ms: ms,
                        breath: breath?.value ?? 0,
                        light: colors.textPrimary,
                        accent: colors.accent,
                        shadow: widget.transparent,
                      ),
                    ),
                  ),
                ),
              );
              return Opacity(
                opacity: 1 - exit,
                child: widget.transparent ? body : ColoredBox(color: colors.background, child: body),
              );
            },
          ),
        ),
      ),
    );
    return Stack(fit: StackFit.expand, children: [if (_exiting && !widget.transparent) app, intro]);
  }
}

/// 0 before [a], 1 after [b], linear between.
double _seg(double ms, double a, double b) => ((ms - a) / (b - a)).clamp(0.0, 1.0);

class _IntroPainter extends CustomPainter {
  _IntroPainter({
    required this.ms,
    required this.breath,
    required this.light,
    required this.accent,
    required this.shadow,
  });

  final double ms, breath;
  final Color light, accent;

  /// On a see-through window: a soft shadow keeps the mark readable on any wallpaper.
  final bool shadow;

  static final _pieces = [LogoMark.left, LogoMark.top, LogoMark.bottom, LogoMark.right];

  /// Each piece's outlines, measured once, to draw a stretch of them.
  static final _outlines = [for (final p in _pieces) p.computeMetrics().toList()];

  /// The pen's width, in the mark's design units (about 3 px on screen).
  static const _pen = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    _ring(canvas, center);

    // Punch: a damped spring kicked at the impact (overshoots, dips once, settles).
    final pt = _seg(ms, _impact, _impact + 380);
    final punch = pt > 0 ? 0.08 * math.exp(-5 * pt) * math.sin(3 * math.pi * pt) : 0.0;
    final scale = (1 + punch) * (1 + 0.025 * breath);

    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(scale)
      ..translate(-_markSize / 2, -_markSize / 2);
    canvas.save();
    LogoMark.fit(canvas, const Size.square(_markSize));

    if (shadow) {
      // Under the filled mark, once it is there: a shadow under a drawn outline would smear it.
      final s = _seg(ms, _impact - 120, _impact + 240);
      if (s > 0) {
        for (final piece in _pieces) {
          canvas.drawShadow(piece, Colors.black.withValues(alpha: s), 60, false); // design units: ~9 px
        }
      }
    }

    // The glint after it lights only the mark, so it goes into one layer.
    final glint = _seg(ms, _impact + 120, _impact + 560);
    final lit = glint > 0 && glint < 1;
    if (lit) canvas.saveLayer(LogoMark.bounds.inflate(40), Paint());
    for (var i = 0; i < _pieces.length; i++) {
      _drawPiece(canvas, i);
    }
    if (lit) {
      final b = LogoMark.bounds;
      final x = b.left - 360 + (b.width + 720) * Curves.easeInOutSine.transform(glint);
      final shine = Color.lerp(Colors.white, accent, 0.3)!;
      canvas
        ..drawRect(
          b.inflate(40),
          Paint()
            ..blendMode = BlendMode.srcATop
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [shine.withValues(alpha: 0), shine.withValues(alpha: 0.85), shine.withValues(alpha: 0)],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(Rect.fromCenter(center: Offset(x, b.center.dy), width: 520, height: 520)),
        )
        ..restore();
    }
    canvas
      ..restore()
      ..restore();
  }

  /// Piece [i]: its outline as far as the pen has drawn it, with a glowing tip, then its fill coming in as the
  /// outline fades.
  void _drawPiece(Canvas canvas, int i) {
    final piece = _pieces[i];
    final color = identical(piece, LogoMark.right) ? AppLogo.accent : light;
    final drawn = Curves.easeInOutCubic.transform(_seg(ms, i * _drawEvery, i * _drawEvery + _drawFor));
    final filled = Curves.easeOutCubic.transform(
      _seg(ms, _fillFrom + i * _fillEvery, _fillFrom + i * _fillEvery + _fillFor),
    );
    if (drawn <= 0) return;

    if (filled > 0) canvas.drawPath(piece, Paint()..color = color.withValues(alpha: color.a * filled));

    final outline = 1 - filled;
    if (outline <= 0) return;
    final metrics = _outlines[i];
    final total = metrics.fold<double>(0, (sum, m) => sum + m.length);
    var left = total * drawn;
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _pen
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: color.a * outline);
    Tangent? tip;
    for (final m in metrics) {
      if (left <= 0) break;
      final stretch = math.min(left, m.length);
      canvas.drawPath(m.extractPath(0, stretch), pen);
      tip = m.getTangentForOffset(stretch);
      left -= stretch;
    }
    // The pen's tip, glowing in the accent colour while it draws.
    if (tip != null && drawn < 1) {
      canvas
        ..drawCircle(
          tip.position,
          _pen * 2.4,
          Paint()
            ..color = accent.withValues(alpha: 0.55 * outline)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _pen * 1.6),
        )
        ..drawCircle(tip.position, _pen * 0.8, Paint()..color = Colors.white.withValues(alpha: outline));
    }
  }

  /// The shock ring the impact sends out, in the accent colour, and its faint echo. While waiting for the library a
  /// dim ring breathes with the mark instead.
  void _ring(Canvas canvas, Offset center) {
    for (final (delay, strength) in const [(0.0, 0.75), (90.0, 0.35)]) {
      final t = _seg(ms, _impact + delay, _impact + delay + 520);
      if (t <= 0 || t >= 1) continue;
      final e = Curves.easeOutCubic.transform(t);
      canvas.drawCircle(
        center,
        _markSize * (0.5 + 1.0 * e),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 * (1 - e) + 0.5
          ..color = accent.withValues(alpha: strength * (1 - t)),
      );
    }
    if (breath > 0) {
      canvas.drawCircle(
        center,
        _markSize * (0.78 + 0.06 * breath),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = accent.withValues(alpha: 0.12 + 0.18 * breath),
      );
    }
  }

  @override
  bool shouldRepaint(_IntroPainter old) =>
      old.ms != ms || old.breath != breath || old.light != light || old.accent != accent || old.shadow != shadow;
}
