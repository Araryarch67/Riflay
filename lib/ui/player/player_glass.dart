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

LiquidGlassSettings _settings(BuildContext context) => LiquidGlassSettings.ios27Regular(
  brightness: AppColors.of(context).light ? Brightness.light : Brightness.dark,
  frost: 24,
  tintAmount: 0.4,
);

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
      settings: _settings(context),
      useBackdropGroup: true,
      shape: circle ? const LiquidOval() : LiquidRoundedSuperellipse(borderRadius: corners),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}
