import 'package:flutter/material.dart';

import '../../services/appearance.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../theme.dart';
import '../widgets/controls.dart';

/// The phone's tabs. Settings is one of them, so no page needs a gear of its own;
/// Downloads keeps a tab because its ring shows songs being saved.
enum PhoneTab { home, search, library, downloads, settings }

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
  const _TabIcon({required this.info, required this.selected});

  final _TabInfo info;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.textPrimary : AppColors.textSecondary;
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

/// The phone's bottom area: the mini player docked above a floating, rounded
/// tab bar. The selected tab sits in a pill that glides to the next one; both
/// cards float clear of the screen's edge and its safe areas.
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

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final selected = _tabItems.indexWhere((i) => i.tab == tab);
    final radius = LayoutPrefs.corner(28);
    final bar = SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, box) {
          final cell = box.maxWidth / _tabItems.length;
          return Stack(
            children: [
              // The pill behind the selected tab's icon and label.
              AnimatedPositioned(
                duration: LayoutPrefs.dur(const Duration(milliseconds: 280)),
                curve: Curves.easeOutCubic,
                left: cell * selected + 4,
                top: 6,
                width: cell - 8,
                height: _height - 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final i in _tabItems)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: tab == i.tab,
                        child: InkResponse(
                          onTap: () => onSelect(i.tab),
                          radius: 32,
                          highlightShape: BoxShape.rectangle,
                          borderRadius: BorderRadius.circular(22),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _TabIcon(info: i, selected: tab == i.tab),
                              const SizedBox(height: 3),
                              // Large text sizes shrink the label before they break the bar.
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    i.label,
                                    maxLines: 1,
                                    style: text.labelSmall?.copyWith(
                                      fontSize: 11,
                                      color: tab == i.tab ? AppColors.textPrimary : AppColors.textSecondary,
                                      fontWeight: tab == i.tab ? FontWeight.w700 : FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          mini,
          if (showTabs)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: DecoratedBox(
                // A soft shadow lifts the bar off the page that scrolls behind it.
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 4))],
                ),
                child: Appearance.instance.glass
                    ? GlassPanel(color: AppColors.elevated, borderRadius: radius, child: bar)
                    : Material(
                        color: AppColors.elevated,
                        borderRadius: radius,
                        clipBehavior: Clip.antiAlias,
                        child: bar,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
