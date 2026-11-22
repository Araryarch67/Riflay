import 'package:flutter/material.dart';

import '../../platform/features.dart';
import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../navigation.dart';
import '../pages/library_page.dart';
import '../pages/listen_together_page.dart';
import '../pages/settings_page.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/smooth_scroll.dart';
import 'first_frame_gate.dart';

/// The now-playing side panel, sliding open and shut instead of popping.
class SlidingPanel extends StatelessWidget {
  const SlidingPanel({
    super.key,
    required this.open,
    required this.child,
    this.width = LayoutPrefs.sidePanelDefault,
    this.handle,
  });

  static const gap = 8.0;

  final bool open;
  final Widget child;
  final double width;

  /// Sits in the gap on the panel's left edge; it opens and shuts with the panel.
  final Widget? handle;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: open ? 1 : 0),
    duration: const Duration(milliseconds: 280),
    curve: Curves.easeOutCubic,
    builder: (context, t, child) => t == 0
        ? const SizedBox.shrink()
        : SizedBox(
            width: (width + gap) * t,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: width + gap,
                maxWidth: width + gap,
                child: Opacity(opacity: t, child: child),
              ),
            ),
          ),
    child: handle == null
        ? Padding(
            padding: const EdgeInsets.only(left: gap),
            child: child,
          )
        : Row(
            children: [
              SizedBox(width: gap, child: handle),
              Expanded(child: child),
            ],
          ),
  );
}

