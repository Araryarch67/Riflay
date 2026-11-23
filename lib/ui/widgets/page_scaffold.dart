import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../services/appearance.dart';
import '../../services/layout_prefs.dart';
import '../debug_switches.dart';
import '../shell_scope.dart';
import '../theme.dart';
import 'app_logo.dart';
import 'smooth_scroll.dart';
import '../../services/language.dart';
import 'title_bar.dart' show hasCustomTitleBar;
import 'top_bar_surface.dart';

/// Scrolling page with a top colour wash and a sticky title bar that fades in on scroll.
class PageScaffold extends StatefulWidget {
  const PageScaffold({
    super.key,
    required this.slivers,
    this.gradientColor,
    this.title,
    this.actions = const [],
    this.brand = false,
    this.hideToolbar = false,
    this.transparent = false,
    this.overHero = false,
    this.pinned,
    this.pinnedHeight = 0,
  });

  /// Stays under the top bar, [pinnedHeight] tall, while the page scrolls beneath it: Settings' preview on a phone,
  /// in view as the options under it change.
  final Widget? pinned;
  final double pinnedHeight;

  final List<Widget> slivers;
  final Color? gradientColor;
  final String? title;
  final List<Widget> actions;

  /// The app's mark and name at the left of the bar, on phones (desktop windows have it in the title bar).
  final bool brand;
  final bool hideToolbar;

  /// No panel and no colour wash behind the page: what is under it shows (the search popup's dimmed window).
  final bool transparent;

  /// The first thing on the page is a picture that goes to the very top, under the status bar: the bar then floats over
  /// it (a round back button) and only fills in once the picture has scrolled away.
  final bool overHero;

  @override
  State<PageScaffold> createState() => _PageScaffoldState();
}

