import 'package:flutter/material.dart';

import '../../services/language.dart';

/// A photo's colour grade: each value at its neutral leaves the photo as it is.
@immutable
class PhotoGrade {
  const PhotoGrade({
    this.brightness = 0,
    this.contrast = 1,
    this.saturation = 1,
    this.warmth = 0,
    this.fade = 0,
    this.vignette = 0,
  });

  /// −0.5 to 0.5: added light.
  final double brightness;

  /// 0.5 to 1.5: spread from the middle grey.
  final double contrast;

  /// 0 (grey) to 2.
  final double saturation;

  /// −1 (cool, blue) to 1 (warm, orange).
  final double warmth;

  /// 0 to 1: blacks lifted to a soft, washed grey, as an old print.
  final double fade;

  /// 0 to 1: the corners darkened.
  final double vignette;

  static const original = PhotoGrade();

  PhotoGrade copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? warmth,
    double? fade,
    double? vignette,
  }) => PhotoGrade(
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    warmth: warmth ?? this.warmth,
    fade: fade ?? this.fade,
    vignette: vignette ?? this.vignette,
  );

  /// The grade as one 4×5 colour matrix (vignette aside, which is drawn over the photo).
  List<double> get matrix {
    // Saturation, about the eye's own weights for red, green and blue.
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final s = saturation;
    var m = <double>[
      lr * (1 - s) + s,
      lg * (1 - s),
      lb * (1 - s),
      0,
      0,
      lr * (1 - s),
      lg * (1 - s) + s,
      lb * (1 - s),
      0,
      0,
      lr * (1 - s),
      lg * (1 - s),
      lb * (1 - s) + s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
    // Contrast about the middle grey, brightness and fade as offsets (in 0–255).
    final c = contrast;
    final lift = 128 * (1 - c) + brightness * 255 + fade * 60;
    final keep = c * (1 - fade * 0.25);
    m = _times([keep, 0, 0, 0, lift, 0, keep, 0, 0, lift, 0, 0, keep, 0, lift, 0, 0, 0, 1, 0], m);
    // Warmth: red up and blue down, or the other way.
    final w = warmth;
    m = _times([1 + 0.12 * w, 0, 0, 0, 12 * w, 0, 1, 0, 0, 0, 0, 0, 1 - 0.12 * w, 0, -12 * w, 0, 0, 0, 1, 0], m);
    return m;
  }

  /// [a] after [b], both 4×5 colour matrices.
  static List<double> _times(List<double> a, List<double> b) {
    double at(List<double> m, int r, int c) => c == 5 ? (r == 3 ? 1 : 0) : m[r * 5 + c];
    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        var v = 0.0;
        for (var k = 0; k < 4; k++) {
          v += a[r * 5 + k] * at(b, k, c);
        }
        if (c == 4) v += a[r * 5 + 4];
        out[r * 5 + c] = v;
      }
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is PhotoGrade &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation &&
      other.warmth == warmth &&
      other.fade == fade &&
      other.vignette == vignette;

  @override
  int get hashCode => Object.hash(brightness, contrast, saturation, warmth, fade, vignette);
}

/// Ready-made grades.
enum PhotoFilter {
  original(PhotoGrade.original),
  vivid(PhotoGrade(contrast: 1.15, saturation: 1.4)),
  warm(PhotoGrade(warmth: 0.6, saturation: 1.1, brightness: 0.03)),
  cool(PhotoGrade(warmth: -0.6, contrast: 1.05)),
  mono(PhotoGrade(saturation: 0, contrast: 1.15)),
  faded(PhotoGrade(fade: 0.5, saturation: 0.8, contrast: 0.9)),
  film(PhotoGrade(fade: 0.25, warmth: 0.3, saturation: 0.9, contrast: 1.1, vignette: 0.35));

  const PhotoFilter(this.grade);
  final PhotoGrade grade;

  String get label => switch (this) {
    original => tr.posterFilterOriginal,
    vivid => tr.posterFilterVivid,
    warm => tr.posterFilterWarm,
    cool => tr.posterFilterCool,
    mono => tr.posterFilterMono,
    faded => tr.posterFilterFaded,
    film => tr.posterFilterFilm,
  };
}

/// [child] (the photo or its cut-out) in [grade]'s colours.
class Graded extends StatelessWidget {
  const Graded({super.key, required this.grade, required this.child});

  final PhotoGrade grade;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      grade == PhotoGrade.original ? child : ColorFiltered(colorFilter: ColorFilter.matrix(grade.matrix), child: child);
}

/// The grade's darkened corners, over the photo.
class Vignette extends StatelessWidget {
  const Vignette({super.key, required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context) => amount <= 0
      ? const SizedBox.shrink()
      : IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 0.95,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.85 * amount),
                ],
                stops: const [0.55, 1],
              ),
            ),
          ),
        );
}
