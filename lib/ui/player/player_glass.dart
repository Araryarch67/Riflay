import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

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
    tint: light ? const Color(0x80FFFFFF) : const Color(0xAD000000),
  );
}

LiquidGlassSettings _settings(BuildContext context) {
  final brightness = switch (LayoutPrefs.instance.playerGlassTint) {
    GlassTint.theme => PlayerGlassBackdrop.isLight(context) ? Brightness.light : Brightness.dark,
    GlassTint.light => Brightness.light,
    GlassTint.black => Brightness.dark,
  };
  return riflayGlass(brightness: brightness);
}

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
    return LiquidGlass.auto(
      appearance: riflayGlassAppearance(
        themeIsLight: PlayerGlassBackdrop.isLight(context),
        tint: LayoutPrefs.instance.playerGlassTint,
      ),
      settings: _settings(context),
      useBackdropGroup: true,
      shape: circle ? const LiquidOval() : LiquidRoundedSuperellipse(borderRadius: corners),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}
