import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final look = Appearance.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await look.reset();
  });
  tearDown(look.reset);

  test('component surfaces and selected controls follow every chosen scheme', () async {
    for (final choice in [ThemeChoice.nord, ThemeChoice.catppuccinLatte, ThemeChoice.gruvbox]) {
      await look.setTheme(choice);
      final theme = appThemeNow();
      final p = look.palette;
      expect(theme.dialogTheme.backgroundColor, p.menu);
      expect(theme.bottomSheetTheme.backgroundColor, p.menu);
      expect(theme.cardTheme.color, p.elevated);
      expect(theme.sliderTheme.activeTrackColor, p.accent);
      expect(theme.chipTheme.selectedColor, p.accent);
      expect(theme.switchTheme.trackColor!.resolve({WidgetState.selected}), p.accent);
      expect(theme.filledButtonTheme.style!.backgroundColor!.resolve({}), p.accent);
      expect(theme.filledButtonTheme.style!.foregroundColor!.resolve({}), p.onAccent);
      expect(theme.inputDecorationTheme.fillColor, p.textPrimary.withValues(alpha: 0.08));
      expect(theme.textSelectionTheme.cursorColor, p.accent);
      expect(theme.progressIndicatorTheme.color, p.accent);
      expect(theme.colorScheme.surfaceContainerHighest, p.hover);
    }
  });

  test('changing corners keeps the chosen button and surface colors', () async {
    await look.setTheme(ThemeChoice.nord);
    await LayoutPrefs.instance.setCorners(CornerStyle.square);
    try {
      final theme = appThemeNow();
      expect(theme.filledButtonTheme.style!.backgroundColor!.resolve({}), look.palette.accent);
      expect(theme.filledButtonTheme.style!.foregroundColor!.resolve({}), look.palette.onAccent);
      expect(theme.dialogTheme.backgroundColor, look.palette.menu);
    } finally {
      await LayoutPrefs.instance.reset();
    }
  });

  test('Matugen applies all Material roles and invalid reload keeps the rendered theme', () async {
    if (!Platform.isLinux) return;
    final dir = Directory.systemTemp.createTempSync('riflay-components-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/colors.json');
    file.writeAsStringSync(File('test/fixtures/matugen-v4.json').readAsStringSync());
    await look.setMatugenPath(file.path);
    await look.setTheme(ThemeChoice.matugen);
    await look.matugen.reload();
    final theme = appThemeNow();
    final imported = look.matugen.colors!.scheme(light: false);
    expect(theme.colorScheme.secondary, imported.secondary);
    expect(theme.colorScheme.tertiary, imported.tertiary);
    expect(theme.colorScheme.error, imported.error);
    expect(theme.colorScheme.onErrorContainer, imported.onErrorContainer);
    expect(theme.colorScheme.surface, imported.surface);
    file.writeAsStringSync('{');
    await look.matugen.reload();
    expect(appThemeNow(), same(theme));
    await look.setBrightness(ThemeBrightness.light);
    expect(appThemeNow().brightness, Brightness.light);
  });
}
