import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/layout_prefs.dart';
import '../../services/visualizer_levels.dart';
import '../player_scope.dart';
import '../theme.dart';
import 'audio_reactive_view.dart';
import 'pulse_cover.dart';
import 'flower_cover.dart';

/// A flower cover at rest, with optional audio-driven decoration.
class AudioVisualizer extends StatelessWidget {
  const AudioVisualizer({
    super.key,
    this.child,
    this.radialOnly = false,
    this.linearOnly = false,
    this.height = 72,
    this.classicShape = false,
  });
  final Widget? child;
  final bool radialOnly;
  final bool linearOnly;
  final double height;

  /// Always the flower, whatever Cover says (the desktop's expanded player is always Classic).
  final bool classicShape;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LayoutPrefs.instance,
    builder: (context, _) {
      final prefs = LayoutPrefs.instance;
      final style = prefs.visualizerStyle;
      final shape = classicShape ? VisualizerCoverShape.flower : prefs.visualizerCoverShape;
      if (prefs.visualizerEnabled &&
          LayoutPrefs.moves &&
          !MediaQuery.disableAnimationsOf(context) &&
          child != null &&
          !style.radial &&
          context.getInheritedWidgetOfExactType<PlayerScope>() != null) {
        return AudioReactiveView(
          builder: (context, levels) => RepaintBoundary(
            child: FlowerCover(
              animate: true,
              levels: levels,
              // The rounded square fills its box; the flower keeps its petals' room.
              fit: shape == VisualizerCoverShape.square,
              shape: shape,
              color: AppColors.of(context).accent,
              child: child!,
            ),
          ),
        );
      }
      if (!prefs.visualizerEnabled ||
          !LayoutPrefs.moves ||
          MediaQuery.disableAnimationsOf(context) ||
          (child != null && !style.radial) ||
          (radialOnly && !style.radial) ||
          (linearOnly && style.radial)) {
        if (child == null) return const SizedBox.shrink();
        // Square is a plain rounded card: no glow, no motion. Those belong to the flower.
        if (shape == VisualizerCoverShape.square) {
          return ClipRRect(borderRadius: BorderRadius.circular(LayoutPrefs.radius(16)), child: child!);
        }
        return FlowerCover(animate: true, shape: shape, child: child!);
      }
      return AudioReactiveView(
        builder: (context, levels) {
          final canvas = VisualizerCanvas(
            levels: levels,
            color: AppColors.of(context).accent,
            style: style,
            coverShape: shape,
            radius: LayoutPrefs.radius(8),
            radialMotion: prefs.visualizerRadius,
            thickness: prefs.visualizerThickness,
            child: child,
          );
          return RepaintBoundary(
            child: child != null
                ? canvas
                : IgnorePointer(
                    child: Align(
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: SizedBox(height: height, width: double.infinity, child: canvas),
                      ),
                    ),
                  ),
          );
        },
      );
    },
  );
}

