import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../../services/appearance.dart';
import '../../services/layout_prefs.dart';
import '../theme.dart';

/// One backdrop sample for a Liquid preset's controls; sibling surfaces share it.
class PlayerGlassLayer extends StatelessWidget {
  const PlayerGlassLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!LayoutPrefs.instance.playerGlassControls || LayoutPrefs.lightweight) return child;
    return LiquidGlassLayer(settings: _settings(context), useBackdropGroup: true, child: child);
  }
}

/// Riflay's Liquid glass, everywhere it is drawn: little frost and a lot of refraction, dispersion and rim light.
/// What makes it read as liquid glass is the page bending and catching light at the edges, not a blur (where the
/// renderer falls back to its frosted approximation, the rim light and contour still show).
LiquidGlassSettings riflayGlass({required Brightness brightness, double frost = 10, double tintAmount = 0.35}) =>
    LiquidGlassSettings.ios27Regular(
      brightness: brightness,
      frost: frost,
      tintAmount: tintAmount,
    ).copyWith(refractionHeight: 28, refractionAmount: 95, dispersion: 0.35, highlight: 0.9, contourStrength: 0.75);

/// The phone's Liquid glass bar: clear glass (iOS's `.clear`), not frosted. The page stays sharp and readable
/// through it; what makes it liquid is the edge bending the page, splitting its colours along the rim, and the
/// glint, not a blur. [dragging]: the lens under a finger bends a little more.
LiquidGlassSettings riflayClearGlass({bool dragging = false}) =>
    LiquidGlassSettings.ios27Clear(tintAmount: 0.1, frost: dragging ? 0.3 : 0.6).copyWith(
      // Bent and lit enough to read as liquid, not so much the page behind turns into a funhouse mirror.
      refractionHeight: dragging ? 28 : 22,
      refractionAmount: dragging ? 120 : 85,
      dispersion: dragging ? 0.3 : 0.18,
      highlight: 0.6,
      contourStrength: 0.5,
    );

/// Whether the bottom bar's glass reads light: Settings › Bottom bar Liquid Glass tint, or the theme's.
bool glassIsLight(bool themeIsLight, [GlassTint? tint]) => switch (tint ?? LayoutPrefs.instance.glassTint) {
  GlassTint.theme => themeIsLight,
  GlassTint.light => true,
  GlassTint.black => false,
};

/// The bottom bar glass's own colour. Following the theme it is barely there (a touch of shade); Light is a clear
/// white glass, Black a dark smoked glass the page still shows through.
Color glassTintColor(bool themeIsLight, [GlassTint? tint]) => switch (tint ?? LayoutPrefs.instance.glassTint) {
  GlassTint.theme => themeIsLight ? const Color(0x24FFFFFF) : const Color(0x2E000000),
  GlassTint.light => const Color(0x66FFFFFF),
  GlassTint.black => const Color(0xB8000000),
};

/// Clear glass's material: a touch of shade on a dark theme (or light on a light one, or as Settings › Glass
/// tint asks) so the white or dark labels on it keep their contrast over a busy page.
LiquidGlassAppearance riflayClearGlassAppearance({required bool themeIsLight, GlassTint? tint}) =>
    LiquidGlassAppearance.ios27Clear(tint: glassTintColor(themeIsLight, tint));

class PlayerGlassBackdrop extends InheritedWidget {
  const PlayerGlassBackdrop({super.key, required this.color, required super.child});

  final Color color;

  static bool isLight(BuildContext context) {
    final backdrop = context.dependOnInheritedWidgetOfExactType<PlayerGlassBackdrop>()?.color;
    return backdrop == null
        ? AppColors.of(context).light
        : ThemeData.estimateBrightnessForColor(backdrop) == Brightness.light;
  }

  @override
  bool updateShouldNotify(PlayerGlassBackdrop oldWidget) => oldWidget.color != color;
}

LiquidGlassAppearance riflayGlassAppearance({required bool themeIsLight, GlassTint? tint}) {
  final light = switch (tint ?? LayoutPrefs.instance.glassTint) {
    GlassTint.theme => themeIsLight,
    GlassTint.light => true,
    GlassTint.black => false,
  };
  return LiquidGlassAppearance.ios27Regular(
    brightness: light ? Brightness.light : Brightness.dark,
    tint: light ? const Color(0x66FFFFFF) : const Color(0x5C000000),
  );
}

bool _lightGlass(BuildContext context) => switch (LayoutPrefs.instance.playerGlassTint) {
  GlassTint.theme => PlayerGlassBackdrop.isLight(context),
  GlassTint.light => true,
  GlassTint.black => false,
};

LiquidGlassSettings _settings(BuildContext context) =>
    riflayGlass(brightness: _lightGlass(context) ? Brightness.light : Brightness.dark);

/// Frosts a control's surface in Liquid presets, with the renderer's platform fallback.
class PlayerGlassSurface extends StatelessWidget {
  const PlayerGlassSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.enabled = true,
    this.circle = false,
  });

  final Widget child;
  final double radius;

  /// A true circle (an oval on a square child) for round buttons: a superellipse with half the side as its corner
  /// radius is a squircle, which read as a circle drawn badly beside them.
  final bool circle;

  /// The part's own switch under Liquid Glass controls (the seek bar, transport and volume have one).
  final bool enabled;

  static final _lightPalette = AppPalette.derive(Colors.white);
  static final _darkPalette = AppPalette.derive(Colors.black);

  /// Foreground roles for controls drawn on the selected glass tint.
  static AppColorsView colorsOf(BuildContext context, {bool enabled = true}) {
    final colors = AppColors.of(context);
    if (!enabled || !LayoutPrefs.instance.playerGlassControls || LayoutPrefs.lightweight) return colors;
    final light = _lightGlass(context);
    return light == colors.light ? colors : AppColorsView(light ? _lightPalette : _darkPalette, 1, colors.highContrast);
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled || !LayoutPrefs.instance.playerGlassControls) return child;
    final corners = LayoutPrefs.radius(radius).clamp(0.0, radius);
    if (LayoutPrefs.lightweight) {
      final c = AppColors.of(context);
      return Material(
        color: c.elevated,
        shape: circle ? const CircleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(corners)),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }
    final colors = colorsOf(context);
    return LiquidGlass.auto(
      appearance: riflayGlassAppearance(
        themeIsLight: PlayerGlassBackdrop.isLight(context),
        tint: LayoutPrefs.instance.playerGlassTint,
      ),
      settings: _settings(context),
      useBackdropGroup: true,
      shape: circle ? const LiquidOval() : LiquidRoundedSuperellipse(borderRadius: corners),
      child: Material(
        type: MaterialType.transparency,
        child: AppColorsScope(
          colors: colors,
          child: IconTheme.merge(
            data: IconThemeData(color: colors.textPrimary, shadows: colors.light ? const [] : null),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: colors.textPrimary),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
