import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme.dart';
import 'app_logo.dart';

/// The desktop launch's intro: the mark's four pieces slam together, the mark punches and shakes with a ring, a glint
/// sweeps it and the wordmark settles in, then the whole thing zooms out of the way. About 1.8 s; a click or any key
/// skips to the end. If the library is still loading the mark breathes until it is ready.
///
/// [transparent]: drawn straight on a see-through window ([SplashWindow]); otherwise on the theme's background.
/// [beforeApp] runs once the intro is gone and before [child] is built (the window turns into the app's);
/// [afterApp] after [child]'s first frame.
class DesktopIntro extends StatefulWidget {
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

// The timeline, in milliseconds.
const _impact = 700.0; // the last piece locks in
const _hold = 1450; // fully formed; waits here for the library
const _end = 1800;
const _markSize = 112.0;

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
                  scale: 1 + 0.14 * exit,
                  child: SizedBox(
                    width: 360,
                    height: 360,
                    child: Stack(
                      children: [
                        Positioned.fill(
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
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 252,
                          child: _Wordmark(ms: ms, colors: colors, shadow: widget.transparent),
                        ),
                      ],
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

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.ms, required this.colors, required this.shadow});

  final double ms;
  final AppColorsView colors;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final t = Curves.easeOutCubic.transform(_seg(ms, 950, 1400));
    final line = Curves.easeOutQuart.transform(_seg(ms, 1080, 1420));
    final style = Theme.of(context).textTheme.titleLarge ?? const TextStyle();
    return ExcludeSemantics(
      child: Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - t)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'RIFLAY',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                // The spacing closes in as it fades up, like a title card.
                style: style.copyWith(
                  color: colors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 22 - 13 * t,
                  height: 1,
                  decoration: TextDecoration.none,
                  shadows: shadow ? const [Shadow(color: Color(0x99000000), blurRadius: 10)] : null,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: 64 * line,
                height: 2,
                decoration: BoxDecoration(color: colors.accent, borderRadius: BorderRadius.circular(1)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the mark's pieces flying in: from [from] (design units, off its place), turned by [turn] and enlarged, as if
/// thrown at the screen, over [start]…[end] ms.
class _Piece {
  const _Piece(this.path, this.start, this.end, this.from, this.turn);

  final Path path;
  final double start, end;
  final Offset from;
  final double turn;
}

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

  // Quick out, long soft lock: the pieces arrive fast and settle without a bounce (the punch is the bounce).
  static const _fly = Cubic(0.55, 0, 0.1, 1);

  static final _pieces = [
    _Piece(LogoMark.left, 0, 520, const Offset(-420, 0), -0.35),
    _Piece(LogoMark.top, 60, 580, const Offset(0, -380), 0.6),
    _Piece(LogoMark.bottom, 120, 640, const Offset(0, 380), -0.6),
    _Piece(LogoMark.right, 180, _impact, const Offset(460, 0), 0.35),
  ];

  static final _centers = [for (final p in _pieces) p.path.getBounds().center];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, 150);
    _ring(canvas, center);

    // Shake: a few quick, decaying jolts right after the impact.
    final st = _seg(ms, _impact, _impact + 260);
    final decay = (1 - st) * (1 - st);
    final shake = st > 0 && st < 1
        ? Offset(math.sin(st * math.pi * 9) * 4 * decay, math.cos(st * math.pi * 7) * 2 * decay)
        : Offset.zero;
    // Punch: a damped spring kicked at the impact (overshoots, dips once, settles).
    final pt = _seg(ms, _impact, _impact + 380);
    final punch = pt > 0 ? 0.12 * math.exp(-5 * pt) * math.sin(3 * math.pi * pt) : 0.0;
    // The pieces close in from a little further away while they fly.
    final approach = 0.9 + 0.1 * Curves.easeOutCubic.transform(_seg(ms, 0, _impact));
    final scale = approach * (1 + punch) * (1 + 0.025 * breath);

    canvas
      ..save()
      ..translate(center.dx + shake.dx, center.dy + shake.dy)
      ..scale(scale)
      ..translate(-_markSize / 2, -_markSize / 2);
    final box = Offset.zero & const Size.square(_markSize);
    canvas.save();
    LogoMark.fit(canvas, box.size);

    // The flash at the impact and the glint after it light only the pieces, so they go into one layer.
    final flash = 1 - _seg(ms, _impact, _impact + 180);
    final glint = _seg(ms, 880, 1280);
    final lit = (flash > 0 && flash < 1) || (glint > 0 && glint < 1);
    if (shadow) _drawPieces(canvas, shadowOnly: true);
    if (lit) canvas.saveLayer(LogoMark.bounds.inflate(40), Paint());
    _drawPieces(canvas);
    if (lit) {
      if (flash > 0 && flash < 1) {
        canvas.drawRect(
          LogoMark.bounds.inflate(40),
          Paint()
            ..blendMode = BlendMode.srcATop
            ..color = Color.lerp(Colors.white, accent, 0.2)!.withValues(alpha: 0.6 * flash),
        );
      }
      if (glint > 0 && glint < 1) {
        final b = LogoMark.bounds;
        final x = b.left - 360 + (b.width + 720) * Curves.easeInOutSine.transform(glint);
        final shine = Color.lerp(Colors.white, accent, 0.3)!;
        canvas.drawRect(
          b.inflate(40),
          Paint()
            ..blendMode = BlendMode.srcATop
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [shine.withValues(alpha: 0), shine.withValues(alpha: 0.85), shine.withValues(alpha: 0)],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(Rect.fromCenter(center: Offset(x, b.center.dy), width: 520, height: 520)),
        );
      }
      canvas.restore();
    }
    canvas
      ..restore()
      ..restore();
  }

  void _drawPieces(Canvas canvas, {bool shadowOnly = false}) {
    for (var i = 0; i < _pieces.length; i++) {
      final piece = _pieces[i];
      final color = identical(piece.path, LogoMark.right) ? AppLogo.orange : light;
      final p = _seg(ms, piece.start, piece.end);
      if (p <= 0) continue;
      if (shadowOnly) {
        // Fades in once the mark has locked: a moving shadow would smear.
        final s = _seg(ms, _impact, _impact + 240);
        if (s > 0) canvas.drawShadow(piece.path, Colors.black.withValues(alpha: s), 60, false); // design units: ~9 px
        continue;
      }
      // Two fading copies trail a piece in flight (a cheap motion blur).
      if (p < 1) {
        for (var k = 2; k >= 1; k--) {
          final pk = _seg(ms - k * 26, piece.start, piece.end);
          if (pk > 0) _drawPiece(canvas, i, _fly.transform(pk), color.withValues(alpha: color.a * 0.16 * (3 - k) * pk));
        }
      }
      final opacity = (p / 0.3).clamp(0.0, 1.0);
      _drawPiece(canvas, i, _fly.transform(p), color.withValues(alpha: color.a * opacity));
    }
  }

  void _drawPiece(Canvas canvas, int i, double p, Color color) {
    final piece = _pieces[i], pivot = _centers[i];
    final q = 1 - p;
    canvas
      ..save()
      ..translate(piece.from.dx * q + pivot.dx, piece.from.dy * q + pivot.dy)
      ..rotate(piece.turn * q)
      ..scale(1 + 0.7 * q)
      ..translate(-pivot.dx, -pivot.dy)
      ..drawPath(piece.path, Paint()..color = color)
      ..restore();
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
