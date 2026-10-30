import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../platform/features.dart';
import '../../services/appearance.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../theme.dart';

/// The phone's tabs. Settings is one of them, so no page needs a gear of its own;
/// Downloads keeps a tab because its ring shows songs being saved.
enum PhoneTab {
  home,
  search,
  library,
  downloads,
  settings;

  /// Whether this build shows the tab.
  bool get available => this != downloads || Features.downloads;
}

typedef _TabInfo = ({PhoneTab tab, IconData icon, IconData selected, String label});

const _tabItems = <_TabInfo>[
  (tab: PhoneTab.home, icon: Icons.home_outlined, selected: Icons.home_rounded, label: 'Home'),
  (tab: PhoneTab.search, icon: Icons.search_rounded, selected: Icons.manage_search_rounded, label: 'Search'),
  (tab: PhoneTab.library, icon: Icons.library_music_outlined, selected: Icons.library_music_rounded, label: 'Library'),
  (tab: PhoneTab.downloads, icon: Icons.download_outlined, selected: Icons.download_rounded, label: 'Downloads'),
  (tab: PhoneTab.settings, icon: Icons.settings_outlined, selected: Icons.settings_rounded, label: 'Settings'),
];

/// A tab's icon. Downloads wears a progress ring while songs are being saved.
class _TabIcon extends StatelessWidget {
  const _TabIcon({required this.info, required this.selected, this.color});

  final _TabInfo info;
  final bool selected;

  /// Defaults to primary text when selected, secondary otherwise.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? (selected ? AppColors.textPrimary : AppColors.textSecondary);
    final icon = Icon(selected ? info.selected : info.icon, color: color, size: 24, key: ValueKey(selected));
    final swapped = AnimatedSwitcher(
      duration: LayoutPrefs.dur(const Duration(milliseconds: 180)),
      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
      child: icon,
    );
    if (info.tab != PhoneTab.downloads) return swapped;
    final youtube = PlayerScope.read(context).youtube;
    return ListenableBuilder(
      listenable: youtube,
      builder: (context, _) {
        final progress = youtube.activeProgress;
        return SizedBox.square(
          dimension: 24,
          child: progress == null
              ? swapped
              : Padding(
                  padding: const EdgeInsets.all(1.5),
                  child: CircularProgressIndicator(
                    value: progress == 0 ? null : progress,
                    strokeWidth: 2.2,
                    color: AppColors.accent,
                    backgroundColor: AppColors.hover,
                  ),
                ),
        );
      },
    );
  }
}

/// The phone's tabs as a rail down the left, for a phone held sideways.
class PhoneSideTabs extends StatelessWidget {
  const PhoneSideTabs({super.key, required this.tab, required this.onSelect});

  static const width = 88.0;

  final PhoneTab tab;
  final ValueChanged<PhoneTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      right: false,
      child: SizedBox(
        width: width,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              for (final i in _tabItems)
                if (i.tab.available)
                  Semantics(
                    button: true,
                    selected: tab == i.tab,
                    child: InkResponse(
                      onTap: () => onSelect(i.tab),
                      radius: 36,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: SizedBox(
                          width: width,
                          child: Column(
                            children: [
                              _TabIcon(info: i, selected: tab == i.tab),
                              const SizedBox(height: 4),
                              Text(
                                i.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.labelSmall?.copyWith(
                                  color: tab == i.tab ? AppColors.textPrimary : AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The phone's bottom area: the mini player docked above a floating tab bar. Home is the raised round button in
/// the middle, sitting in a notch cut into the bar; the other tabs are icons, and a dot marks the selected one.
/// The bar is liquid glass: the page blurs and brightens behind it, under a light rim and sheen.
class PhoneBottomBar extends StatelessWidget {
  const PhoneBottomBar({
    super.key,
    required this.mini,
    required this.tab,
    required this.onSelect,
    this.showTabs = true,
  });

  final Widget mini;
  final PhoneTab tab;
  final ValueChanged<PhoneTab> onSelect;

  /// Off when the tabs sit in [PhoneSideTabs] instead.
  final bool showTabs;

  static const _height = 60.0;

  /// The Home button's size, and how far it stands above the bar.
  static const _hub = 56.0;
  static const _rise = 34.0;

  static const _left = [PhoneTab.search, PhoneTab.library];
  static const _right = [PhoneTab.downloads, PhoneTab.settings];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final radius = LayoutPrefs.corner(28);
    final shape = _NotchedBar(radius: radius, hub: _hub, rise: _rise);
    _TabInfo info(PhoneTab t) => _tabItems.firstWhere((i) => i.tab == t);
    Widget cell(PhoneTab t) => Expanded(
      child: _BarTab(info: info(t), selected: tab == t, onTap: () => onSelect(t)),
    );
    // Each side takes half of what the Home button leaves, however many tabs it has (the web build has no Downloads).
    Widget side(List<PhoneTab> tabs) => Expanded(
      child: Row(
        children: [
          for (final t in tabs)
            if (t.available) cell(t),
        ],
      ),
    );
    final row = Row(
      children: [
        side(_left),
        // Under the Home button: its dot, when Home is the tab shown.
        SizedBox(
          width: _hub + 24,
          child: Align(
            alignment: const Alignment(0, 0.62),
            child: _Dot(on: tab == PhoneTab.home),
          ),
        ),
        side(_right),
      ],
    );
    final surface = _LiquidGlass(shape: shape, colors: colors, child: row);
    final bar = SizedBox(
      height: _height + _rise,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(left: 0, right: 0, bottom: 0, height: _height, child: surface),
          Positioned(
            top: 0,
            child: _HomeHub(size: _hub, selected: tab == PhoneTab.home, onTap: () => onSelect(PhoneTab.home)),
          ),
        ],
      ),
    );
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          mini,
          if (showTabs) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 10), child: bar),
        ],
      ),
    );
  }
}

/// One icon tab of the bottom bar: accent and a dot under it when selected.
class _BarTab extends StatelessWidget {
  const _BarTab({required this.info, required this.selected, required this.onTap});

