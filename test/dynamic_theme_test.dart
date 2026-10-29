import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/color_tools.dart';
import 'package:riflay/services/cover_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A [side] x [side] RGBA image: the first [share] of its pixels are [a], the rest [b].
Uint8List image(Color a, {Color? b, double share = 1, int side = 32, int alpha = 255}) {
  final out = Uint8List(side * side * 4);
  for (var i = 0; i < side * side; i++) {
    final c = i < side * side * share ? a : (b ?? a);
    out[i * 4] = (c.r * 255).round();
    out[i * 4 + 1] = (c.g * 255).round();
    out[i * 4 + 2] = (c.b * 255).round();
    out[i * 4 + 3] = alpha;
  }
  return out;
}

double worstOn(Color fg, AppPalette p) => [
  p.background,
  p.panel,
  p.elevated,
  p.hover,
  p.menu,
].map((s) => contrastRatio(fg, s)).reduce((a, b) => a < b ? a : b);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('extractCoverColors', () {
    test('solid red', () {
      final c = extractCoverColors(image(const Color(0xFFD32F2F)))!;
      final hsl = HSLColor.fromColor(c.base);
      expect(hsl.hue, closeTo(0, 3));
      expect(hsl.saturation, greaterThan(0.5));
      expect(HSLColor.fromColor(c.accent).hue, closeTo(0, 6));
    });

    test('two colours: the big one is the base, the vivid other one the accent', () {
      final c = extractCoverColors(image(const Color(0xFF1F2F5F), b: const Color(0xFFFF7A00), share: 0.7))!;
      expect(HSLColor.fromColor(c.base).hue, closeTo(223, 12));
      expect(HSLColor.fromColor(c.accent).hue, closeTo(29, 8));
    });

    test('a few stray pixels do not make an accent', () {
      final c = extractCoverColors(image(const Color(0xFF1F2F5F), b: const Color(0xFFFF7A00), share: 0.99))!;
      expect(HSLColor.fromColor(c.accent).hue, closeTo(223, 12));
    });

    test('a grey cover stays grey', () {
      final c = extractCoverColors(image(const Color(0xFF808080)))!;
      expect(HSLColor.fromColor(c.base).saturation, lessThan(0.05));
      expect(HSLColor.fromColor(c.accent).saturation, lessThan(0.15));
    });

    test('nothing to look at', () {
      expect(extractCoverColors(Uint8List(0)), isNull);
      expect(extractCoverColors(image(const Color(0xFFFF0000), alpha: 0)), isNull);
    });

    test('equality', () {
      expect(
        const CoverColors(Color(0xFF112233), Color(0xFF445566)),
        const CoverColors(Color(0xFF112233), Color(0xFF445566)),
      );
    });
  });

  group('paletteFromCover', () {
    final covers = <String, CoverColors?>{
      'red': const CoverColors(Color(0xFFB02020), Color(0xFFFF8040)),
      'blue': const CoverColors(Color(0xFF203080), Color(0xFF40C0FF)),
      'yellow': const CoverColors(Color(0xFFE0C020), Color(0xFFE0C020)),
      'green': const CoverColors(Color(0xFF20A040), Color(0xFFA0FF40)),
      'white': const CoverColors(Color(0xFFF0F0F0), Color(0xFFF0F0F0)),
      'black': const CoverColors(Color(0xFF050505), Color(0xFF050505)),
      'grey': const CoverColors(Color(0xFF808080), Color(0xFF808080)),
      'magenta': const CoverColors(Color(0xFFFF00FF), Color(0xFF00FFFF)),
      'null': null,
    };
    for (final e in covers.entries) {
      for (final light in [false, true]) {
        for (final hc in [false, true]) {
          for (final strength in [0.0, 0.5, 1.0]) {
            test('${e.key} light=$light highContrast=$hc strength=$strength reads', () {
              final p = paletteFromCover(e.value, light: light, strength: strength, highContrast: hc);
              expect(p.light, light);
              expect(worstOn(p.textPrimary, p), greaterThanOrEqualTo(hc ? 7 : 4.5));
              expect(worstOn(p.textSecondary, p), greaterThanOrEqualTo(hc ? 7 : 4.5));
              expect(worstOn(p.textMuted, p), greaterThanOrEqualTo(hc ? 4.5 : 3));
              expect(contrastRatio(p.accent, p.panel), greaterThanOrEqualTo(3));
              expect(contrastRatio(p.onAccent, p.accent), greaterThanOrEqualTo(4.5));
              final l = HSLColor.fromColor(p.background).lightness;
              expect(light ? l > 0.85 : l < 0.15, isTrue, reason: 'background lightness $l');
            });
          }
        }
      }
    }

    test('no cover is calm and neutral', () {
      for (final light in [false, true]) {
        final p = paletteFromCover(null, light: light);
        expect(HSLColor.fromColor(p.background).saturation, lessThan(0.02));
        expect(HSLColor.fromColor(p.accent).saturation, lessThan(0.02));
      }
    });

    test('strength 0 is paler than strength 1', () {
      const c = CoverColors(Color(0xFF2040C0), Color(0xFFFF8000));
      final a = HSLColor.fromColor(paletteFromCover(c, light: false, strength: 0).panel).saturation;
      final b = HSLColor.fromColor(paletteFromCover(c, light: false, strength: 1).panel).saturation;
      expect(a, lessThan(b));
    });

    test('a grey cover gets a grey accent', () {
      final p = paletteFromCover(const CoverColors(Color(0xFF808080), Color(0xFF808080)), light: false);
      expect(HSLColor.fromColor(p.accent).saturation, lessThan(0.05));
    });
  });

  group('brightness', () {
    test('Latte under dark is a Mocha-like dark palette, and back', () {
      expect(ThemeChoice.catppuccinLatte.paletteIn(light: false).light, isFalse);
      expect(ThemeChoice.catppuccinLatte.paletteIn(light: false), ThemeChoice.catppuccinMocha.palette);
      expect(ThemeChoice.catppuccinFrappe.paletteIn(light: true), ThemeChoice.catppuccinLatte.palette);
      expect(ThemeChoice.everforestDark.paletteIn(light: true), ThemeChoice.everforestLight.palette);
    });

    for (final t in ThemeChoice.values) {
      for (final light in [false, true]) {
        test('${t.label} in light=$light', () {
          final p = t.paletteIn(light: light);
          if (t == ThemeChoice.custom) {
            expect(p, t.palette, reason: 'custom keeps its own colours');
          } else {
            expect(p.light, light);
            // Authors' own colours (Everforest Light) sit a little under AA; "High contrast" lifts them.
            expect(contrastRatio(p.textPrimary, p.hover), greaterThanOrEqualTo(4));
          }
        });
      }
    }

    test('high contrast pushes text to 7:1 on every theme', () {
      for (final t in ThemeChoice.values) {
        for (final light in [false, true]) {
          final p = t.paletteIn(light: light).withHighContrast();
          expect(worstOn(p.textPrimary, p), greaterThanOrEqualTo(7), reason: t.label);
          expect(worstOn(p.textSecondary, p), greaterThanOrEqualTo(7), reason: t.label);
          expect(worstOn(p.textMuted, p), greaterThanOrEqualTo(4.5), reason: t.label);
          expect(contrastRatio(p.onAccent, p.accent), greaterThanOrEqualTo(4.5), reason: t.label);
        }
      }
    });
  });

  group('AppPalette.lerp', () {
    test('endpoints and middle', () {
      final a = ThemeChoice.standard.palette, b = ThemeChoice.nord.palette;
      expect(AppPalette.lerp(a, b, 0), a);
      expect(AppPalette.lerp(a, b, 1), b);
      expect(AppPalette.lerp(a, b, 0.5).panel, Color.lerp(a.panel, b.panel, 0.5));
    });

    test('text stays readable at every step between two covers', () {
      final a = paletteFromCover(const CoverColors(Color(0xFFE0C020), Color(0xFFE0C020)), light: false);
      final b = paletteFromCover(const CoverColors(Color(0xFF203080), Color(0xFF40C0FF)), light: false);
      for (var i = 0; i <= 12; i++) {
        final p = AppPalette.lerp(a, b, i / 12).withReadableText();
        expect(worstOn(p.textPrimary, p), greaterThanOrEqualTo(4.5));
        expect(worstOn(p.textSecondary, p), greaterThanOrEqualTo(4.5));
      }
    });
  });

  group('Appearance', () {
    test('brightness and high contrast persist, reset restores them', () async {
      SharedPreferences.setMockInitialValues({});
      final a = Appearance.instance;
      await a.reset();
      await a.setBrightness(ThemeBrightness.system);
      await a.setHighContrast(true);
      a.brightness = ThemeBrightness.dark;
      a.highContrast = false;
      await a.load();
      expect(a.brightness, ThemeBrightness.system);
      expect(a.highContrast, isTrue);
      await a.reset();
      expect(a.brightness, ThemeBrightness.dark);
      expect(a.highContrast, isFalse);
    });

    test('an old save with Latte stays light', () async {
      SharedPreferences.setMockInitialValues({
        'appearance.v1': jsonEncode({'theme': 'catppuccinLatte'}),
      });
      final a = Appearance.instance;
      await a.load();
      expect(a.brightness, ThemeBrightness.light);
      expect(a.palette.light, isTrue);
      await a.reset();
    });

    test('a theme picked brings its brightness unless following the system', () async {
      SharedPreferences.setMockInitialValues({});
      final a = Appearance.instance;
      await a.reset();
      await a.setTheme(ThemeChoice.catppuccinLatte);
      expect(a.brightness, ThemeBrightness.light);
      await a.setBrightness(ThemeBrightness.dark);
      expect(a.palette.light, isFalse);
      await a.setTheme(ThemeChoice.dynamic);
      expect(a.brightness, ThemeBrightness.dark);
      await a.setBrightness(ThemeBrightness.system);
      await a.setTheme(ThemeChoice.nord);
      expect(a.brightness, ThemeBrightness.system);
      await a.reset();
    });

    test('Dynamic follows the cover, and the same colours again change nothing', () async {
      SharedPreferences.setMockInitialValues({});
      final a = Appearance.instance;
      await a.reset();
      await a.setTheme(ThemeChoice.dynamic);
      expect(a.followsCover, isTrue);
      const c = CoverColors(Color(0xFF203080), Color(0xFF40C0FF));
      a.setCoverColors(c);
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      var notified = 0;
      void count() => notified++;
      a.addListener(count);
      expect(a.coverColorsNow, c);
      final p = a.palette;
      a.setCoverColors(c);
      expect(notified, 0);
      expect(identical(a.palette, p), isTrue);
      a.removeListener(count);
      await a.reset();
    });

    test('high contrast applies on top of a theme', () async {
      SharedPreferences.setMockInitialValues({});
      final a = Appearance.instance;
      await a.reset();
      await a.setHighContrast(true);
      final p = a.palette;
      expect(worstOn(p.textPrimary, p), greaterThanOrEqualTo(7));
      await a.reset();
    });
  });
}
