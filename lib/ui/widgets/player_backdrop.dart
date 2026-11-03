import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/appearance.dart';
import '../../services/beta_features.dart';
import '../../services/layout_prefs.dart';
import '../../services/visualizer_levels.dart';
import '../theme.dart';
import 'audio_reactive_view.dart';

/// Decorative color fields, confined to the Now Playing canvas. Radial shaders
/// keep the softness of a blurred image without full-screen blur/saveLayer work.
class PlayerBackdrop extends StatelessWidget {
  const PlayerBackdrop({super.key, required this.coverColor});
  final Color coverColor;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([Appearance.instance, LayoutPrefs.instance, BetaFeatures.instance]),
    builder: (context, _) {
      final look = Appearance.instance;
      // Lightweight draws no backdrop at all, just the page's own background colour.
      if (!look.nowPlaying.isAbstract || LayoutPrefs.lightweight) return const SizedBox.shrink();
      Widget paint(VisualizerLevels? levels) => IgnorePointer(
        child: RepaintBoundary(
          child: _BackdropPaint(
            style: look.nowPlaying,
            cover: coverColor,
            accent: AppColors.accent,
            background: AppColors.solidBackground,
            light: AppColors.light,
            levels: levels,
          ),
        ),
      );
      if (!BetaFeatures.instance.isOn(BetaFeature.audioVisualizer) ||
          !look.reactiveBackground ||
          !LayoutPrefs.moves ||
          MediaQuery.disableAnimationsOf(context)) {
        return paint(null);
      }
      // The colour fields drift slowly: 30 updates a second look the same as 60 or 120.
      return AudioReactiveView(maxFps: LayoutPrefs.heavy ? null : 30, builder: (context, levels) => paint(levels));
    },
  );
}

/// Tests set this to render the CPU painter even where the shader would load.
@visibleForTesting
bool debugBackdropFallback = false;

/// The backdrop's fragment program (shaders/backdrop.frag), loaded once for the whole app. Until it is
/// ready, or if it can't load on this device, [_AbstractBackdrop] paints the same look on the CPU path.
class _BackdropPaint extends StatefulWidget {
  const _BackdropPaint({
    required this.style,
    required this.cover,
    required this.accent,
    required this.background,
    required this.light,
    this.levels,
  });
  final NowPlayingBackground style;
  final Color cover;
  final Color accent;
  final Color background;
  final bool light;
  final VisualizerLevels? levels;

  @override
  State<_BackdropPaint> createState() => _BackdropPaintState();
}

class _BackdropPaintState extends State<_BackdropPaint> {
  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram?>? _loading;
  ui.FragmentShader? _shader;

  static Future<ui.FragmentProgram?> _load() =>
      _loading ??= ui.FragmentProgram.fromAsset('shaders/backdrop.frag')
          .then<ui.FragmentProgram?>((program) => _program = program)
          .catchError((Object e) {
            debugPrint('Backdrop shader unavailable: $e');
            return null;
          });

  @override
  void initState() {
    super.initState();
    if (debugBackdropFallback) return;
    if (_program case final program?) {
      _shader = program.fragmentShader();
    } else {
      _load().then((program) {
        if (mounted && program != null) setState(() => _shader = program.fragmentShader());
      });
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final shader = _shader;
    return CustomPaint(
      painter: shader != null
          ? _ShaderBackdrop(
              shader: shader,
              style: w.style,
              cover: w.cover,
              accent: w.accent,
              background: w.background,
              light: w.light,
              levels: w.levels,
            )
          : _AbstractBackdrop(
              style: w.style,
              cover: w.cover,
              accent: w.accent,
              background: w.background,
              light: w.light,
              levels: w.levels,
            ),
      child: const SizedBox.expand(),
    );
  }
}

/// The four colour-field tints, from the cover colour and the accent.
List<Color> _backdropColors(Color cover, Color accent) {
  final hsl = HSLColor.fromColor(cover);
  return [
    cover,
    accent,
    hsl.withHue((hsl.hue + 42) % 360).withSaturation(hsl.saturation.clamp(0.25, 0.65)).toColor(),
    hsl.withHue((hsl.hue + 315) % 360).withSaturation(hsl.saturation.clamp(0.25, 0.65)).toColor(),
  ];
}

class _ShaderBackdrop extends CustomPainter {
  _ShaderBackdrop({
    required this.shader,
    required this.style,
    required this.cover,
    required this.accent,
    required this.background,
    required this.light,
    this.levels,
  }) : colors = _backdropColors(cover, accent),
       super(repaint: levels);
  final ui.FragmentShader shader;
  final NowPlayingBackground style;
  final Color cover;
  final Color accent;
  final Color background;
  final bool light;
  final VisualizerLevels? levels;
  final List<Color> colors;
  final _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // The motion repeats every 100 pi, so wrapping keeps float precision after hours of playback.
    final phase = ((levels?.frame ?? 0) * 0.006) % (100 * math.pi);
    final base = Color.lerp(background, cover, light ? 0.035 : 0.08)!;
    var i = 0;
    void set(double v) => shader.setFloat(i++, v);
    void setColor(Color c) {
      set(c.r);
      set(c.g);
      set(c.b);
    }

    set(size.width);
    set(size.height);
    set(switch (style) {
      NowPlayingBackground.aurora => 0,
      NowPlayingBackground.silk => 1,
      NowPlayingBackground.orbits => 2,
      _ => 3,
    });
    set(phase);
    set(levels?.backgroundEnergy ?? 0.35);
    set(light ? 1 : 0);
    colors.forEach(setColor);
    setColor(background);
    setColor(base);
    canvas.drawRect(Offset.zero & size, _paint..shader = shader);
  }