class _PageScaffoldState extends State<PageScaffold> {
  final _scroll = SmoothScrollController();
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (widget.hideToolbar) return;
      final o = _scroll.offset.clamp(0.0, 300.0);
      if ((o - _offset).abs() > 4 || o == 0 || o == 300) setState(() => _offset = o);
    });
  }

  @override
  void didUpdateWidget(covariant PageScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hideToolbar && !widget.hideToolbar && _scroll.hasClients) {
      _offset = _scroll.offset.clamp(0.0, 300.0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final color = widget.gradientColor ?? AppColors.elevated;
    // Pages below this one, not above: Navigator.canPop() goes stale on a root page rebuilt while covered.
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    // Desktop: Back / Forward live in the title bar; the bar here only carries the title.
    final history = shell.history;
    final brand = widget.brand && shell.compact && !hasCustomTitleBar;
    final showBar = !widget.hideToolbar && (history != null || canPop || widget.actions.isNotEmpty || brand);
    final barOpacity = (widget.overHero ? (_offset - 240) / 60 : (_offset - 180) / 80).clamp(0.0, 1.0);
    final phoneGlass =
        shell.compact &&
        LayoutPrefs.instance.tabBar == TabBarStyle.glass &&
        !LayoutPrefs.lightweight &&
        !DebugSwitches.noGlassTopBar;
    final phoneBlur = (Appearance.instance.glass ? Appearance.instance.blur.clamp(18.0, 40.0) : 24.0) * barOpacity;
    const barHeight = 56.0;
    final topInset = shell.compact ? MediaQuery.paddingOf(context).top : 0.0;

    return Material(
      color: widget.transparent || LayoutPrefs.instance.coverGlass ? Colors.transparent : AppColors.panel,
      child: Stack(
        children: [
          // Colour wash behind the header. It scrolls with the page, as part of it: held in place it seemed to follow
          // the content. Not under a hero: the cover is the header there.
          if (!widget.overHero && !widget.transparent && !LayoutPrefs.instance.coverGlass)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 420,
              child: AnimatedBuilder(
                animation: _scroll,
                builder: (context, wash) =>
                    Transform.translate(offset: Offset(0, _scroll.hasClients ? -_scroll.offset : 0), child: wash),
                // Its own layer: scrolling moves it, never repaints it.
                child: RepaintBoundary(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          color.withValues(alpha: 0.85 * AppColors.washStrength),
                          color.withValues(alpha: 0.25 * AppColors.washStrength),
                          AppColors.panel,
                        ],
                        stops: const [0, 0.55, 1],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          CustomScrollView(
            controller: _scroll,
            slivers: [
              if (widget.pinned case final pinned?)
                // The room under the bar and the pinned part as one header, so it holds under the bar, not behind it.
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedHeader(
                    gap: topInset + (showBar ? barHeight : 8),
                    height: widget.pinnedHeight,
                    color: AppColors.panel,
                    child: pinned,
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: widget.overHero || widget.transparent ? 0 : topInset + (showBar ? barHeight : 8),
                  ),
                ),
              ...widget.slivers,
              // Clears the phone's floating player and tab bar.
              SliverToBoxAdapter(child: SizedBox(height: 32 + MediaQuery.paddingOf(context).bottom)),
            ],
          ),
          if (!widget.hideToolbar)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              // Only the buttons take clicks: the bar's empty area must not swallow
              // taps meant for what scrolls under it (e.g. the search box).
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: !shell.compact
                          ? TopBarSurface(color: color, opacity: barOpacity, blurBehind: true)
                          : phoneGlass && barOpacity > 0
                          ? ClipRect(
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: phoneBlur, sigmaY: phoneBlur),
                                child: ColoredBox(
                                  color: AppColors.sink(color, 0.45).withValues(alpha: 0.4 * barOpacity),
                                ),
                              ),
                            )
                          : ColoredBox(color: AppColors.sink(color, 0.45).withValues(alpha: barOpacity)),
                    ),
                  ),
                  Container(
                    height: (showBar ? barHeight : 8) + topInset,
                    padding: EdgeInsets.only(top: topInset, left: 8, right: 8),
                    child: Row(
                      children: [
                        if (history == null && canPop)
                          IconButton.filled(
                            tooltip: tr.back,
                            style: IconButton.styleFrom(backgroundColor: Colors.black45, foregroundColor: Colors.white),
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                        const SizedBox(width: 8),
                        if (brand) ...[
                          const AppLogo(size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Riflay',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
                          ),
                        ],
                        Expanded(
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: barOpacity,
                              child: Text(
                                widget.title ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ),
                        ...widget.actions,
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// [PageScaffold.pinned] under [gap] (the top bar's room). Clear at the top of the page; once rows scroll under it,
/// it fills with the page's [color] so they pass behind it.
class _PinnedHeader extends SliverPersistentHeaderDelegate {
  const _PinnedHeader({required this.gap, required this.height, required this.color, required this.child});

  final double gap;
  final double height;
  final Color color;
  final Widget child;

  @override
  double get maxExtent => gap + height;

  @override
  double get minExtent => gap + height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => ColoredBox(
    color: color.withValues(alpha: (shrinkOffset / 24).clamp(0.0, 1.0)),
    child: Padding(
      padding: EdgeInsets.only(top: gap),
      child: child,
    ),
  );

  @override
  bool shouldRebuild(_PinnedHeader old) =>
      old.gap != gap || old.height != height || old.color != color || old.child != child;
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.onShowAll, this.compactSpacing = false, this.icon});

  final String title;
  final VoidCallback? onShowAll;
  final bool compactSpacing;

  /// Shown before the title while Settings › Section icons is on.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        shell.compact ? 16 : 24,
        compactSpacing ? 16 : 24,
        shell.compact ? 8 : 16,
        compactSpacing ? 10 : 4,
      ),
      child: Row(
        children: [
          if (icon != null && LayoutPrefs.instance.sectionIcons) ...[
            Icon(icon, size: 22, color: AppColors.textPrimary),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              title,
              style: (icon != null && LayoutPrefs.instance.sectionIcons ? text.titleLarge : text.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
            ),
          ),
          if (onShowAll != null)
            TextButton(
              onPressed: onShowAll,
              style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
              child: Text(tr.showAll),
            ),
        ],
      ),
    );
  }
}
