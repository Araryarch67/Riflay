import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Color, HSLColor;

import 'appearance.dart';
import 'color_tools.dart';

/// The two colours a cover is known by: the one that fills most of it, and the liveliest other one.
class CoverColors {
  const CoverColors(this.base, this.accent);

  /// The colour family that takes up most of the cover.
  final Color base;

  /// The most vibrant colour of a different hue (a stronger version of [base] when there is none).
  final Color accent;

  @override
  bool operator ==(Object other) => other is CoverColors && other.base == base && other.accent == accent;

  @override
  int get hashCode => Object.hash(base, accent);

  @override
  String toString() => 'CoverColors(${hexOf(base)}, ${hexOf(accent)})';
}

/// The colours of a cover from its raw RGBA pixels (a small image, about 32 x 32 is plenty). Pure Dart, so
/// it can run in an isolate. Null when there is nothing to look at (no pixels, or all transparent).
CoverColors? extractCoverColors(Uint8List rgba) {
  const hues = 12;
  const neutral = hues;
  // Per bucket: pixels, summed channels and summed saturation. The last bucket holds greys, near-black and
  // near-white pixels, which have no hue worth naming.
  final count = List<int>.filled(hues + 1, 0);
  final sumR = List<int>.filled(hues + 1, 0);
  final sumG = List<int>.filled(hues + 1, 0);
  final sumB = List<int>.filled(hues + 1, 0);
  var opaque = 0;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    opaque++;
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    final hi = r > g ? (r > b ? r : b) : (g > b ? g : b);
    final lo = r < g ? (r < b ? r : b) : (g < b ? g : b);
    final l = (hi + lo) / 510;
    final d = (hi - lo) / 255;
    final s = d == 0 ? 0.0 : d / (1 - (2 * l - 1).abs());
    var bucket = neutral;
    if (s >= 0.18 && l >= 0.12 && l <= 0.92) {
      final h = _hue(r, g, b, hi, lo);
      bucket = ((h + 15) / 30).floor() % hues;
    }
    count[bucket]++;
    sumR[bucket] += r;
    sumG[bucket] += g;
    sumB[bucket] += b;
  }
  if (opaque == 0) return null;

  Color mean(int k) => Color.fromARGB(255, sumR[k] ~/ count[k], sumG[k] ~/ count[k], sumB[k] ~/ count[k]);

  // The base: the biggest family. Greys count half, so a cover that is half black and half red reads as red.
  var baseK = -1;
  var best = 0.0;
  for (var k = 0; k <= hues; k++) {
    final w = count[k] * (k == neutral ? 0.5 : 1.0);
    if (w > best) {
      best = w;
      baseK = k;
    }
  }
  final base = mean(baseK);
  final baseHsl = HSLColor.fromColor(base);
  final baseGrey = baseK == neutral;

  // The accent: the liveliest bucket of a different hue that is not just a few stray pixels.
  Color? accent;
  var bestScore = 0.0;
  for (var k = 0; k < hues; k++) {
    if (k == baseK || count[k] < opaque * 0.03) continue;
    final c = mean(k);
    final hsl = HSLColor.fromColor(c);
    if (!baseGrey && _hueGap(hsl.hue, baseHsl.hue) < 30) continue;
    final vibrancy = hsl.saturation * (1 - (2 * hsl.lightness - 1).abs());
    final score = vibrancy * math.sqrt(count[k] / opaque);
    if (score > bestScore) {
      bestScore = score;
      accent = c;
    }
  }
  // Nothing else on the cover: the same colour, livelier. A grey cover stays grey.
  accent ??= baseGrey
      ? base
      : baseHsl
            .withSaturation((baseHsl.saturation * 1.3 + 0.1).clamp(0.0, 1.0))
            .withLightness(baseHsl.lightness.clamp(0.4, 0.6))
            .toColor();
  return CoverColors(base, accent);
}

