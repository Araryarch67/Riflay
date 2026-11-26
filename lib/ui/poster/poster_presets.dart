import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/language.dart';
import 'poster_card.dart';

/// Where a card sits and how it is turned: its centre (0–1 of the poster), size, and turns in radians (in the
/// poster's plane, about the across axis, about the up axis).
typedef PosterPose = ({Offset at, double scale, double tilt, double pitch, double yaw});

/// Ready-made layouts: every card placed and turned in one tap, the editing left for the details. Poses are listed
/// bottom layer first, so the card that leads a layout (the middle one, the big one) is drawn over the others.
enum PosterPreset {
  scatter,
  stack,
  grid,
  fan,
  spotlight,
  cascade,
  float3d;

  String get label => switch (this) {
    scatter => tr.posterPresetScatter,
    stack => tr.posterPresetStack,
    grid => tr.posterPresetGrid,
    fan => tr.posterPresetFan,
    spotlight => tr.posterPresetSpotlight,
    cascade => tr.posterPresetCascade,
    float3d => tr.posterPresetFloat,
  };

  /// The look it suggests for the cards; null keeps theirs.
  PosterCardStyle? get style => switch (this) {
    float3d => PosterCardStyle.glass,
    _ => null,
  };

  /// A card at scale 1 on a 390 × 693 poster: its half-size, as parts of the poster, so a pose keeps it inside.
  static const _halfWide = 130 / 390, _halfTall = 230 / 693;

  static double _deg(double d) => d * math.pi / 180;

  static PosterPose _pose(double x, double y, double scale, {double tilt = 0, double pitch = 0, double yaw = 0}) => (
    // Kept in: a card's middle no nearer the edge than half of it.
    at: Offset(
      x.clamp(_halfWide * scale * 0.85, 1 - _halfWide * scale * 0.85),
      y.clamp(_halfTall * scale * 0.9, 1 - _halfTall * scale * 0.9),
    ),
    scale: scale,
    tilt: _deg(tilt),
    pitch: _deg(pitch),
    yaw: _deg(yaw),
  );

  /// [count] cards laid out, bottom layer first.
  List<PosterPose> layout(int count) {
    if (count <= 0) return const [];
    final n = math.min(count, 8);
    final poses = switch (this) {
      scatter => _scatter(n),
      stack => _stack(n),
      grid => _grid(n),
      fan => _fan(n),
      spotlight => _spotlight(n),
      cascade => _cascade(n),
      float3d => _float(n),
    };
    // More than eight: the rest over the layout's own places again.
    return [for (var i = 0; i < count; i++) poses[i % poses.length]];
  }

  /// Loose, as if dropped on a table: around the poster, the last (in the middle) on top.
  static List<PosterPose> _scatter(int n) {
    const spots = {
      1: [(0.5, 0.5, -3.0)],
      2: [(0.34, 0.37, -7.0), (0.66, 0.63, 6.0)],
      3: [(0.28, 0.3, -8.0), (0.72, 0.31, 8.0), (0.5, 0.68, -2.0)],
      4: [(0.28, 0.29, -7.0), (0.73, 0.27, 6.0), (0.27, 0.72, 5.0), (0.73, 0.71, -6.0)],
      5: [(0.27, 0.24, -8.0), (0.74, 0.22, 7.0), (0.26, 0.78, 6.0), (0.75, 0.77, -7.0), (0.5, 0.5, -2.0)],
      6: [
        (0.26, 0.22, -8.0),
        (0.75, 0.21, 7.0),
        (0.24, 0.53, 5.0),
        (0.77, 0.53, -6.0),
        (0.3, 0.8, -4.0),
        (0.7, 0.79, 6.0),
      ],
      7: [
        (0.26, 0.21, -8.0),
        (0.75, 0.2, 7.0),
        (0.2, 0.52, 6.0),
        (0.8, 0.52, -6.0),
        (0.28, 0.81, -5.0),
        (0.72, 0.8, 5.0),
        (0.5, 0.5, -2.0),
      ],
      8: [
        (0.25, 0.19, -8.0),
        (0.75, 0.19, 7.0),
        (0.2, 0.44, 6.0),
        (0.8, 0.45, -6.0),
        (0.22, 0.73, -5.0),
        (0.78, 0.74, 5.0),
        (0.5, 0.86, 3.0),
        (0.5, 0.48, -2.0),
      ],
    };
    final scale = switch (n) {
      1 => 1.0,
      2 => 0.66,
      3 => 0.58,
      4 => 0.54,
      5 => 0.5,
      6 => 0.46,
      _ => 0.42,
    };
    return [
      for (final (x, y, t) in spots[n]!) _pose(x, y, n >= 5 && (x - 0.5).abs() < 0.01 ? scale * 1.18 : scale, tilt: t),
    ];
  }

  /// A pile in the middle: each card under the top one a little more turned and off, the top one straight.
  static List<PosterPose> _stack(int n) {
    final scale = n <= 2 ? 0.92 : 0.84;
    return [
      for (var i = 0; i < n; i++)
        () {
          final depth = n - 1 - i; // 0 for the top card
          final side = depth.isEven ? 1.0 : -1.0;
          return _pose(0.5 + side * 0.035 * depth, 0.5 + 0.012 * depth, scale, tilt: side * 5.5 * depth);
        }(),
    ];
  }

