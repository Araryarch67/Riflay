import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/visualizer_levels.dart';
import '../../services/layout_prefs.dart';
import 'flower_cover.dart';

/// Pulse fills a continuous audio-driven wave around the selected cover shape.
/// Orbit adds spectrum bars that start immediately outside the same contour.
class PulseCover extends StatelessWidget {
  const PulseCover({
    super.key,
    required this.levels,
    required this.color,
    required this.movement,
    required this.thickness,
    this.child,
    this.orbit = false,
    this.petals = false,
    this.coverShape = VisualizerCoverShape.flower,
  });

  final VisualizerLevels levels;
  final Color color;
  final double movement;
  final double thickness;
  final Widget? child;
  final bool orbit;
  final bool petals;
  final VisualizerCoverShape coverShape;

  @override
  Widget build(BuildContext context) {
    final contour = _PulseContour(levels, movement, thickness, orbit, petals, coverShape);
    return CustomPaint(
      painter: _PulsePainter(contour, color, glow: true),
      foregroundPainter: _PulsePainter(contour, color, glow: false),
      child: child == null
          ? null
          : ClipPath(
              clipper: orbit
                  ? _PulseClipper(contour)
                  : FlowerClipper(levels: levels, shape: coverShape, geometry: contour.coverGeometry),
              child: child,
            ),
    );
  }
}

class _PulseContour {
  _PulseContour(this.levels, this.movement, this.thickness, this.orbit, this.petals, this.coverShape);

  final VisualizerLevels levels;
  final double movement;
  final double thickness;
  final bool orbit;
  final bool petals;
  final VisualizerCoverShape coverShape;
  late final coverGeometry = FlowerGeometry(levels: levels, shape: coverShape);
  Size? _size;
  List<double>? _values;
  double? _beat;
  Path? _path;

  Path path(Size size) {
    if (_size == size && identical(_values, levels.value) && _beat == levels.beat) return _path!;
    _size = size;
    _values = levels.value;
    _beat = levels.beat;
    return _path = FlowerContour.path(size, radiusAt: (phase) => radius(size.shortestSide, phase));
  }

  double level(double phase) {
    final band = (1 - math.cos(phase)) * 0.5 * (levels.value.length - 1);
    final left = band.floor();
    final right = math.min(left + 1, levels.value.length - 1);
    return levels.value[left] + (levels.value[right] - levels.value[left]) * (band - left);
  }

  double radius(double side, double phase) {
    final beat = levels.beat.clamp(0.0, 1.0);
    final energy = levels.backgroundEnergy.clamp(0.0, 1.0);
    final drive = (energy * 0.2 + math.pow(level(phase).clamp(0.0, 1.0), 0.7) * 0.8 + beat * 0.3).clamp(0.0, 1.0);
    final motion = (movement / 2.5).clamp(0.0, 1.0);
    final scallop = (1 + math.cos(phase * 24)) * 0.5;
    if (orbit) {
      if (coverShape == VisualizerCoverShape.square) {
        return FlowerContour.coverRadius(side, phase, shape: coverShape, levels: levels);
      }
      // A flower-shaped base stays visible even between beats. Leave room
      // outside it for the radial spectrum rather than shrinking on slider changes.
      return FlowerContour.radius(side, phase) + side * motion * (beat * 0.014 + drive * scallop * 0.025);
    }
    // The cover breathes gently inside a separate, crisp waveform. Peaks and
    // troughs follow each audio band instead of just brightening its edge.
    final gap = side * 0.012 + thickness;
    final base = coverShape == VisualizerCoverShape.flower
        ? side * 0.368
        : FlowerContour.coverRadius(side, phase, shape: coverShape);
    final available = math.max(0.0, outerRadius(side, phase, 0.48) - thickness - base - gap);
    // Uneven, overlapping lobes avoid the uniformly spaced flower/sine look.
    // Cosine harmonics keep the two sides mirrored; audio bands reshape them.
    final warp = levels.value[3] * 2.1 + levels.value[11] * 1.3 + levels.value[19] * 0.8;
    final texture =
        0.5 +
        0.5 *
            math.sin(
              1.7 * math.cos(phase * 7) +
                  1.1 * math.cos(phase * 13) +
                  0.7 * math.cos(phase * 19) +
                  0.4 * math.cos(phase * 31) +
                  warp,
            );
    final wave = 0.08 + texture * 0.92;
    final sides = 0.18 + 0.82 * math.pow(math.sin(phase), 2);
    return base + gap + available * math.sqrt(motion) * drive * wave * sides;
  }

