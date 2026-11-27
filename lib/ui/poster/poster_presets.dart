import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

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
    float3d => PosterCardStyle.liquid,
    _ => null,
  };

  /// A card at scale 1 on a 390 × 693 poster: its half-size, as parts of the poster, so a pose keeps it inside.
  static const _halfWide = 130 / 390, _halfTall = 230 / 693;

  static double _deg(double d) => d * math.pi / 180;

  /// Every layout's cards at this part of the size it was drawn with: room is left for the person in the photo,
  /// who usually stands in its middle.
  static const _room = 0.72;

  static PosterPose _pose(double x, double y, double size, {double tilt = 0, double pitch = 0, double yaw = 0}) =>
      _placed(x, y, size * _room, tilt: tilt, pitch: pitch, yaw: yaw);

  static PosterPose _placed(double x, double y, double scale, {double tilt = 0, double pitch = 0, double yaw = 0}) => (
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

  /// [count] cards across the clear band above a person who fills the photo, the band ending [top] down the poster and
  /// their head at [headX], each card a little tucked behind them; this preset's own character kept (a row for grid,
  /// one big card over the head for spotlight...). [halfWide] and [halfTall]: a card's half-size at scale 1. Null for
  /// the presets that already keep together (stack, fan), or when the band is too thin for a card to be seen.
  List<PosterPose>? aboveHead(
    int count, {
    required double top,
    required double headX,
    required double halfWide,
    required double halfTall,
  }) {
    if (count <= 0 || this == stack || this == fan) return null;
    final n = math.min(count, 8);
    // Tall enough to show above the person with a third of it behind them, and the row wide enough for every card,
    // overlapping a little (grid: side by side).
    final overlap = this == grid ? 1.04 : 0.72;
    final byHeight = (top - 0.015) / 1.4 / halfTall;
    final byWidth = 0.94 / (2 * halfWide * (1 + (n - 1) * overlap));
    var scale = math.min(byHeight, byWidth);
    if (this == spotlight && n > 1) scale = math.min(byHeight, 0.94 / (2 * halfWide * (1.25 + (n - 1) * 0.6)));
    if (scale < 0.22) return null;
    final hh = halfTall * scale;
    double rowY(double s) => top - 0.4 * halfTall * s;
    final step = 2 * halfWide * scale * overlap;
    final start = 0.5 - step * (n - 1) / 2;
    final poses = <(double, PosterPose)>[];
    for (var i = 0; i < n; i++) {
      final t = n == 1 ? 0.0 : i / (n - 1) - 0.5; // −0.5 … 0.5
      final x = start + step * i;
      final PosterPose pose = switch (this) {
        scatter => _placed(x, rowY(scale) + (i.isEven ? -0.012 : 0.01), scale, tilt: (i.isEven ? -7.0 : 6.0)),
        grid => _placed(x, rowY(scale), scale),
        cascade => _placed(x, rowY(scale) - hh * 0.25 * (0.5 - t), scale, tilt: -4),
        float3d => _placed(x, rowY(scale), scale, pitch: 10, yaw: -t * 70),
        _ => _placed(x, rowY(scale), scale),
      };
      // The middle on top.
      poses.add((t.abs(), pose));
    }
    if (this == spotlight && n > 1) {
      // One big card over the head, the others smaller on either side of it.
      final big = math.min(byHeight, scale * 1.25), small = scale * 0.8;
      final side = (2 * halfWide * (big + small) / 2) * 0.62;
      // Centred, leaning towards the head: right over it, a side card had gone off the poster.
      final x0 = 0.5 + (headX - 0.5) * 0.3;
      poses
        ..clear()
        ..add((0, _placed(x0, rowY(big), big, tilt: -2)));
      for (var i = 1; i < n; i++) {
        final k = (i + 1) ~/ 2, dir = i.isOdd ? -1 : 1;
        poses.add((k.toDouble(), _placed(x0 + dir * side * k * 0.9, rowY(small), small, tilt: dir * 5.0)));
      }
    }
    poses.sort((a, b) => b.$1.compareTo(a.$1));
    final out = [for (final p in poses) p.$2];
    return [for (var i = 0; i < count; i++) out[i % out.length]];
  }

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

  /// A pile in the middle, the top card straight, each under it turned and set out to one side and the other in turn
  /// and a little higher, so every card's cover still shows past the one in front.
  static List<PosterPose> _stack(int n) {
    final scale = n <= 2 ? 0.88 : (n <= 4 ? 0.8 : 0.7);
    final reach = n <= 3 ? 0.19 : (n <= 5 ? 0.14 : 0.1);
    return [
      for (var i = 0; i < n; i++)
        () {
          final depth = n - 1 - i; // 0 for the top card
          final side = depth.isOdd ? -1.0 : 1.0;
          final out = (depth + 1) ~/ 2;
          return _pose(0.5 + side * reach * out, 0.55 - 0.035 * depth, scale, tilt: side * 8.0 * out);
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

/// Where the person is in a photo, from its cut-out: how solid they are (0–1) on a coarse grid over the photo, enough to
/// tell whether a card would be hidden behind them.
class SubjectMap {
  SubjectMap(this.width, this.height, this.alpha, {double? aspect}) : aspect = aspect ?? width / height;

  final int width, height;
  final Uint8List alpha;

  /// The photo's width over its height.
  final double aspect;

  /// The cut-out (a PNG, see-through around the person) read at 64 cells on its longer side; null when unreadable.
  static SubjectMap? fromPng(Uint8List png) {
    final image = img.decodePng(png);
    if (image == null) return null;
    final small = image.width >= image.height
        ? img.copyResize(image, width: 64, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: 64, interpolation: img.Interpolation.average);
    final alpha = Uint8List(small.width * small.height);
    for (final px in small) {
      alpha[px.y * small.width + px.x] = small.numChannels < 4 ? 255 : px.a.toInt();
    }
    return SubjectMap(small.width, small.height, alpha, aspect: image.width / image.height);
  }

  /// How solid the person is at ([u], [v]), parts of the photo; nothing outside it.
  double at(double u, double v) {
    if (u < 0 || v < 0 || u >= 1 || v >= 1) return 0;
    return alpha[(v * height).floor() * width + (u * width).floor()] / 255;
  }

  /// How much of a card centred at [at], [halfWide] × [halfTall] (parts of the poster), the person covers, 0–1, on a
  /// poster [posterAspect] (width over height) the photo covers, moved by [photoAt] and zoomed by [zoom] about its
  /// middle, as the editor draws it.
  double covering(
    Offset at,
    double halfWide,
    double halfTall, {
    required double posterAspect,
    Offset photoAt = Offset.zero,
    double zoom = 1,
  }) {
    var sum = 0.0, n = 0;
    for (var i = 0; i <= 4; i++) {
      for (var j = 0; j <= 6; j++) {
        final f = at + Offset((i / 2 - 1) * halfWide * 0.9, (j / 3 - 1) * halfTall * 0.9);
        sum += onPoster(f, posterAspect: posterAspect, photoAt: photoAt, zoom: zoom);
        n++;
      }
    }
    return sum / n;
  }

  /// How solid the person is at [f], a point of the poster (parts of it), the photo placed as [covering] has it.
  double onPoster(Offset f, {required double posterAspect, Offset photoAt = Offset.zero, double zoom = 1}) {
    // Back through the move and zoom, then the cover fit.
    final q = const Offset(0.5, 0.5) + (f - const Offset(0.5, 0.5) - photoAt) / zoom;
    final (u, v) = aspect > posterAspect
        ? (0.5 + (q.dx - 0.5) * posterAspect / aspect, q.dy)
        : (q.dx, 0.5 + (q.dy - 0.5) * aspect / posterAspect);
    return at(u, v);
  }

  /// Where the person begins, from the top, across the poster's middle: the clear band above them (parts of the
  /// poster, 1 when nobody is there), and the middle of their top, where their head is.
  ({double top, double headX}) outline({required double posterAspect, Offset photoAt = Offset.zero, double zoom = 1}) {
    final tops = <double>[];
    var highest = 1.0, headX = 0.5;
    for (var x = 0.15; x <= 0.851; x += 0.05) {
      var top = 1.0;
      for (var y = 0.0; y < 1; y += 0.01) {
        if (onPoster(Offset(x, y), posterAspect: posterAspect, photoAt: photoAt, zoom: zoom) > 0.5) {
          top = y;
          break;
        }
      }
      tops.add(top);
      if (top < highest - 0.005) {
        highest = top;
        headX = x;
      } else if ((top - highest).abs() <= 0.005) {
        headX = (headX + x) / 2;
      }
    }
    tops.sort();
    // Their shoulders more than the tip of a hat or a raised hand: the band most of the middle has clear above.
    return (top: tops[tops.length ~/ 3], headX: headX);
  }
}

/// [poses] moved where the person in the photo doesn't hide them, kept as one composition: the whole layout made
/// smaller and moved together, as little as will do, so a fan stays a fan and a row stays even, with every card inside
/// the poster. [hidden] says how much of a card the person covers (0–1) for a centre and size; [halfWide] and
/// [halfTall] are a card's half-size at scale 1, as parts of the poster. A card may stay tucked behind the person a
/// little: that is the poster's depth.
List<PosterPose> clearOfSubject(
  List<PosterPose> poses,
  double Function(Offset at, double scale) hidden, {
  required double halfWide,
  required double halfTall,
}) {
  if (poses.isEmpty) return poses;
  // Covered beyond this costs: a card peeking out from behind the person is the look, one lost behind them is not.
  const tucked = 0.35;
  double cost(List<PosterPose> layout) {
    var sum = 0.0, most = 0.0;
    for (final p in layout) {
      final over = math.max(0.0, hidden(p.at, p.scale) - tucked);
      sum += over;
      most = math.max(most, over);
    }
    return sum / layout.length * 6 + most * 4;
  }

  var best = poses;
  var least = cost(poses);
  if (least == 0) return poses;
  const middle = Offset(0.5, 0.5);
  for (var g = 1.0; g >= 0.3; g -= 0.05) {
    for (var dx = -0.45; dx <= 0.451; dx += 0.05) {
      for (var dy = -0.45; dy <= 0.451; dy += 0.05) {
        final shift = Offset(dx, dy);
        final layout = <PosterPose>[];
        var inside = true;
        for (final p in poses) {
          final at = middle + (p.at - middle) * g + shift;
          final scale = p.scale * g;
          // Whole cards only, a sliver over the edge at most, turned as they are: a layout squeezed against the edge
          // had cut cards off.
          final c = math.cos(p.tilt).abs(), sn = math.sin(p.tilt).abs();
          final hw = (halfWide * c + halfTall * sn) * scale * 0.95, hh = (halfTall * c + halfWide * sn) * scale * 0.95;
          if (at.dx < hw || at.dx > 1 - hw || at.dy < hh || at.dy > 1 - hh) {
            inside = false;
            break;
          }
          layout.add((at: at, scale: scale, tilt: p.tilt, pitch: p.pitch, yaw: p.yaw));
        }
        if (!inside) continue;
        final c = cost(layout) + (1 - g) * 1.5 + shift.distance * 0.6;
        if (c < least) {
          least = c;
          best = layout;
        }
      }
    }
  }
  return best;
}

/// A preset at a glance, as it would come out: [poses] (by default its layout of four cards) on a frame of the
/// poster's [aspect], over the [photo] with the person ([front], the cut-out) in front of the cards, the photo moved by
/// [photoAt] and zoomed by [zoom] as on the poster. Cards drawn at their true size, as small rounded panes.
class PosterPresetPreview extends StatelessWidget {
  const PosterPresetPreview({
    super.key,
    required this.preset,
    this.selected = false,
    this.poses,
    this.aspect = 9 / 16,
    this.photo,
    this.front,
    this.photoAt = Offset.zero,
    this.zoom = 1,
  });

  final PosterPreset preset;
  final bool selected;
  final List<PosterPose>? poses;
  final double aspect;
  final Uint8List? photo, front;
  final Offset photoAt;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: aspect,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, box) {
            final size = box.biggest;
            // As on the poster: a card 260 wide at scale 1, on a poster 390 units wide (see the editor's canvas).
            final unit = math.min(size.width, size.height * 9 / 16) / 390;
            final dpr = MediaQuery.devicePixelRatioOf(context);
            Widget placed(Uint8List bytes) => Positioned.fill(
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.translationValues(photoAt.dx * size.width, photoAt.dy * size.height, 0)
                  ..scaleByDouble(zoom, zoom, 1, 1),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  // Decoded small: a thumbnail, not the whole photo seven times over.
                  cacheWidth: (size.width * zoom * dpr * 1.5).round().clamp(32, 1024),
                  gaplessPlayback: true,
                ),
              ),
            );
            return Stack(
              clipBehavior: Clip.none,
              children: [
                if (photo case final photo?) placed(photo),
                for (final p in poses ?? preset.layout(4))
                  Positioned(
                    left: p.at.dx * size.width - 130 * unit,
                    top: p.at.dy * size.height - 207 * unit,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0022 / unit)
                        ..rotateX(p.pitch)
                        ..rotateY(p.yaw)
                        ..rotateZ(p.tilt)
                        ..scaleByDouble(p.scale, p.scale, 1, 1),
                      child: Container(
                        width: 260 * unit,
                        height: 414 * unit,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(30 * unit),
                          border: Border.all(color: scheme.onPrimary.withValues(alpha: 0.6)),
                        ),
                      ),
                    ),
                  ),
                if (photo != null)
                  if (front case final front?) placed(front),
              ],
            );
          },
        ),
      ),
    );
  }
}