  /// Neat rows, each card as big as its cell lets it be.
  static List<PosterPose> _grid(int n) {
    final columns = n <= 1 ? 1 : (n <= 4 || n == 6 ? 2 : (n <= 6 ? 2 : 3));
    final rows = (n / columns).ceil();
    // A cell's room, against a card's own size, with a gutter.
    final scale = math.min((1 / columns) / (2 * _halfWide) * 0.88, (1 / rows) / (2 * _halfTall) * 0.9);
    return [
      for (var i = 0; i < n; i++)
        () {
          final row = i ~/ columns;
          // A last row that isn't full is centred.
          final inRow = row == rows - 1 ? n - row * columns : columns;
          final col = i % columns;
          return _pose((col + 0.5 + (columns - inRow) / 2) / columns, (row + 0.5) / rows, scale);
        }(),
    ];
  }

  /// Held like cards in a hand: on an arc, opening upwards, the middle one on top.
  static List<PosterPose> _fan(int n) {
    final scale = n <= 3 ? 0.66 : (n <= 5 ? 0.6 : 0.52);
    final spread = math.min(64.0, 16.0 * (n - 1));
    final poses = <(double, PosterPose)>[];
    for (var i = 0; i < n; i++) {
      final t = n == 1 ? 0.0 : i / (n - 1) - 0.5; // −0.5 … 0.5
      final angle = t * spread;
      final r = _deg(angle);
      // On a circle around a point under the poster's middle, measured on a 390 × 693 poster.
      const pivotY = 1.05 * 693, radius = 0.42 * 693;
      final x = (195 + math.sin(r) * radius) / 390, y = (pivotY - math.cos(r) * radius) / 693;
      poses.add((t.abs(), _pose(x, y, scale, tilt: angle)));
    }
    // The outer ones first: the middle card ends up on top.
    poses.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final p in poses) p.$2];
  }

  /// One card big at the top, the others small along the foot, under it.
  static List<PosterPose> _spotlight(int n) {
    if (n == 1) return [_pose(0.5, 0.48, 1.05, tilt: -2)];
    final rest = n - 1;
    final small = rest <= 2 ? 0.46 : (rest <= 4 ? 0.36 : 0.28);
    return [
      for (var i = 0; i < rest; i++) _pose((i + 0.5) / rest, 0.84, small, tilt: (i - (rest - 1) / 2) * 4),
      _pose(0.5, 0.39, 0.84, tilt: -2),
    ];
  }

  /// Stepping down from the top left to the bottom right, each over the one before.
  static List<PosterPose> _cascade(int n) {
    final scale = n <= 2 ? 0.7 : (n <= 4 ? 0.6 : 0.5);
    return [
      for (var i = 0; i < n; i++)
        () {
          final t = n == 1 ? 0.5 : i / (n - 1);
          return _pose(0.3 + 0.4 * t, 0.27 + 0.46 * t, scale, tilt: -4);
        }(),
    ];
  }

  /// On a wall seen from aside: turned in space, the far ones smaller, the near ones bigger and on top.
  static List<PosterPose> _float(int n) {
    const far = [
      (0.27, 0.22, 0.42, 14.0, 40.0),
      (0.74, 0.2, 0.42, -12.0, -40.0),
      (0.25, 0.8, 0.44, -14.0, 38.0),
      (0.75, 0.79, 0.44, 14.0, -38.0),
      (0.18, 0.5, 0.4, 0.0, 45.0),
      (0.82, 0.5, 0.4, 0.0, -45.0),
      (0.5, 0.88, 0.36, 24.0, 0.0),
    ];
    if (n == 1) return [_pose(0.5, 0.5, 0.95, pitch: 14, yaw: -32)];
    return [
      for (final (x, y, s, p, yw) in far.take(n - 1)) _pose(x, y, s * (n <= 3 ? 1.3 : 1.0), pitch: p, yaw: yw),
      _pose(0.5, 0.5, n <= 3 ? 0.78 : 0.66, pitch: 12, yaw: -28),
    ];
  }
}

/// A preset at a glance: its layout of four cards, drawn as small rounded panes in a 9:16 frame.
class PosterPresetPreview extends StatelessWidget {
  const PosterPresetPreview({super.key, required this.preset, this.selected = false});

  final PosterPreset preset;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              for (final p in preset.layout(4).reversed)
                Positioned(
                  left: p.at.dx * box.maxWidth - box.maxWidth * 0.16,
                  top: p.at.dy * box.maxHeight - box.maxWidth * 0.24,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.004)
                      ..rotateX(p.pitch)
                      ..rotateY(p.yaw)
                      ..rotateZ(p.tilt)
                      ..scaleByDouble(p.scale, p.scale, 1, 1),
                    child: Container(
                      width: box.maxWidth * 0.32,
                      height: box.maxWidth * 0.48,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: scheme.onPrimary.withValues(alpha: 0.6)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
