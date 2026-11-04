import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/visualizer_levels.dart';
import '../../services/layout_prefs.dart';
import 'playing_motion.dart';

/// Shared resting geometry for player covers and their audio-driven borders.
abstract final class FlowerContour {
  /// With a [motion] clock the petals turn slowly and their depth ripples; at rest it is the plain flower.
  static double radius(double side, double phase, {MotionClock? motion}) {
    if (motion == null) return side * (0.35 + 0.018 * (1 + math.cos(phase * 24)) / 2);
    final spin = motion.time * 0.15;
    // The ripple fades with the clock, so a pause settles back to evenly deep petals.
    final ripple = 1 + 0.45 * motion.eased * math.sin(motion.time * 1.7 + phase * 3);
    return side * (0.35 + 0.018 * (1 + math.cos((phase - spin) * 24)) / 2 * ripple);
  }

  static double coverRadius(
    double side,
    double phase, {
    VisualizerLevels? levels,
    VisualizerCoverShape shape = VisualizerCoverShape.flower,
    bool fit = false,
    MotionClock? clock,
  }) {
    final energy = (levels?.backgroundEnergy ?? 0).clamp(0.0, 1.0);
    final beat = (levels?.beat ?? 0).clamp(0.0, 1.0);
    final motion = side * (energy * 0.005 + beat * 0.007);
    final r = shape == VisualizerCoverShape.flower
        ? radius(side, phase, motion: clock) + motion * (0.7 + 0.3 * math.cos(phase * 2))
        : squareRadius(side * 0.368 + motion, math.min(12, side * 0.03), phase);
    return r * (fit ? 0.5 / 0.368 : 1);
  }

  /// Distance along a ray to a rounded square, including its corner arcs.
  static double squareRadius(double half, double corner, double phase) {
    final x = math.sin(phase).abs(), y = math.cos(phase).abs();
    final straight = half / math.max(x, y);
    final inset = half - corner;
    if (math.min(x, y) * straight <= inset) return straight;
    final dot = inset * (x + y);
    return dot + math.sqrt(math.max(0, dot * dot - 2 * inset * inset + corner * corner));
  }

  /// Small audio-driven breathing keeps either artwork shape recognizable.
  static Path coverPath(
    Size size, {
    VisualizerLevels? levels,
    bool fit = false,
    VisualizerCoverShape shape = VisualizerCoverShape.flower,
    MotionClock? motion,
  }) => path(
    size,
    radiusAt: (phase) => coverRadius(size.shortestSide, phase, levels: levels, fit: fit, shape: shape, clock: motion),
  );

  static Path path(Size size, {double Function(double phase)? radiusAt}) {
    final center = (Offset.zero & size).center;
    const count = 192;
    // Packed coordinates avoid temporary Offset objects for each point and
    // each Bezier control point, while preserving the same contour.
    final points = Float64List(count * 2);
    for (var i = 0; i < count; i++) {
      final phase = i / count * math.pi * 2;
      final angle = phase - math.pi / 2;
      final r = radiusAt?.call(phase) ?? radius(size.shortestSide, phase);
      points[i * 2] = center.dx + math.cos(angle) * r;
      points[i * 2 + 1] = center.dy + math.sin(angle) * r;
    }
    final path = Path()..moveTo(points[0], points[1]);
    double x(int i) => points[(i % count) * 2];
    double y(int i) => points[(i % count) * 2 + 1];
    for (var i = 0; i < count; i++) {
      path.cubicTo(
        x(i) + (x(i + 1) - x(i - 1)) / 6,
        y(i) + (y(i + 1) - y(i - 1)) / 6,
        x(i + 1) - (x(i + 2) - x(i)) / 6,
        y(i + 1) - (y(i + 2) - y(i)) / 6,
        x(i + 1),
        y(i + 1),
      );
    }
    return path..close();
  }
}

/// The clip and halo use exactly the same native path. Only the latest path is
/// retained; animation frames never accumulate in a history or global cache.
class FlowerGeometry {
  FlowerGeometry({this.levels, this.fit = false, this.shape = VisualizerCoverShape.flower, this.motion});
  final VisualizerLevels? levels;
  final MotionClock? motion;
  final bool fit;
  final VisualizerCoverShape shape;
  Size? _size;
  double? _energy;
  double? _beat;
  double? _time;
  double? _eased;
  Path? _path;

