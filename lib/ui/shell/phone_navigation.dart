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

/// The phone's bottom area: the mini player above the tab bar, in the style picked in Settings › Look & feel ›
/// Layout ([TabBarStyle]). Docked styles run edge to edge on the app's background, down under the home indicator:
///
/// - Classic: an icon and a label per tab.
/// - Material: the same, the selected icon in a soft accent pill (as Android's own bar).
/// - Underline: labels with a short accent line over the selected tab.
/// - Minimal: icons only, a dot under the selected one.
/// - Text only: just the labels.
///
/// The others hover above the edge:
///
/// - Floating: a rounded bar of icons and labels, the selected icon in an accent pill.
/// - Capsule: icons; the selected tab widens into an accent capsule with its name.
/// - Dock: a small bar in the middle, icons only, the selected one in an accent circle.
/// - Centre button: Home raised in the middle, in a notch cut into a plain bar.
/// - Liquid glass: the same shape, the page blurring behind it.
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LayoutPrefs.instance,
    builder: (context, _) {
      final style = LayoutPrefs.instance.tabBar;
      if (showTabs && style.docked) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SafeArea(top: false, bottom: false, child: mini),
            _DockedBar(style: style, tab: tab, onSelect: onSelect),
          ],
        );
      }
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            mini,
            if (showTabs)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: switch (style) {
                  TabBarStyle.glass => _NotchBar(tab: tab, onSelect: onSelect, glass: true),
                  TabBarStyle.centre => _NotchBar(tab: tab, onSelect: onSelect, glass: false),
                  TabBarStyle.dock => Center(
                    child: _DockBar(tab: tab, onSelect: onSelect),
                  ),
                  _ => _FloatingBar(style: style, tab: tab, onSelect: onSelect),
                },
              ),
          ],
        ),
      );
    },
  );
}

_TabInfo _info(PhoneTab t) => _tabItems.firstWhere((i) => i.tab == t);

/// Every tab this build shows, in order.
Iterable<_TabInfo> get _shownTabs => _tabItems.where((i) => i.tab.available);

/// One row of tabs drawn by [item], each as wide as the others, or with [wideSelected] the selected one twice as wide.
Widget _tabRow(
  PhoneTab tab,
  ValueChanged<PhoneTab> onSelect,
  Widget Function(_TabInfo info, bool selected) item, {
  bool wideSelected = false,
}) => Material(
  type: MaterialType.transparency,
  child: Row(
    children: [
      for (final i in _shownTabs)
        Expanded(
          flex: wideSelected && tab == i.tab ? 2 : 1,
          child: _TabButton(
            info: i,
            selected: tab == i.tab,
            onTap: () => onSelect(i.tab),
            child: item(i, tab == i.tab),
          ),
        ),
    ],
  ),
);

/// The docked styles: flat, edge to edge, a hairline on top.
class _DockedBar extends StatelessWidget {
  const _DockedBar({required this.style, required this.tab, required this.onSelect});

  final TabBarStyle style;
  final PhoneTab tab;
  final ValueChanged<PhoneTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final inset = MediaQuery.paddingOf(context);
    final height = switch (style) {
      TabBarStyle.material => 66.0,
      TabBarStyle.minimal || TabBarStyle.text => 52.0,
      _ => 58.0,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.solidBackground,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(inset.left, 0, inset.right, inset.bottom),
        child: SizedBox(
          height: height,
          child: _tabRow(tab, onSelect, (i, selected) {
            return switch (style) {
              TabBarStyle.material => _IconOverLabel(info: i, selected: selected, pill: true),
              TabBarStyle.underline => _Underlined(info: i, selected: selected),
              TabBarStyle.minimal => _IconAndDot(info: i, selected: selected),
              TabBarStyle.text => Center(
                child: _TabLabel(info: i, selected: selected, accent: true),
              ),
              _ => _IconOverLabel(info: i, selected: selected),
            };
          }),
        ),
      ),
    );
  }
}

/// Floating and Capsule: a rounded bar on the raised surface, a soft shadow under it.
class _FloatingBar extends StatelessWidget {
  const _FloatingBar({required this.style, required this.tab, required this.onSelect});

  final TabBarStyle style;
  final PhoneTab tab;
  final ValueChanged<PhoneTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final capsule = style == TabBarStyle.capsule;
    return _RaisedSurface(
      radius: LayoutPrefs.corner(capsule ? 32 : 22),
      child: SizedBox(
        height: capsule ? 60 : 64,
        child: _tabRow(
          tab,
          onSelect,
          (i, selected) =>
              capsule ? _Capsule(info: i, selected: selected) : _IconOverLabel(info: i, selected: selected, pill: true),
          wideSelected: capsule,
        ),
      ),
    );
  }
}

/// Dock: only as wide as its icons, in the middle.
class _DockBar extends StatelessWidget {
  const _DockBar({required this.tab, required this.onSelect});

