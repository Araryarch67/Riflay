import 'package:flutter/painting.dart';

/// WCAG contrast ratio between two opaque colours (1 to 21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [fg] moved in lightness (same hue and saturation) until it reads on [bg] at [min]:1 or better.
/// Goes toward whichever of white and black stands out more on [bg], or toward white when [towardWhite] is true
/// (black when false).
Color ensureContrast(Color fg, Color bg, [double min = 4.5, bool? towardWhite]) {
  if (contrastRatio(fg, bg) >= min) return fg;
  final lighter =
      towardWhite ?? contrastRatio(const Color(0xFFFFFFFF), bg) >= contrastRatio(const Color(0xFF000000), bg);
  final hsl = HSLColor.fromColor(fg);
  for (var l = hsl.lightness; lighter ? l <= 1 : l >= 0; l += lighter ? 0.02 : -0.02) {
    final c = hsl.withLightness(l.clamp(0.0, 1.0)).toColor();
    if (contrastRatio(c, bg) >= min) return c;
  }
  return lighter ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
}

/// Text or icon colour for something filled with [bg]: a tinted near-black or near-white, whichever reads better.
Color onColorFor(Color bg) {
  final dark = Color.lerp(bg, const Color(0xFF000000), 0.88)!;
  final light = Color.lerp(bg, const Color(0xFFFFFFFF), 0.96)!;
  return contrastRatio(dark, bg) >= contrastRatio(light, bg) ? dark : light;
}

/// "#RRGGBB" for [c].
String hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Reads "#RGB", "RRGGBB" and the like; null when it isn't a colour.
Color? parseHex(String text) {
  var s = text.trim().replaceFirst('#', '');
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}