  Path path(Size size) {
    final energy = levels?.backgroundEnergy ?? 0;
    final beat = levels?.beat ?? 0;
    final time = motion?.time, eased = motion?.eased;
    if (_size == size && _energy == energy && _beat == beat && _time == time && _eased == eased) return _path!;
    _size = size;
    _energy = energy;
    _beat = beat;
    _time = time;
    _eased = eased;
    return _path = FlowerContour.coverPath(size, levels: levels, fit: fit, shape: shape, motion: motion);
  }
}

/// A softly lit player cover. Shared levels animate it without rebuilding art.
class FlowerCover extends StatelessWidget {
  const FlowerCover({
    super.key,
    required this.child,
    this.levels,
    this.color,
    this.fit = false,
    this.shape = VisualizerCoverShape.flower,
    this.animate = false,
  });
  final Widget child;
  final VisualizerLevels? levels;
  final Color? color;
  final bool fit;
  final VisualizerCoverShape shape;

  /// Turns the petals and ripples their depth while a song plays (see [PlayingMotion] for when
  /// it holds still). Only for the big player covers: a list of small ones would each run a clock.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (!animate) return _flower(context, null);
    // Boundaries keep a beat to this cover: the art underneath stays a cached layer that is only
    // clipped again, instead of drawn again.
    return PlayingMotion(builder: (context, clock) => RepaintBoundary(child: _flower(context, clock, boundary: true)));
  }

  Widget _flower(BuildContext context, MotionClock? clock, {bool boundary = false}) {
    final geometry = FlowerGeometry(levels: levels, fit: fit, shape: shape, motion: clock);
    return CustomPaint(
      painter: _FlowerGlow(levels, color ?? Theme.of(context).colorScheme.primary, fit, shape, geometry, clock),
      child: ClipPath(
        clipper: FlowerClipper(fit: fit, levels: levels, shape: shape, geometry: geometry, motion: clock),
        child: boundary ? RepaintBoundary(child: child) : child,
      ),
    );
  }
}

class FlowerClipper extends CustomClipper<Path> {
  FlowerClipper({this.fit = false, this.levels, this.shape = VisualizerCoverShape.flower, this.geometry, this.motion})
    : super(reclip: _either(levels, motion));
  final MotionClock? motion;
  final bool fit;
  final VisualizerLevels? levels;
  final VisualizerCoverShape shape;
  final FlowerGeometry? geometry;
  @override
  Path getClip(Size size) =>
      geometry?.path(size) ?? FlowerContour.coverPath(size, fit: fit, levels: levels, shape: shape, motion: motion);
  @override
  bool shouldReclip(FlowerClipper oldClipper) =>
      oldClipper.fit != fit || oldClipper.levels != levels || oldClipper.shape != shape || oldClipper.motion != motion;
}

/// What to repaint on: the audio levels, the motion clock, both or neither.
Listenable? _either(Listenable? a, Listenable? b) => a == null ? b : (b == null ? a : Listenable.merge([a, b]));

class _FlowerGlow extends CustomPainter {
  _FlowerGlow(this.levels, this.color, this.fit, this.shape, this.geometry, this.motion)
    : super(repaint: _either(levels, motion));
  final MotionClock? motion;
  final FlowerGeometry geometry;
  final VisualizerLevels? levels;
  final Color color;
  final bool fit;
  final VisualizerCoverShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final energy = (levels?.backgroundEnergy ?? 0).clamp(0.0, 1.0);
    final beat = (levels?.beat ?? 0).clamp(0.0, 1.0);
    final blur = math.min(5.0, size.shortestSide * 0.012) * (1 + energy * 0.35);
    canvas.drawPath(
      geometry.path(size),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.min(3.0, size.shortestSide * 0.009)
        ..color = color.withValues(alpha: 0.2 + energy * 0.2 + beat * 0.15)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
  }

  @override
  bool shouldRepaint(_FlowerGlow oldDelegate) =>
      oldDelegate.levels != levels ||
      oldDelegate.motion != motion ||
      oldDelegate.color != color ||
      oldDelegate.fit != fit ||
      oldDelegate.shape != shape;
}

/// A solid flower silhouette for the optional play/pause button shape.
class FlowerBorder extends ShapeBorder {
  const FlowerBorder();
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;
  @override
  ShapeBorder scale(double t) => this;
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => FlowerContour.path(
    rect.size,
    radiusAt: (phase) => rect.shortestSide * (0.43 + 0.07 * (1 + math.cos(phase * 10)) / 2),
  ).shift(rect.topLeft);
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect, textDirection: textDirection);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
}
