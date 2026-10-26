import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/color_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('custom theme', () {
    for (final bg in [
      const Color(0xFF000000),
      const Color(0xFF14161B),
      const Color(0xFF808080),
      const Color(0xFFFFFFFF),
      const Color(0xFFF4ECD8),
      const Color(0xFF8B1A1A),
      const Color(0xFF123456),
    ]) {
      test('text reads on ${hexOf(bg)}', () {
        final p = AppPalette.derive(bg);
        for (final s in [p.background, p.panel, p.elevated, p.hover, p.menu]) {
          expect(contrastRatio(p.textPrimary, s), greaterThanOrEqualTo(4.5), reason: 'primary on ${hexOf(s)}');
          expect(contrastRatio(p.textSecondary, s), greaterThanOrEqualTo(4.0), reason: 'secondary on ${hexOf(s)}');
        }
        expect(contrastRatio(p.onAccent, p.accent), greaterThanOrEqualTo(4.5));
      });
    }

    test('a text colour that is too faint is nudged', () {
      final p = AppPalette.derive(const Color(0xFFFFFFFF), text: const Color(0xFFEEEEEE));
      expect(contrastRatio(p.textPrimary, p.hover), greaterThanOrEqualTo(4.5));
    });
  });

  group('whole-app tint', () {
    final covers = {
      'red': const Color(0xFF8C2F2F),
      'blue': const Color(0xFF2F4F8C),
      'yellow': const Color(0xFF8C8C2F),
      'grey': const Color(0xFF666666),
      'near black': const Color(0xFF1A1A1A),
    };
    for (final theme in [ThemeChoice.standard, ThemeChoice.catppuccinLatte, ThemeChoice.everforestLight, ThemeChoice.nord]) {
      for (final e in covers.entries) {
        test('${theme.label} with a ${e.key} cover stays readable', () {
          for (final amount in [0.25, 1.0]) {
            final p = theme.palette.tinted(e.value, amount, 1);
            final base = theme.palette;
            final all = [p.background, p.panel, p.elevated, p.hover, p.menu];
            final baseAll = [base.background, base.panel, base.elevated, base.hover, base.menu];
            double worst(Color fg, List<Color> on) => on.map((s) => contrastRatio(fg, s)).reduce((a, b) => a < b ? a : b);
            // At least 4.5:1, or what the theme itself offered when that was lower.
            for (final (fg, was) in [(p.textPrimary, base.textPrimary), (p.textSecondary, base.textSecondary)]) {
              final need = worst(was, baseAll) < 4.5 ? worst(was, baseAll) : 4.5;
              expect(worst(fg, all), greaterThanOrEqualTo(need - 0.001));
            }
            final grey = HSLColor.fromColor(e.value).saturation < 0.1;
            if (grey) {
              expect(p.accent, base.accent, reason: 'a grey cover keeps the theme accent');
            } else {
              expect(worst(p.accent, all), greaterThanOrEqualTo(4.4), reason: 'accent as text');
            }
            expect(contrastRatio(p.onAccent, p.accent), greaterThanOrEqualTo(4.5));
            expect(p.light, theme.palette.light);
          }
        });
      }
    }

    test('no amount leaves the theme untouched', () {
      final base = ThemeChoice.standard.palette;
      expect(identical(base.tinted(const Color(0xFF8C2F2F), 0), base), isTrue);
    });
  });

  group('saved settings', () {
    Future<Appearance> loadWith(Map<String, Object?> saved) async {
      SharedPreferences.setMockInitialValues({'appearance.v1': jsonEncode(saved)});
      final a = Appearance.instance;
      await a.load();
      return a;
    }

    test('an old "cover colours on" becomes Player only', () async {
      final a = await loadWith({'coverColors': true});
      expect(a.coverMode, CoverColorMode.player);
    });

    test('an old "cover colours off" stays off', () async {
      final a = await loadWith({'coverColors': false});
      expect(a.coverMode, CoverColorMode.off);
      expect(a.coverColors, isFalse);
    });

    test('the new choice wins over the old flag', () async {
      final a = await loadWith({'coverColors': true, 'coverMode': 'app', 'coverStrength': 0.8});
      expect(a.coverMode, CoverColorMode.app);
      expect(a.coverStrength, 0.8);
    });

    test('custom colours survive a restart and reset puts everything back', () async {
      SharedPreferences.setMockInitialValues({});
      final a = Appearance.instance;
      await a.setCustomBackground(const Color(0xFFF4ECD8));
      await a.setCustomAccent(const Color(0xFFAA3366));
      await a.setCoverMode(CoverColorMode.app);
      await a.load();
      expect(a.theme, ThemeChoice.custom);
      expect(a.customBackground, const Color(0xFFF4ECD8));
      expect(a.accent, AccentChoice.custom);
      expect(a.palette.light, isTrue);
      await a.reset();
      expect(a.theme, ThemeChoice.standard);
      expect(a.accent, AccentChoice.theme);
      expect(a.coverMode, CoverColorMode.player);
      expect(a.coverStrength, 0.5);
    });
  });

  test('hex parsing', () {
    expect(parseHex('#2ee6c5'), const Color(0xFF2EE6C5));
    expect(parseHex('fa0'), const Color(0xFFFFAA00));
    expect(parseHex('12'), isNull);
    expect(parseHex('zzzzzz'), isNull);
  });
}