double _hue(int r, int g, int b, int hi, int lo) {
  final d = (hi - lo).toDouble();
  double h;
  if (hi == r) {
    h = ((g - b) / d) % 6;
  } else if (hi == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  return h * 60;
}

double _hueGap(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

/// A whole palette from a cover: surfaces in the cover's hue (deep on dark, pale on light; [strength] 0 is
/// nearly neutral, 1 is rich but never neon), the cover's accent lifted to read, and text that holds WCAG AA
/// on every surface (7:1 for primary and secondary text with [highContrast]). No cover: a calm neutral palette.
AppPalette paletteFromCover(CoverColors? c, {required bool light, double strength = 0.5, bool highContrast = false}) {
  final s = strength.clamp(0.0, 1.0).toDouble();
  final text = highContrast ? 7.0 : 4.5;
  final muted = highContrast ? 4.5 : 3.0;
  if (c == null) return (light ? neutralLightPalette : neutralDarkPalette).withReadableText(text: text, muted: muted);

  final hsl = HSLColor.fromColor(c.base);
  // How colourful the cover really is: a grey one stays grey.
  final chroma = ((hsl.saturation - 0.05) / 0.45).clamp(0.0, 1.0);
  final sat = light ? ((0.18 + 0.42 * s) * chroma).clamp(0.0, 0.6) : ((0.06 + 0.34 * s) * chroma).clamp(0.0, 0.42);
  Color surface(double l) => HSLColor.fromAHSL(1, hsl.hue, sat, l).toColor();

  final background = surface(light ? 0.93 : 0.07);
  final panel = surface(light ? 0.96 : 0.095);
  final elevated = surface(light ? 0.95 : 0.12);
  final hover = surface(light ? 0.90 : 0.155);
  final menu = surface(light ? 0.965 : 0.11);

  final accentHsl = HSLColor.fromColor(c.accent);
  final Color accent;
  if (accentHsl.saturation < 0.12) {
    accent = light ? const Color(0xFF3A3A3A) : const Color(0xFFD0D0D0);
  } else {
    accent = accentHsl
        .withSaturation(accentHsl.saturation.clamp(0.45, 0.85))
        .withLightness(accentHsl.lightness.clamp(light ? 0.28 : 0.55, light ? 0.42 : 0.75))
        .toColor();
  }

  Color ink(double l) => HSLColor.fromAHSL(1, hsl.hue, 0.15 * chroma, l).toColor();
  final primary = ink(light ? 0.10 : 0.95);
  return AppPalette(
    background: background,
    panel: panel,
    elevated: elevated,
    hover: hover,
    menu: menu,
    textPrimary: primary,
    textSecondary: Color.lerp(primary, panel, 0.35)!,
    textMuted: Color.lerp(primary, panel, 0.55)!,
    accent: accent,
    onAccent: onColorFor(accent),
    light: light,
  ).withReadableText(text: text, muted: muted);
}

/// The calm palette when nothing plays, on dark.
const neutralDarkPalette = AppPalette(
  background: Color(0xFF0E0E0E),
  panel: Color(0xFF141414),
  elevated: Color(0xFF1C1C1C),
  hover: Color(0xFF2A2A2A),
  menu: Color(0xFF242424),
  textPrimary: Color(0xFFF2F2F2),
  textSecondary: Color(0xFFB0B0B0),
  textMuted: Color(0xFF8A8A8A),
  accent: Color(0xFFD0D0D0),
  onAccent: Color(0xFF121212),
);

/// The calm palette when nothing plays, on light.
const neutralLightPalette = AppPalette(
  background: Color(0xFFEDEDED),
  panel: Color(0xFFF4F4F4),
  elevated: Color(0xFFFAFAFA),
  hover: Color(0xFFE2E2E2),
  menu: Color(0xFFFAFAFA),
  textPrimary: Color(0xFF151515),
  textSecondary: Color(0xFF4A4A4A),
  textMuted: Color(0xFF666666),
  accent: Color(0xFF3A3A3A),
  onAccent: Color(0xFFF4F4F4),
  light: true,
);