/// Paints only when measured audio changes; the cover does not rebuild per frame.
class VisualizerCanvas extends StatelessWidget {
  const VisualizerCanvas({
    super.key,
    required this.levels,
    required this.color,
    required this.style,
    this.radius = 8,
    this.coverShape = VisualizerCoverShape.flower,
    this.radialMotion = 1.6,
    this.thickness = 3,
    this.child,
  });
  final VisualizerLevels levels;
  final Color color;
  final VisualizerStyle style;
  final double radius;
  final VisualizerCoverShape coverShape;
  final double radialMotion;
  final double thickness;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (style.radial) {
      return PulseCover(
        levels: levels,
        color: color,
        movement: radialMotion,
        coverShape: coverShape,
        thickness: thickness,
        orbit: style != VisualizerStyle.pulse,
        petals: style == VisualizerStyle.petals,
        child: child,
      );
    }
    return CustomPaint(
      foregroundPainter: _VisualizerPainter(
        levels,
        color,
        style,
        child != null,
        radius,
        radialMotion,
        thickness,
        coverShape,
      ),
      child: child == null ? null : FlowerCover(levels: levels, shape: coverShape, color: color, child: child!),
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  _VisualizerPainter(
    this.levels,
    this.color,
    this.style,
    this.border,
    this.radius,
    this.radialMotion,
    this.thickness,
    this.coverShape,
  ) : super(repaint: levels);
  final VisualizerLevels levels;
  final Color color;
  final VisualizerStyle style;
  final bool border;
  final double radius;
  final double radialMotion;
  final double thickness;
  final VisualizerCoverShape coverShape;

  // One pen, restyled per stroke: every caller draws with it before asking for the next.
  final _pen = Paint();
  Paint pen(double opacity, {double width = 2, bool fill = false}) => _pen
    ..shader = null
    ..color = color.withValues(alpha: opacity)
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke;

  // Interpolate the current logarithmic frequency bands for curved styles.
  double sample(List<double> values, double t) {
    final index = t.clamp(0.0, 1.0) * (values.length - 1);
    final left = index.floor();
    final right = math.min(left + 1, values.length - 1);
    return values[left] + (values[right] - values[left]) * (index - left);
  }

  Path curve(List<Offset> points, {bool closed = false}) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    Offset point(int i) => closed ? points[i % points.length] : points[i.clamp(0, points.length - 1)];
    for (var i = 0; i < points.length - (closed ? 0 : 1); i++) {
      final p0 = point(i - 1), p1 = point(i), p2 = point(i + 1), p3 = point(i + 2);
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    if (closed) path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || levels.value.every((v) => v < 0.001)) return;
    // Frequency positions are fixed. Do not scroll history, subtract a moving
    // floor, or normalize every frame to a full-height plateau.
    final values = levels.value.map((v) => math.pow(v, 1.25).toDouble()).toList();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (border) {
      _border(canvas, size, values);
    } else {
      _linear(canvas, size, values);
    }
    canvas.restore();
  }

  void _border(Canvas canvas, Size size, List<double> values) {
    final contour = FlowerContour.coverPath(size, shape: coverShape, levels: levels);
    final metric = contour.computeMetrics().first;
    final count = (metric.length / 7).floor().clamp(32, 160);
    final outer = <Offset>[], inner = <Offset>[];
    for (var i = 0; i < count; i++) {
      final t = i / count;
      final tangent = metric.getTangentForOffset(metric.length * t)!;
      final normal = Offset(tangent.vector.dy, -tangent.vector.dx);
      final amplitude = sample(values, (1 - math.cos(t * math.pi * 2)) / 2);
      final length = amplitude * 10;
      final start = tangent.position + normal * 3;
      final end = tangent.position + normal * (4 + length);
      switch (style) {
        case VisualizerStyle.bars:
          canvas.drawLine(start, end, pen(0.75, width: 2.5));
        case VisualizerStyle.mirror:
          canvas.drawLine(
            tangent.position + normal * (8 - length * 0.45),
            tangent.position + normal * (8 + length * 0.45),
            pen(0.65, width: 2),
          );
        case VisualizerStyle.dots:
          canvas.drawCircle(end, 1.25, pen(0.45 + amplitude * 0.45, fill: true));
        default:
          outer.add(end);
          inner.add(tangent.position + normal * (3 + length * 0.35));
      }
    }
    if (outer.isEmpty) return;
    final outside = curve(outer, closed: true);
    if (style == VisualizerStyle.wave || style == VisualizerStyle.peaks) {
      final band = Path()
        ..fillType = PathFillType.evenOdd
        ..addPath(outside, Offset.zero)
        ..addPath(contour, Offset.zero);
      canvas.drawPath(band, pen(style == VisualizerStyle.wave ? 0.22 : 0.5, fill: true));
    }
    canvas.drawPath(outside, pen(0.8, width: style == VisualizerStyle.line ? 1.5 : 1.2));
    if (style == VisualizerStyle.twinWaves) {
      canvas.drawPath(curve(inner, closed: true), pen(0.35, width: 1));
    }
  }