  @override
  bool shouldRepaint(_ShaderBackdrop old) =>
      old.style != style ||
      old.cover != cover ||
      old.accent != accent ||
      old.background != background ||
      old.light != light ||
      old.levels != levels ||
      old.shader != shader;
}

class _AbstractBackdrop extends CustomPainter {
  _AbstractBackdrop({
    required this.style,
    required this.cover,
    required this.accent,
    required this.background,
    required this.light,
    this.levels,
  }) : super(repaint: levels);
  final NowPlayingBackground style;
  final Color cover;
  final Color accent;
  final Color background;
  final bool light;
  final VisualizerLevels? levels;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.clipRect(rect);
    final phase = (levels?.frame ?? 0) * 0.006;
    final energy = levels?.backgroundEnergy ?? 0.35;
    final colors = _backdropColors(cover, accent);
    canvas.drawColor(Color.lerp(background, cover, light ? 0.035 : 0.08)!, BlendMode.srcOver);
    void glow(Offset center, double radius, Color color, double opacity, {double stretch = 1}) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(stretch, 1);
      final bounds = Rect.fromCircle(center: Offset.zero, radius: radius);
      canvas.drawOval(
        bounds,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: opacity * 0.45),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.48, 1],
          ).createShader(bounds),
      );
      canvas.restore();
    }

    final longest = math.max(size.width, size.height);
    switch (style) {
      case NowPlayingBackground.aurora:
        for (var i = 0; i < 5; i++) {
          final x = size.width * (0.15 + i * 0.19 + 0.12 * math.sin(phase + i * 1.7));
          final y = size.height * (0.25 + 0.24 * math.cos(phase * 0.7 + i * 1.3));
          glow(Offset(x, y), longest * (0.36 + energy * 0.09), colors[i % 4], light ? 0.16 : 0.3, stretch: 1.3);
        }
      case NowPlayingBackground.silk:
        for (var i = 0; i < 5; i++) {
          final y = size.height * (0.15 + i * 0.15);
          final drift = math.sin(phase + i * 0.9) * size.height * (0.08 + 0.04 * energy);
          final path = Path()
            ..moveTo(-40, y + drift)
            ..cubicTo(
              size.width * 0.25,
              y - size.height * 0.28,
              size.width * 0.65,
              y + size.height * 0.35,
              size.width + 40,
              y - drift,
            )
            ..lineTo(size.width + 40, y + size.height * 0.22 - drift)
            ..cubicTo(
              size.width * 0.65,
              y + size.height * 0.45,
              size.width * 0.25,
              y - size.height * 0.15,
              -40,
              y + size.height * 0.15 + drift,
            )
            ..close();
          canvas.drawPath(
            path,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors[i % 4].withValues(alpha: 0),
                  colors[(i + 1) % 4].withValues(alpha: light ? 0.11 : 0.22),
                  colors[i % 4].withValues(alpha: 0.04),
                ],
              ).createShader(rect),
          );
        }
      case NowPlayingBackground.orbits:
        // Opposing pools of light follow a slow orbit. Soft edges keep the
        // artwork and lyrics in front, without drawing shapes across them.
        for (var i = 0; i < 2; i++) {
          final angle = phase * 0.18 + i * math.pi;
          final center = Offset(
            size.width * (0.5 + 0.28 * math.cos(angle)),
            size.height * (0.48 + 0.16 * math.sin(angle)),
          );
          glow(
            center,
            longest * (0.34 + energy * 0.035),
            i == 0 ? cover : Color.lerp(cover, accent, 0.3)!,
            light ? 0.14 : 0.28,
            stretch: 1.25,
          );
        }
      case NowPlayingBackground.prism:
        final center = Offset(
          size.width * (0.48 + 0.04 * math.sin(phase)),
          size.height * (0.45 + 0.04 * math.cos(phase)),
        );
        for (var i = 0; i < 7; i++) {
          final angle = i * 2 * math.pi / 7 + math.sin(phase * 0.6) * 0.14;
          final radius = longest * 1.6;
          final path = Path()
            ..moveTo(center.dx, center.dy)
            ..lineTo(center.dx + math.cos(angle) * radius, center.dy + math.sin(angle) * radius)
            ..lineTo(center.dx + math.cos(angle + 0.9) * radius, center.dy + math.sin(angle + 0.9) * radius)
            ..close();
          canvas.drawPath(
            path,
            Paint()
              ..shader = RadialGradient(
                center: Alignment(center.dx / size.width * 2 - 1, center.dy / size.height * 2 - 1),
                radius: 1.2,
                colors: [
                  colors[i % 4].withValues(alpha: 0.04 + energy * 0.06),
                  colors[(i + 1) % 4].withValues(alpha: light ? 0.06 : 0.17),
                ],
              ).createShader(rect),
          );
        }
      default:
        break;
    }
    // Quiet contrast veil underneath text; never blooms or flashes on a beat.
    canvas.drawRect(rect, Paint()..color = background.withValues(alpha: light ? 0.15 : 0.25));
  }

  @override
  bool shouldRepaint(_AbstractBackdrop old) =>
      old.style != style ||
      old.cover != cover ||
      old.accent != accent ||
      old.background != background ||
      old.light != light ||
      old.levels != levels;
}
