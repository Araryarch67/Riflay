import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../services/appearance.dart';
import '../../services/layout_prefs.dart';
import '../debug_switches.dart';
import '../theme.dart';

/// Shared gradient for sticky page headers and standard app bars.
class TopBarSurface extends StatelessWidget {
  const TopBarSurface({super.key, this.color, this.opacity = 1, this.blurBehind = false});

  final Color? color;
  final double opacity;
  final bool blurBehind;

  @override
  Widget build(BuildContext context) {
    if (opacity == 0) return const SizedBox.shrink();
    final colors = AppColors.of(context);
    final tint = color == null ? Color.lerp(colors.elevated, colors.accent, 0.14)! : AppColors.sink(color!, 0.45);
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tint.withValues(alpha: 0.88 * opacity),
            Color.lerp(tint, colors.panel, 0.45)!.withValues(alpha: 0.72 * opacity),
            colors.panel.withValues(alpha: 0.22 * opacity),
          ],
          stops: const [0, 0.72, 1],
        ),
      ),
    );
    if (!blurBehind || LayoutPrefs.lightweight || DebugSwitches.noGlassTopBar) return gradient;
    final sigma = Appearance.instance.glass ? Appearance.instance.blur.clamp(10.0, 24.0) : 16.0;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: gradient,
      ),
    );
  }
}

/// Material app bar with Riflay's header surface.
class RiflayAppBar extends AppBar {
  RiflayAppBar({super.key, super.title, super.leading, super.actions})
    : super(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: const TopBarSurface(),
      );
}