  final PhoneTab tab;
  final ValueChanged<PhoneTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return _RaisedSurface(
      radius: LayoutPrefs.corner(30),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Material(
          type: MaterialType.transparency,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final i in _shownTabs)
                SizedBox.square(
                  dimension: 52,
                  child: _TabButton(
                    info: i,
                    selected: tab == i.tab,
                    onTap: () => onSelect(i.tab),
                    child: Center(
                      child: AnimatedContainer(
                        duration: LayoutPrefs.dur(const Duration(milliseconds: 200)),
                        curve: Curves.easeOut,
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tab == i.tab ? colors.accent : colors.accent.withValues(alpha: 0),
                        ),
                        child: _TabIcon(
                          info: i,
                          selected: tab == i.tab,
                          color: tab == i.tab ? colors.onAccent : colors.textSecondary,
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

/// The plain raised surface the hovering bars sit on: the theme's raised colour, a hairline edge, a soft shadow.
class _RaisedSurface extends StatelessWidget {
  const _RaisedSurface({required this.radius, required this.child});

  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.elevated,
        borderRadius: radius,
        border: Border.all(color: colors.border),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}

/// What every tab shares: one button named by its label, for screen readers and as a tooltip.
class _TabButton extends StatelessWidget {
  const _TabButton({required this.info, required this.selected, required this.onTap, required this.child});

  final _TabInfo info;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: info.label,
    excludeSemantics: true,
    child: Tooltip(
      message: info.label,
      child: InkResponse(onTap: onTap, radius: 32, child: child),
    ),
  );
}

/// A tab's name under or beside its icon. Large text grows it only so far, as Material's own navigation bar does,
/// and a name still too wide for its tab shrinks to fit, so the icons all stay one size.
class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.info, required this.selected, this.accent = false, this.color});

  final _TabInfo info;
  final bool selected;

  /// The selected name in the accent colour, for styles with no icon to carry it.
  final bool accent;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: color ?? (selected ? (accent ? colors.accent : colors.textPrimary) : colors.textSecondary),
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      fontSize: accent ? 13 : null,
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(info.label, maxLines: 1, style: style),
        ),
      ),
    );
  }
}

/// The selected icon is filled and in the accent colour; the others are outlines in the secondary text colour.
Widget _icon(BuildContext context, _TabInfo info, bool selected) {
  final colors = AppColors.of(context);
  return _TabIcon(info: info, selected: selected, color: selected ? colors.accent : colors.textSecondary);
}

/// Classic, Material and Floating: an icon over its name; with [pill], an accent wash behind the selected icon.
class _IconOverLabel extends StatelessWidget {
  const _IconOverLabel({required this.info, required this.selected, this.pill = false});

  final _TabInfo info;
  final bool selected;
  final bool pill;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final icon = _icon(context, info, selected);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (pill)
          AnimatedContainer(
            duration: LayoutPrefs.dur(const Duration(milliseconds: 200)),
            curve: Curves.easeOut,
            width: 56,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: selected ? 0.16 : 0),
              borderRadius: BorderRadius.circular(15),
            ),
            child: icon,
          )
        else
          icon,
        const SizedBox(height: 4),
        _TabLabel(info: info, selected: selected),
      ],
    );
  }
}

/// Underline: the name, with a short accent line along the bar's top edge over the selected tab.
class _Underlined extends StatelessWidget {
  const _Underlined({required this.info, required this.selected});

  final _TabInfo info;
  final bool selected;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Align(
        alignment: Alignment.topCenter,
        child: AnimatedContainer(
          duration: LayoutPrefs.dur(const Duration(milliseconds: 200)),
          curve: Curves.easeOut,
          width: selected ? 28 : 0,
          height: 3,
          decoration: BoxDecoration(
            color: AppColors.of(context).accent,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
          ),
        ),
      ),
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _icon(context, info, selected),
            const SizedBox(height: 4),
            _TabLabel(info: info, selected: selected),
          ],
        ),
      ),
    ],
  );
}

/// Minimal: the icon alone, a dot under the selected one.
class _IconAndDot extends StatelessWidget {
  const _IconAndDot({required this.info, required this.selected});

  final _TabInfo info;
  final bool selected;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _icon(context, info, selected),
      const SizedBox(height: 5),
      _Dot(on: selected),
    ],
  );
}

/// Capsule: the icon alone, or for the selected tab the icon and its name on an accent capsule.
class _Capsule extends StatelessWidget {
  const _Capsule({required this.info, required this.selected});

  final _TabInfo info;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: AnimatedContainer(
        duration: LayoutPrefs.dur(const Duration(milliseconds: 220)),
        curve: Curves.easeOut,
        height: 40,
        padding: EdgeInsets.symmetric(horizontal: selected ? 10 : 0),
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.accent.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TabIcon(info: info, selected: selected, color: selected ? colors.onAccent : colors.textSecondary),
            if (selected) ...[
              const SizedBox(width: 6),
              Flexible(
                child: _TabLabel(info: info, selected: true, color: colors.onAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Centre button and Liquid glass: Home raised in a notch in the middle of the bar, the other tabs as icons with a
/// dot under the selected one. With [glass] the page blurs behind the bar; without, it is the plain raised surface.
class _NotchBar extends StatelessWidget {
  const _NotchBar({required this.tab, required this.onSelect, required this.glass});

  final PhoneTab tab;
  final ValueChanged<PhoneTab> onSelect;
  final bool glass;

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
    Widget cell(PhoneTab t) => Expanded(
      child: _BarTab(info: _info(t), selected: tab == t, onTap: () => onSelect(t)),
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
    final surface = glass
        ? _LiquidGlass(shape: shape, colors: colors, child: row)
        : _SolidNotched(shape: shape, colors: colors, child: row);
    return SizedBox(
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

/// The notched bar without the glass: the theme's raised colour under a hairline, and the same shadow.
class _SolidNotched extends StatelessWidget {
  const _SolidNotched({required this.shape, required this.colors, required this.child});

  final _NotchedBar shape;
  final AppColorsView colors;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _GlassShadow(shape),
    foregroundPainter: _Outline(shape, colors.border),
    child: ClipPath(
      clipper: shape,
      child: ColoredBox(
        color: colors.elevated,
        child: Material(type: MaterialType.transparency, child: child),
      ),
    ),
  );
}

class _Outline extends CustomPainter {
  const _Outline(this.shape, this.color);

  final _NotchedBar shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    shape.getClip(size),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color,
  );

  @override
  bool shouldRepaint(_Outline old) => old.color != color || old.shape.shouldReclip(shape);
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
