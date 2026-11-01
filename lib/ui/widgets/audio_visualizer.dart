import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/layout_prefs.dart';
import '../../services/visualizer_levels.dart';
import '../theme.dart';
import 'audio_reactive_view.dart';

/// Optional player decoration. Disabled means the original child and layout.
class AudioVisualizer extends StatelessWidget {
  const AudioVisualizer({super.key, this.child, this.radialOnly = false, this.linearOnly = false, this.height = 72});
  final Widget? child;
  final bool radialOnly;
  final bool linearOnly;
  final double height;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LayoutPrefs.instance,
    builder: (context, _) {
      final prefs = LayoutPrefs.instance;
      final style = prefs.visualizerStyle;
      if (!prefs.visualizer ||
          !LayoutPrefs.moves ||
          MediaQuery.disableAnimationsOf(context) ||
          (child != null && !style.radial) ||
          (radialOnly && !style.radial) ||
          (linearOnly && style.radial)) {
        return child ?? const SizedBox.shrink();
      }
      return AudioReactiveView(
        builder: (context, levels) {
          final canvas = VisualizerCanvas(
            levels: levels,
            color: AppColors.of(context).accent,
            style: style,
            radius: LayoutPrefs.radius(8),
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
    this.child,
  });
  final VisualizerLevels levels;
  final Color color;
  final VisualizerStyle style;
  final double radius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    Widget? art = child;
    if (art != null && style.radial) {
      art = ClipOval(child: art);
    }
    return CustomPaint(
      foregroundPainter: _VisualizerPainter(levels, color, style, child != null, radius),
      child: child == null ? null : Padding(padding: EdgeInsets.all(style.radial ? 24 : 16), child: art),
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  _VisualizerPainter(this.levels, this.color, this.style, this.border, this.radius) : super(repaint: levels);
  final VisualizerLevels levels;
  final Color color;
  final VisualizerStyle style;
  final bool border;
  final double radius;

  Paint pen(double opacity, {double width = 2, bool fill = false}) => Paint()
    ..color = color.withValues(alpha: opacity)
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke;

  // Interpolating the envelope keeps narrow beats visible without drawing the
  // corners of the sample grid. These are RMS history samples, not FFT bins.
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
    // Remove part of the sustained level so small musical changes still read
    // as contours. Constant audio remains constant; silence stays empty.
    final floor = levels.value.reduce(math.min) * 0.95;
    final peak = levels.value.reduce(math.max);
    final values = levels.value.map((v) {
      final contrast = (v - floor) * peak / (peak - floor);
      // Give quiet passages enough visual weight in a compact player strip.
      return (math.pow(contrast, 0.6) * 1.4).clamp(0.0, 1.0).toDouble();
    }).toList();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (style.radial) {
      _radial(canvas, size, values);
    } else if (border) {
      _border(canvas, size, values);
    } else {
      _linear(canvas, size, values);
    }
    canvas.restore();
  }

  void _radial(Canvas canvas, Size size, List<double> values) {
    final center = (Offset.zero & size).center;
    final base = math.max(1.0, size.shortestSide / 2 - 24);
    // Mirror the same history around the artwork. Both ends of the contour
    // meet with zero slope, rather than jumping at the oldest/newest sample.
    double level(double t) => sample(values, (1 - math.cos(t * math.pi * 2)) / 2);
    if (style == VisualizerStyle.petals || style == VisualizerStyle.orbit) {
      final count = (base * 2 * math.pi / 10).floor().clamp(24, 80);
      for (var i = 0; i < count; i++) {
        final t = i / count;
        final angle = t * math.pi * 2 - math.pi / 2;
        final ray = Offset(math.cos(angle), math.sin(angle));
        final amplitude = level(t);
        if (style == VisualizerStyle.petals) {
          canvas.drawLine(
            center + ray * (base + 4),
            center + ray * (base + 7 + amplitude * 14),
            pen(0.55 + amplitude * 0.4, width: 4),
          );
        } else {
          canvas.drawCircle(
            center + ray * (base + 8 + amplitude * 10),
            2.2 + amplitude,
            pen(0.55 + amplitude * 0.4, fill: true),
          );
        }
      }
      return;
    }
    final points = List.generate(64, (i) {
      final t = i / 64;
      final angle = t * math.pi * 2 - math.pi / 2;
      return center + Offset(math.cos(angle), math.sin(angle)) * (base + 10 + level(t) * 12);
    });
    final band = Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(curve(points, closed: true), Offset.zero)
      ..addOval(Rect.fromCircle(center: center, radius: base + 4));
    canvas.drawPath(band, pen(0.8, fill: true));
  }

  void _border(Canvas canvas, Size size, List<double> values) {
    final rect = (Offset.zero & size).deflate(16);
    if (rect.isEmpty) return;
    final metric = (Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)))).computeMetrics().first;
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
        ..addRRect(RRect.fromRectAndRadius(rect.inflate(2), Radius.circular(radius + 2)));
      canvas.drawPath(band, pen(style == VisualizerStyle.wave ? 0.22 : 0.5, fill: true));
    }
    canvas.drawPath(outside, pen(0.8, width: style == VisualizerStyle.line ? 1.5 : 1.2));
    if (style == VisualizerStyle.twinWaves) {
      canvas.drawPath(curve(inner, closed: true), pen(0.35, width: 1));
    }
  }

  void _linear(Canvas canvas, Size size, List<double> values) {
    final bounds = (Offset.zero & size).deflate(3);
    final center = bounds.center.dy;
    // Only the ends fade out. A fixed sine arch would turn every song into
    // the same hill, concealing the dynamics in the measured history.
    double envelope(double t) {
      final edge = (math.min(t, 1 - t) / 0.09).clamp(0.0, 1.0);
      return sample(values, t) * edge * edge * (3 - 2 * edge);
    }

    if (style == VisualizerStyle.bars || style == VisualizerStyle.dots || style == VisualizerStyle.mirror) {
      final count = (bounds.width / 12).floor().clamp(16, 48);
      final step = bounds.width / count;
      final width = (step * 0.58).clamp(3.0, 7.0);
      for (var i = 0; i < count; i++) {
        final t = (i + 0.5) / count;
        final amplitude = envelope(t);
        final height = math.max(width, amplitude * bounds.height * 0.85);
        final x = bounds.left + (i + 0.5) * step;
        if (style == VisualizerStyle.dots) {
          for (var y = 0.0; y < height; y += 8) {
            canvas.drawCircle(Offset(x, bounds.bottom - y - 3), 2.3, pen(0.5 + amplitude * 0.4, fill: true));
          }
        } else {
          final baseline = style == VisualizerStyle.mirror ? center + height / 2 : bounds.bottom;
          canvas.drawLine(Offset(x, baseline), Offset(x, baseline - height), pen(0.9, width: width));
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
      old.levels != levels || old.color != color || old.border != border || old.radius != radius || old.style != style;
}