  void _linear(Canvas canvas, Size size, List<double> spectrum) {
    // CAVA-style mirrored order: bass at both outer edges, treble in the
    // middle. Heights still come directly from the measured frequency bands.
    final values = [...spectrum, ...spectrum.reversed];
    final bounds = (Offset.zero & size).deflate(3);
    final center = bounds.center.dy;
    double envelope(double t) => sample(values, t);

    if (style == VisualizerStyle.bars || style == VisualizerStyle.dots || style == VisualizerStyle.mirror) {
      // Pair adjacent bands for a less crowded display. Keep their peak so
      // a narrow bass or treble hit remains visible after grouping.
      final grouped = List.generate(
        (spectrum.length + 1) ~/ 2,
        (i) => math.max(spectrum[i * 2], spectrum[math.min(i * 2 + 1, spectrum.length - 1)]),
      );
      final bars = [...grouped, ...grouped.reversed];
      final count = bars.length;
      final step = bounds.width / count;
      final width = (step * 0.72).clamp(2.0, 14.0);
      final barShader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [color.withValues(alpha: 0.5), color],
      ).createShader(bounds);
      final barPaint = Paint()..shader = barShader;
      for (var i = 0; i < count; i++) {
        final amplitude = bars[i];
        final height = amplitude * (bounds.height - 4);
        if (height < 0.5) continue;
        final x = bounds.left + (i + 0.5) * step;
        if (style == VisualizerStyle.dots) {
          for (var y = 0.0; y < height; y += 8) {
            canvas.drawCircle(Offset(x, bounds.bottom - y - 3), 2.3, pen(0.5 + amplitude * 0.4, fill: true));
          }
        } else {
          final baseline = style == VisualizerStyle.mirror ? center + height / 2 : bounds.bottom;
          final rect = Rect.fromLTWH(x - width / 2, baseline - height, width, height);
          canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(1.5)), barPaint);
        }
      }
      return;
    }

    if (style == VisualizerStyle.line || style == VisualizerStyle.peaks) {
      final points = List.generate(64, (i) {
        final t = i / 63;
        return Offset(bounds.left + bounds.width * t, bounds.bottom - envelope(t) * bounds.height * 0.85);
      });
      final path = curve(points);
      if (style == VisualizerStyle.peaks) {
        final fill = Path.from(path)
          ..lineTo(bounds.right, bounds.bottom)
          ..lineTo(bounds.left, bounds.bottom)
          ..close();
        canvas.drawPath(fill, pen(0.8, fill: true));
      }
      canvas.drawPath(path, pen(0.95, width: style == VisualizerStyle.line ? 3.5 : 2));
      return;
    }

    final top = <Offset>[], bottom = <Offset>[];
    final twin = style == VisualizerStyle.twinWaves;
    for (var i = 0; i < 64; i++) {
      final t = i / 63;
      final x = bounds.left + bounds.width * t;
      final amplitude = envelope(t) * bounds.height * 0.42;
      top.add(Offset(x, center - amplitude));
      bottom.add(Offset(x, center + (twin ? envelope(1 - t) * bounds.height * 0.3 : amplitude * 0.85)));
    }
    final upper = curve(top), lower = curve(bottom);
    if (!twin) {
      final ribbon = Path.from(upper)
        ..extendWithPath(curve(bottom.reversed.toList()), Offset.zero)
        ..close();
      canvas.drawPath(ribbon, pen(0.85, fill: true));
    }
    if (twin) {
      canvas.drawPath(upper, pen(0.95, width: 5));
      canvas.drawPath(lower, pen(0.5, width: 5));
    }
  }

  @override
  bool shouldRepaint(_VisualizerPainter old) =>
      old.levels != levels ||
      old.color != color ||
      old.border != border ||
      old.radius != radius ||
      old.style != style ||
      old.radialMotion != radialMotion ||
      old.thickness != thickness ||
      old.coverShape != coverShape;
}