  double outerRadius(double side, double phase, double fraction) => coverShape == VisualizerCoverShape.square
      ? side * fraction / math.max(math.sin(phase).abs(), math.cos(phase).abs())
      : side * fraction;
}

class _PulseClipper extends CustomClipper<Path> {
  _PulseClipper(this.contour) : super(reclip: contour.levels);
  final _PulseContour contour;

  @override
  Path getClip(Size size) => contour.path(size);

  @override
  bool shouldReclip(_PulseClipper oldClipper) => oldClipper.contour != contour;
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.contour, this.color, {required this.glow}) : super(repaint: contour.levels);
  final _PulseContour contour;
  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || contour.levels.value.every((v) => v < 0.001)) return;
    final path = contour.path(size);
    final width = contour.thickness;
    final pen = Paint()..style = PaintingStyle.stroke;
    if (!contour.orbit) {
      if (glow) {
        final energy = contour.levels.backgroundEnergy.clamp(0.0, 1.0);
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..color = color.withValues(alpha: 0.12 + energy * 0.1)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.min(3.0, size.shortestSide * 0.01)),
        );
        // Fill up to the artwork's flower edge without tinting the cover,
        // including artwork with transparent pixels.
        final band = Path()
          ..fillType = PathFillType.evenOdd
          ..addPath(path, Offset.zero)
          ..addPath(contour.coverGeometry.path(size), Offset.zero);
        canvas.drawPath(band, Paint()..color = color);
        return;
      }
      canvas.drawPath(
        path,
        pen
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = width
          ..color = color,
      );
      return;
    }
    if (glow) {
      final blur = math.min(3.0, size.shortestSide * 0.008);
      canvas.drawPath(
        path,
        pen
          ..color = color.withValues(alpha: 0.14)
          ..strokeWidth = width + blur * 2
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
      );
      canvas.drawPath(
        path,
        pen
          ..color = color.withValues(alpha: 0.3)
          ..strokeWidth = width + blur * 0.5
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur * 0.4),
      );
      if (contour.orbit) {
        final side = size.shortestSide;
        final center = (Offset.zero & size).center;
        final count = contour.petals ? 48 : 96;
        final rayWidth = contour.petals ? width * 1.6 : width;
        final gap = rayWidth * 0.5 + 2;
        for (var i = 0; i < count; i++) {
          final phase = i / count * math.pi * 2;
          final angle = phase - math.pi / 2;
          final ray = Offset(math.cos(angle), math.sin(angle));
          final amplitude = math.pow(contour.level(phase).clamp(0.0, 1.0), 0.8).toDouble();
          final base = contour.radius(side, phase) + gap;
          final room = math.max(0.0, contour.outerRadius(side, phase, 0.49) - rayWidth / 2 - base);
          final length = math.min(room, side * 0.025 + amplitude * side * 0.15 * (contour.movement / 2.5));
          canvas.drawLine(
            center + ray * base,
            center + ray * (base + length),
            pen
              ..maskFilter = null
              ..strokeCap = StrokeCap.round
              ..strokeWidth = rayWidth
              ..color = color.withValues(alpha: 0.6 + amplitude * 0.4),
          );
        }
      }
    } else {
      canvas.drawPath(
        path,
        pen
          ..color = Colors.black.withValues(alpha: 0.65)
          ..strokeWidth = width + 2,
      );
      canvas.drawPath(
        path,
        pen
          ..color = color.withValues(alpha: 0.9)
          ..strokeWidth = width,
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) =>
      oldDelegate.contour != contour || oldDelegate.color != color || oldDelegate.glow != glow;
}