  final _TabInfo info;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Tooltip(
        message: info.label,
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TabIcon(info: info, selected: selected, color: selected ? colors.accent : colors.textSecondary),
              const SizedBox(height: 6),
              _Dot(on: selected),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small accent dot under the selected tab.
class _Dot extends StatelessWidget {
  const _Dot({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) => AnimatedScale(
    duration: LayoutPrefs.dur(const Duration(milliseconds: 200)),
    curve: Curves.easeOutBack,
    scale: on ? 1 : 0,
    child: DecoratedBox(
      decoration: BoxDecoration(color: AppColors.of(context).accent, shape: BoxShape.circle),
      child: const SizedBox.square(dimension: 5),
    ),
  );
}

/// Home: the round accent button standing in the bar's notch.
class _HomeHub extends StatelessWidget {
  const _HomeHub({required this.size, required this.selected, required this.onTap});

  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Tooltip(
        message: 'Home',
        child: Material(
          color: colors.accent,
          shape: const CircleBorder(),
          elevation: 2,
          shadowColor: const Color(0x55000000),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              width: size,
              height: size,
              // Glass over the accent: a light top fading out, and a bright rim.
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x59FFFFFF), width: 1),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x47FFFFFF), Color(0x00FFFFFF), Color(0x14000000)],
                  stops: [0, 0.55, 1],
                ),
              ),
              child: Icon(selected ? Icons.home_rounded : Icons.home_outlined, color: colors.onAccent, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar's liquid glass. What scrolls behind is blurred and its colours lifted, then tinted with the theme's
/// raised surface (lighter at the top), edged with a rim that catches the light on top and fades towards the
/// bottom. The shadow is painted outside the clip, so it follows the notch.
class _LiquidGlass extends StatelessWidget {
  const _LiquidGlass({required this.shape, required this.colors, required this.child});

  final _NotchedBar shape;
  final AppColorsView colors;
  final Widget child;

  /// Raises saturation by [s] (1 = unchanged): blurred colours otherwise wash out to grey.
  static ColorFilter _saturate(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final i = 1 - s;
    return ColorFilter.matrix([
      r * i + s, g * i, b * i, 0, 0, //
      r * i, g * i + s, b * i, 0, 0,
      r * i, g * i, b * i + s, 0, 0,
      0, 0, 0, 1, 0,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final blur = Appearance.instance.glass ? Appearance.instance.blur.clamp(18.0, 40.0) : 24.0;
    return CustomPaint(
      painter: _GlassShadow(shape),
      child: RepaintBoundary(
        child: ClipPath(
          clipper: shape,
          child: BackdropFilter(
            filter: ImageFilter.compose(
              outer: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              inner: _saturate(1.6),
            ),
            child: CustomPaint(
              painter: _GlassFace(shape, colors.elevated, light: colors.light),
              child: Material(type: MaterialType.transparency, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassShadow extends CustomPainter {
  const _GlassShadow(this.shape);

  final _NotchedBar shape;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawShadow(shape.getClip(size), const Color(0x80000000), 6, true);

  @override
  bool shouldRepaint(_GlassShadow old) => old.shape.shouldReclip(shape);
}

class _GlassFace extends CustomPainter {
  const _GlassFace(this.shape, this.tint, {required this.light});

  final _NotchedBar shape;
  final Color tint;
  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    final path = shape.getClip(size);
    final rect = Offset.zero & size;
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tint.withValues(alpha: light ? 0.62 : 0.48),
            tint.withValues(alpha: light ? 0.78 : 0.66),
          ],
        ).createShader(rect),
    );
    // The sheen: light pooled along the top edge.
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [Color(0x1FFFFFFF), Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(light ? 0xB3FFFFFF : 0x59FFFFFF), const Color(0x0DFFFFFF)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassFace old) => old.tint != tint || old.light != light || old.shape.shouldReclip(shape);
}

/// The bar's outline: a rounded rectangle with a smooth notch around the Home button.
class _NotchedBar extends CustomClipper<Path> {
  const _NotchedBar({required this.radius, required this.hub, required this.rise});

  final BorderRadius radius;
  final double hub, rise;

  /// The gap left between the button and the notch's edge.
  static const _gap = 5.0;

  @override
  Path getClip(Size size) {
    final host = Offset.zero & size;
    // The button's centre, in the bar's coordinates (it starts [rise] above the bar).
    final guest = Rect.fromCircle(center: Offset(size.width / 2, hub / 2 - rise), radius: hub / 2 + _gap);
    final notched = const CircularNotchedRectangle().getOuterPath(host, guest);
    return Path.combine(PathOperation.intersect, notched, Path()..addRRect(radius.toRRect(host)));
  }

  @override
  bool shouldReclip(_NotchedBar old) => old.radius != radius || old.hub != hub || old.rise != rise;
}