class ShellPanel extends StatelessWidget {
  const ShellPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final panel = Material(
      color: colors.panel,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    if (!colors.glass) return panel;
    // Glass over the cover: a hairline edge, brighter at the top, and a soft sheen fading down from it.
    const edge = Colors.white;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        panel,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: edge.withValues(alpha: colors.light ? 0.55 : 0.09)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.22],
                  colors: [
                    edge.withValues(alpha: colors.light ? 0.25 : 0.06),
                    edge.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    super.key,
    required this.collapsed,
    required this.location,
    required this.onHome,
    required this.onSearch,
    this.inTitleBar = false,
    this.shortcuts = false,
  });

  final bool collapsed;
  final bool inTitleBar;
  final bool shortcuts;

  /// What's on screen, so its entry can be highlighted.
  final String location;
  final VoidCallback onHome;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget item(String where, IconData icon, IconData selectedIcon, String label, VoidCallback onTap) {
      final selected = location == where;
      final color = selected ? AppColors.textPrimary : AppColors.textSecondary;
      final row = InkWell(
        borderRadius: BorderRadius.circular(6),
        hoverColor: Colors.transparent,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(selected ? selectedIcon : icon, color: color, size: 26),
              if (!collapsed) ...[
                const SizedBox(width: 18),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      return collapsed ? Tooltip(message: label, child: row) : row;
    }

    // With the title bar, Home and search sit in it and Downloads, Listen together and Settings in its ⋯ menu:
    // the sidebar is then the library alone, nothing listed twice.
    final navItems = [
      if (!inTitleBar) ...[
        item(Locations.home, Icons.home_outlined, Icons.home_rounded, tr.navHome, onHome),
        item(Locations.search, Icons.search_rounded, Icons.manage_search_rounded, tr.navSearch, onSearch),
        if (Features.downloads) DownloadsLink(collapsed: collapsed, selected: location == Locations.downloads),
        if (Features.listenTogether)
          item(Locations.listen, Icons.group_outlined, Icons.group_rounded, tr.listenTogether, () {
            if (location != Locations.listen) {
              ShellScope.of(context).open(const ListenTogetherPage(), location: Locations.listen);
            }
          }),
        item(Locations.settings, Icons.settings_outlined, Icons.settings_rounded, tr.navSettings, () {
          if (location != Locations.settings) ShellScope.of(context).open(const SettingsPage());
        }),
      ],
    ];

    if (shortcuts) return ShortcutRail(location: location, onHome: onHome, onSearch: onSearch);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Short windows can't fit the nav and a usable library list: collapse into
        // one scrolling panel and reach the library through a link instead.
        if (constraints.maxHeight < 440) {
          return ShellPanel(
            child: SmoothScroll(
              builder: (context, scroll) => ListView(
                controller: scroll,
                padding: const EdgeInsets.all(8),
                children: [
                  ...navItems,
                  NavLink(
                    collapsed: collapsed,
                    icon: Icons.open_in_full_rounded,
                    iconSize: 16,
                    label: tr.expandLibrary,
                    onTap: () => ShellScope.of(context).open(const LibraryPage()),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            if (navItems.isNotEmpty) ...[
              ShellPanel(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(children: navItems),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              // The list (thousands of albums and artists behind it) fills in right after the first frame.
              child: ShellPanel(
                child: FirstFrameGate(child: LibraryList(dense: true, collapsed: collapsed)),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The "Shortcut rail" sidebar: the mark, the main pages as icons, and Settings at the foot.
class ShortcutRail extends StatelessWidget {
  const ShortcutRail({super.key, required this.location, required this.onHome, required this.onSearch});

  static const width = 64.0;

  final String location;
  final VoidCallback onHome;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    Widget item(String where, IconData icon, IconData selectedIcon, String label, VoidCallback onTap) => _RailIcon(
      icon: location == where ? selectedIcon : icon,
      label: label,
      selected: location == where,
      onTap: location == where ? null : onTap,
    );
    final settings = item(Locations.settings, Icons.settings_outlined, Icons.settings_rounded, tr.navSettings, () {
      shell.open(const SettingsPage());
    });
    return ShellPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final top = [
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 10),
              child: Tooltip(
                message: tr.navHome,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: location == Locations.home ? null : onHome,
                  child: const Padding(padding: EdgeInsets.all(6), child: AppLogo(size: 28)),
                ),
              ),
            ),
            item(Locations.home, Icons.home_outlined, Icons.home_rounded, tr.navHome, onHome),
            item(Locations.search, Icons.search_rounded, Icons.manage_search_rounded, tr.navSearch, onSearch),
            item(Locations.library, Icons.library_music_outlined, Icons.library_music_rounded, tr.navLibrary, () {
              shell.open(const LibraryPage(), location: Locations.library);
            }),
            if (Features.downloads) DownloadsLink(collapsed: true, selected: location == Locations.downloads),
            if (Features.listenTogether)
              item(Locations.listen, Icons.group_outlined, Icons.group_rounded, tr.listenTogether, () {
                shell.open(const ListenTogetherPage(), location: Locations.listen);
              }),
          ];
          // Settings stays at the foot; a short window scrolls everything instead of overlapping.
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    ...top,
                    const Spacer(),
                    Padding(padding: const EdgeInsets.only(bottom: 10), child: settings),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RailIcon extends StatelessWidget {
  const _RailIcon({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 24, color: selected ? AppColors.textPrimary : AppColors.textSecondary),
        ),
      ),
    ),
  );
}

/// Sidebar entry that opens a page (rather than switching tab).
class NavLink extends StatelessWidget {
  const NavLink({
    super.key,
    required this.collapsed,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconSize = 26,
  });

  final bool collapsed;
  final IconData icon;
  final double iconSize;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final row = InkWell(
      borderRadius: BorderRadius.circular(6),
      hoverColor: Colors.transparent,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.textSecondary, size: iconSize),
            if (!collapsed) ...[
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return collapsed ? Tooltip(message: label, child: row) : row;
  }
}

/// The title bar's ⋯ button: Downloads and Settings. A ring around it shows
/// downloads in progress.
class TitleBarMenu extends StatelessWidget {
  const TitleBarMenu({super.key, required this.onDownloads, required this.onListen, required this.onSettings});

  final VoidCallback onDownloads;
  final VoidCallback onListen;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: c.youtube,
      builder: (context, _) {
        final progress = c.youtube.activeProgress;
        // Compact, like a desktop app's menu: short rows, small text and icons.
        PopupMenuItem<VoidCallback> entry(IconData icon, String label, VoidCallback onTap, {Widget? trailing}) =>
            PopupMenuItem(
              value: onTap,
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: text.bodyMedium?.copyWith(fontSize: 13, color: AppColors.textPrimary),
              child: Row(
                children: [
                  Icon(icon, size: 17, color: AppColors.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label)),
                  ?trailing,
                ],
              ),
            );
        return PopupMenuButton<VoidCallback>(
          // Over the whole window, so a click anywhere closes it.
          useRootNavigator: true,
          tooltip: tr.more,
          position: PopupMenuPosition.under,
          constraints: const BoxConstraints(minWidth: 180),
          menuPadding: const EdgeInsets.symmetric(vertical: 4),
          onSelected: (open) => open(),
          style: IconButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            minimumSize: const Size(36, 36),
            fixedSize: const Size(36, 36),
            padding: EdgeInsets.zero,
          ),
          icon: Stack(
            alignment: Alignment.center,
            children: [
              if (progress != null)
                SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(
                    value: progress == 0 ? null : progress,
                    strokeWidth: 2,
                    color: AppColors.accent,
                    backgroundColor: AppColors.hover,
                  ),
                ),
              const Icon(Icons.more_horiz_rounded, size: 24),
            ],
          ),
          itemBuilder: (context) => [
            if (Features.downloads)
              entry(
                Icons.download_rounded,
                tr.navDownloads,
                onDownloads,
                trailing: progress == null
                    ? null
                    : Text(
                        '${c.youtube.activeCount}',
                        style: text.labelSmall?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700),
                      ),
              ),
            if (Features.listenTogether) entry(Icons.group_outlined, tr.listenTogether, onListen),
            entry(Icons.settings_outlined, tr.navSettings, onSettings),
          ],
        );
      },
    );
  }
}

/// Sidebar entry for YouTube downloads, with a progress ring while busy.
class DownloadsLink extends StatelessWidget {
  const DownloadsLink({super.key, required this.collapsed, required this.selected});

  final bool collapsed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: c.youtube,
      builder: (context, _) {
        final progress = c.youtube.activeProgress;
        final row = InkWell(
          borderRadius: BorderRadius.circular(6),
          hoverColor: Colors.transparent,
          onTap: selected ? null : shell.openDownloads,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                SizedBox.square(
                  dimension: 26,
                  child: progress == null
                      ? Icon(
                          Icons.download_rounded,
                          color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                          size: 26,
                        )
                      : Padding(
                          padding: const EdgeInsets.all(3),
                          child: CircularProgressIndicator(
                            value: progress == 0 ? null : progress,
                            strokeWidth: 2.5,
                            color: AppColors.accent,
                            backgroundColor: AppColors.hover,
                          ),
                        ),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      tr.navDownloads,
                      style: text.titleMedium?.copyWith(
                        color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (progress != null)
                    Text(
                      '${c.youtube.activeCount}',
                      style: text.labelLarge?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700),
                    ),
                ],
              ],
            ),
          ),
        );
        return collapsed ? Tooltip(message: tr.navDownloads, child: row) : row;
      },
    );
  }
}
