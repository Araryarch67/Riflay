import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../../services/language.dart';
import '../../platform/features.dart';
import '../../services/appearance.dart';
import '../../services/layout_prefs.dart';
import '../../models/track.dart';
import '../../services/player_controller.dart';
import '../debug_switches.dart';
import '../pages/search/search_input.dart';
import '../pages/search/soundcloud_results.dart' show SearchSourceButton;
import '../player/mini_player.dart';
import '../player/player_glass.dart';
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

List<_TabInfo> get _tabItems => <_TabInfo>[
  (tab: PhoneTab.home, icon: Icons.home_outlined, selected: Icons.home_rounded, label: tr.navHome),
  (
    tab: PhoneTab.library,
    icon: Icons.library_music_outlined,
    selected: Icons.library_music_rounded,
    label: tr.navLibrary,
  ),
  (tab: PhoneTab.search, icon: Icons.search_rounded, selected: Icons.manage_search_rounded, label: tr.navSearch),
  (tab: PhoneTab.downloads, icon: Icons.download_outlined, selected: Icons.download_rounded, label: tr.navDownloads),
  (tab: PhoneTab.settings, icon: Icons.settings_outlined, selected: Icons.settings_rounded, label: tr.navSettings),
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
/// - Liquid glass: the page blurring behind glass pills. The mini player sits on its own row above the tabs, with
///   Search as a round button beside them; scrolling down shrinks it all to one row (see [GlassBarLink]). On the
///   Search tab the search field moves into the bar, and while typing it rides on the keyboard.
class PhoneBottomBar extends StatelessWidget {
  const PhoneBottomBar({
    super.key,
    required this.onOpenPlayer,
    required this.tab,
    required this.onSelect,
    required this.link,
    this.showTabs = true,
  });

  final VoidCallback onOpenPlayer;
  final PhoneTab tab;
  final ValueChanged<PhoneTab> onSelect;
  final GlassBarLink link;

  /// Off when the tabs sit in [PhoneSideTabs] instead.
  final bool showTabs;

  /// Liquid glass: the round button the tabs shrink into, and the search field on the Search tab.
  static const tabsButtonKey = ValueKey('glass-tabs-button');
  static const searchFieldKey = ValueKey('glass-search-field');

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LayoutPrefs.instance,
    builder: (context, _) {
      final style = LayoutPrefs.instance.tabBar;
      final mini = MiniPlayer(onOpen: onOpenPlayer);
      // The search page leaves its box out while the bar carries it; told after this frame, as the page is not
      // below the bar.
      final inBar = showTabs && style == TabBarStyle.glass;
      if (link.searchInBar.value != inBar) {
        WidgetsBinding.instance.addPostFrameCallback((_) => link.searchInBar.value = inBar);
      }
      if (inBar) return _GlassBar(tab: tab, onSelect: onSelect, onOpenPlayer: onOpenPlayer, link: link);
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
                // As wide as a phone at most: the phone layout also serves a phone held sideways and a narrow
                // browser window, where a bar across the whole width looked stretched.
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: switch (style) {
                      TabBarStyle.dock => Center(
                        child: _DockBar(tab: tab, onSelect: onSelect),
                      ),
                      _ => _FloatingBar(style: style, tab: tab, onSelect: onSelect),
                    },
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// What the shell, the pages and the Liquid glass bar share: whether the bar is shrunk to one row, fed by the
/// pages' scrolling through [onScroll] (one listener around them all, so no page needs its own), and the search
/// field the bar carries on the Search tab ([search]; [searchInBar] tells the search page to leave out its own).
class GlassBarLink {
  final collapsed = ValueNotifier(false);
  final searchInBar = ValueNotifier(false);
  final search = SearchInput();

  /// How far the page has scrolled one way since it last turned.
  double _run = 0;

  /// Scrolling this far one way shrinks the bar (down) or grows it (up); within [_top] of the top it is always full.
  static const _turn = 24.0, _top = 8.0;

  bool onScroll(ScrollNotification n) {
    // The page's own list, not a shelf of covers across it or a list inside it.
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final m = n.metrics;
    if (DebugSwitches.noTabBarCollapse ||
        LayoutPrefs.instance.keepPhoneNavOpen ||
        m.pixels <= m.minScrollExtent + _top) {
      _run = 0;
      collapsed.value = false;
    } else if (n is ScrollUpdateNotification && m.pixels <= m.maxScrollExtent) {
      // Past the end (a bounce) counts neither way.
      final d = n.scrollDelta ?? 0;
      if (d == 0) return false;
      if (d.sign != _run.sign) _run = 0;
      _run += d;
      if (_run > _turn) collapsed.value = true;
      if (_run < -_turn) collapsed.value = false;
    }
    return false;
  }

  void dispose() {
    collapsed.dispose();
    searchInBar.dispose();
    search.dispose();
  }
}

/// Liquid glass (see [PhoneBottomBar]). Three animations drive one layout: [_collapse] (scrolled down: the tabs
/// shrink to a round button and the mini player joins their row), [_search] (the Search tab: the search button
/// grows into a field, the tabs shrink, a close button takes the corner) and [_typing] (the field focused: it
/// stays alone with the close button, on top of the keyboard).
class _GlassBar extends StatefulWidget {
  const _GlassBar({required this.tab, required this.onSelect, required this.onOpenPlayer, required this.link});

  final PhoneTab tab;
  final ValueChanged<PhoneTab> onSelect;
  final VoidCallback onOpenPlayer;
  final GlassBarLink link;

  @override
  State<_GlassBar> createState() => _GlassBarState();
}

class _GlassBarState extends State<_GlassBar> with TickerProviderStateMixin {
  /// A row's height, the round buttons' size, and the space between pills.
  static const _size = 58.0, _gap = 8.0;

  late final _collapse = _anim(_collapses);

  /// A song is in the player (playing or paused): its mini player joins the shrunk row. With none the bar shrank to
  /// two round buttons at its ends with nothing between them; it stays full then (`RIFLAY_TAB_BAR_COLLAPSE_IDLE`: as
  /// it was).
  bool _hasSong = false;
  bool _draggingLens = false;

  /// Scrolled down, with a song in the player.
  bool get _collapses =>
      widget.link.collapsed.value &&
      !LayoutPrefs.instance.keepPhoneNavOpen &&
      !DebugSwitches.noTabBarCollapse &&
      (_hasSong || DebugSwitches.tabBarCollapseIdle);

  late final _search = _anim(widget.tab == PhoneTab.search);
  late final _typing = _anim(false);

  /// The tab open before Search (where Close returns), and the one the round button shows when the bar shrinks.
  late PhoneTab _last = widget.tab == PhoneTab.search ? PhoneTab.home : widget.tab;

  SearchInput get _input => widget.link.search;

  AnimationController _anim(bool on) =>
      AnimationController(vsync: this, duration: const Duration(milliseconds: 340), value: on ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _listen(widget.link);
  }

  void _listen(GlassBarLink link) {
    link.collapsed.addListener(_follow);
    link.search.focus.addListener(_follow);
  }

  void _unlisten(GlassBarLink link) {
    link.collapsed.removeListener(_follow);
    link.search.focus.removeListener(_follow);
  }

  @override
  void didUpdateWidget(_GlassBar old) {
    super.didUpdateWidget(old);
    if (old.link != widget.link) {
      _unlisten(old.link);
      _listen(widget.link);
    }
    if (old.tab != widget.tab) {
      if (widget.tab != PhoneTab.search) _last = widget.tab;
      // Another tab opens at its top, with the bar full.
      widget.link.collapsed.value = false;
    }
    _follow();
  }

  @override
  void dispose() {
    _unlisten(widget.link);
    _collapse.dispose();
    _search.dispose();
    _typing.dispose();
    super.dispose();
  }

  void _follow() {
    final search = widget.tab == PhoneTab.search;
    _to(_collapse, _collapses);
    _to(_search, search);
    _to(_typing, search && _input.focus.hasFocus);
  }

  /// Animates [a] to on or off; without full motion it switches at once.
  void _to(AnimationController a, bool on) {
    final v = on ? 1.0 : 0.0;
    if (a.value == v && !a.isAnimating) return;
    if (LayoutPrefs.moves) {
      a.animateTo(v, curve: Curves.easeOutCubic);
    } else {
      a.value = v;
    }
  }

  /// The close button: leaves Search for the tab before it, the field emptied.
  void _close() {
    _input.controller.clear();
    _input.focus.unfocus();
    widget.onSelect(_last);
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return PlayerSelect<Track?>(
      select: (c) => c.currentTrack,
      builder: (context, track, _) {
        if ((track != null) != _hasSong) {
          _hasSong = track != null;
          // After this frame: the bar animates from where it is to the new rule.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _follow();
          });
        }
        return _bar(context, track, keyboard);
      },
    );
  }

  Widget _bar(BuildContext context, Track? track, double keyboard) {
    return AnimatedBuilder(
      animation: Listenable.merge([_collapse, _search, _typing]),
      builder: (context, _) {
        final typing = _typing.value;
        final mini = track != null && typing < 1;
        final height = mini ? _size * 2 + _gap : _size;
        return SafeArea(
          top: false,
          child: Padding(
            // While typing, the row rides on the keyboard (the scaffold leaves its bar under it).
            padding: EdgeInsets.fromLTRB(12, 0, 12, 10 + keyboard * typing),
            // As wide as a phone at most, as the other floating bars.
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SizedBox(
                  width: double.infinity,
                  height: height,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: LayoutBuilder(
                      builder: (context, box) =>
                          _layer(context, Stack(children: _parts(context, box.maxWidth, height, track))),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _parts(BuildContext context, double width, double height, Track? track) {
    final colors = AppColors.of(context);
    final search = _search.value, typing = _typing.value;
    // Search keeps the bar full: the field needs the room.
    final collapse = _collapse.value * (1 - search);
    final shrink = math.max(collapse, search);
    final row = height - _size;
    final side = _size + _gap;
    final full = width - side;
    final tabs = Rect.fromLTWH(0, row, lerpDouble(full, _size, shrink)!, _size);
    final corner = Rect.fromLTWH(width - _size, row, _size, _size);
    final field = Rect.fromLTWH(side, row, full, _size);
    final searchRect = Rect.lerp(corner, field, search)!;
    return [
      if (typing < 1)
        Positioned.fromRect(
          rect: tabs,
          child: _fade(
            1 - typing,
            IgnorePointer(ignoring: typing > 0.5, child: _tabsPill(colors, full, shrink, search)),
          ),
        ),
      // The tabs disappear at the end of the typing animation. Keep Search's subtree in place when its
      // position in this list changes, so its text input connection and keyboard survive the animation.
      Positioned.fromRect(
        key: const ValueKey('glass-search-pill'),
        rect: searchRect,
        child: _searchPill(colors, searchRect.width, field.width, search),
      ),
      if (search > 0 && typing > 0)
        Positioned.fromRect(
          rect: Rect.fromLTWH(0, row, _size, _size),
          child: _fade(
            typing * search,
            IgnorePointer(
              ignoring: typing < 0.5 || search < 0.5,
              child: _round(
                tooltip: tr.close,
                onTap: _close,
                child: Icon(Icons.arrow_back_rounded, color: _glassInk(colors), size: 26),
              ),
            ),
          ),
        ),
      if (track != null && typing < 1)
        Positioned.fromRect(
          rect: Rect.lerp(
            Rect.fromLTWH(0, 0, width, _size),
            Rect.fromLTWH(side, row, width - 2 * side, _size),
            collapse,
          )!,
          child: _fade(
            1 - typing,
            _glass(
              colors,
              GlassMiniPlayer(track: track, onOpen: widget.onOpenPlayer, compact: collapse),
              tint: LayoutPrefs.instance.miniGlassTint,
            ),
          ),
        ),
    ];
  }

  /// The tabs, laid out at their full width while the pill shrinks around them and they fade, and the round
  /// button's icon sliding from its tab's place to the button's middle: the open tab's, or on Search Home's.
  Widget _tabsPill(AppColorsView colors, double full, double shrink, double search) {
    final shown = [
      for (final i in _shownTabs)
        if (i.tab != PhoneTab.search) i,
    ];
    final round = widget.tab == PhoneTab.search ? PhoneTab.home : _last;
    // Every tab as wide as the others, its icon over its name, as Liquid glass tab bars are.
    int flex(_TabInfo i) => 1;
    final unit = (full - 8) / shown.fold(0, (n, i) => n + flex(i));
    var centre = 4.0;
    for (final i in shown) {
      if (i.tab == round) {
        centre += flex(i) * unit / 2;
        break;
      }
      centre += flex(i) * unit;
    }
    final last = _info(round);
    // The open tab's place in the full row: where the round button's glass starts from.
    final glassFrom = unit;
    return Stack(
      children: [
        Positioned.fill(child: IgnorePointer(child: _glass(colors, const SizedBox.expand()))),
        if (shrink < 1)
          Opacity(
            opacity: (1 - shrink * 2).clamp(0.0, 1.0),
            child: IgnorePointer(
              ignoring: shrink > 0.5,
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: full,
                maxWidth: full,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _DraggableGlassTabs(
                    tabs: shown,
                    tab: widget.tab,
                    renderer: _renderer,
                    // While the bar shrinks the round button's glass is the open tab's, moving: one drop of glass,
                    // not this one left behind (glass ignores the fade around it) and that one already there.
                    hideGlass: shrink > 0 && search <= 0.5,
                    onSelect: widget.onSelect,
                    onDragChanged: (dragging) {
                      if (mounted && dragging != _draggingLens) setState(() => _draggingLens = dragging);
                    },
                  ),
                ),
              ),
            ),
          ),
        if (shrink > 0)
          Positioned(
            left: lerpDouble(centre - glassFrom / 2, 0, shrink),
            top: 0,
            width: lerpDouble(glassFrom, _size, shrink),
            height: _size,
            child: Opacity(
              opacity: shrink,
              child: IgnorePointer(
                ignoring: shrink < 0.5,
                child: _TabButton(
                  key: PhoneBottomBar.tabsButtonKey,
                  info: last,
                  selected: widget.tab == round,
                  // Shrunk by scrolling it brings the tabs back; on Search it goes Home.
                  onTap: search > 0.5 ? () => widget.onSelect(round) : () => widget.link.collapsed.value = false,
                  // The open tab on its accent disc, as its capsule was; Home on Search is plain.
                  child: Center(
                    child: _GlassButtonFace(
                      renderer: _renderer,
                      active: search <= 0.5,
                      // The open tab's bubble (a tab wide, the row's height) growing round into the button.
                      child: SizedBox(
                        width: lerpDouble(glassFrom - 4, 44, shrink),
                        height: lerpDouble(_size - 8, 44, shrink),
                        child: Center(
                          child: _TabIcon(info: last, selected: true, color: _glassInk(colors)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Search: a round button that grows into the search field ([search] from 0 to 1), [fieldWidth] wide in the end.
  Widget _searchPill(AppColorsView colors, double width, double fieldWidth, double search) {
    final open = widget.tab == PhoneTab.search;
    const inset = 16.0 + 24 + 10;
    return _glass(
      colors,
      Stack(
        children: [
          if (search < 1)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: search > 0.5,
                child: Semantics(
                  button: true,
                  selected: open,
                  label: tr.navSearch,
                  excludeSemantics: true,
                  child: Tooltip(
                    message: tr.navSearch,
                    child: InkWell(
                      onTap: () {
                        widget.onSelect(PhoneTab.search);
                        // The shell must finish switching focus scopes before the field takes focus.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && widget.tab == PhoneTab.search) _input.focus.requestFocus();
                        });
                      },
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: lerpDouble((_size - 24) / 2, 16, search),
            top: 0,
            bottom: 0,
            child: IgnorePointer(child: Icon(Icons.search_rounded, size: 24, color: _glassInk(colors))),
          ),
          // Built as soon as Search opens, so "focus the search box" finds it before the field has grown.
          if (open)
            Positioned(
              key: const ValueKey('glass-search-input'),
              left: inset,
              top: 0,
              bottom: 0,
              width: math.max(0.0, width - inset),
              child: Opacity(
                opacity: search,
                child: IgnorePointer(
                  ignoring: search < 0.5,
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: fieldWidth - inset,
                    maxWidth: fieldWidth - inset,
                    child: _field(context, colors),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field(BuildContext context, AppColorsView colors) {
    final text = Theme.of(context).textTheme;
    final ink = _glassInk(colors);
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: PhoneBottomBar.searchFieldKey,
            controller: _input.controller,
            focusNode: _input.focus,
            textInputAction: TextInputAction.search,
            onSubmitted: _input.submit,
            style: text.bodyLarge?.copyWith(color: ink),
            cursorColor: ink,
            // The pill is the field: no fill or outline of the theme's, focused or not.
            decoration: InputDecoration(
              isCollapsed: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: tr.searchHint,
              hintStyle: text.bodyLarge?.copyWith(color: ink.withValues(alpha: 0.72)),
            ),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: _input.controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox(width: 8)
              : IconButton(
                  tooltip: tr.clear,
                  icon: const Icon(Icons.close_rounded),
                  color: ink,
                  onPressed: () {
                    _input.controller.clear();
                    _input.focus.requestFocus();
                  },
                ),
        ),
        SearchSourceButton(color: ink, onSelected: _input.selectSource),
        const SizedBox(width: 4),
      ],
    );
  }

  /// A round glass button.
  Widget _round({required String tooltip, required VoidCallback onTap, required Widget child}) => _glass(
    AppColors.of(context),
    Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          child: Center(child: child),
        ),
      ),
    ),
  );

  /// Whether the pills are drawn by liquid_glass_renderer, which refracts the page behind them and melts pills that
  /// touch into one (it falls back to its own frosted glass where the GPU path isn't there, as on the web).
  /// Lightweight draws the plain raised surface instead; `RIFLAY_NO_GLASS_RENDERER` Riflay's own blur.
  static bool get _renderer =>
      !LayoutPrefs.lightweight && !DebugSwitches.noGlassRenderer && ImageFilter.isShaderFilterSupported;

  /// The one layer every pill of the bar renders into, the pills melting together where they come closer than
  /// [_gap] (as the mini player passes over the tabs).
  Widget _layer(BuildContext context, Widget child) {
    if (!_renderer) return child;
    // Light frost and strong refraction ([riflayGlass]): where the shader runs (Impeller) the page bends behind the
    // pills; the frosted fallback (no shader filters) keeps the rim light and a tint so text stays legible.
    // Clear liquid glass ([riflayClearGlass]): the page sharp through it, bent and split into colours at the edges.
    final optics = riflayClearGlass(dragging: _draggingLens);
    return LiquidGlassLayer(
      settings: optics,
      child: LiquidGlassBlendGroup(blend: _gap - 2, child: child),
    );
  }

  /// [child] faded to [visibility]: the renderer's glass fades through its own scope, which [Opacity] doesn't reach.
  Widget _fade(double visibility, Widget child) => _renderer
      ? LiquidGlassVisibility(visibility: visibility, child: child)
      : Opacity(opacity: visibility, child: child);

  /// [child] on a glass pill.
  Widget _glass(AppColorsView colors, Widget child, {GlassTint? tint}) {
    final radius = math.min(LayoutPrefs.radius(_size / 2), _size / 2);
    if (_renderer) {
      return LiquidGlass.grouped(
        appearance: riflayClearGlassAppearance(themeIsLight: colors.light, tint: tint),
        shape: LiquidRoundedSuperellipse(borderRadius: radius),
        child: Material(type: MaterialType.transparency, child: child),
      );
    }
    final shape = _PillShape(radius);
    return LayoutPrefs.lightweight
        ? _SolidSurface(shape: shape, colors: colors, child: child)
        : _LiquidGlass(shape: shape, colors: colors, child: child);
  }
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
}) => _SwipeTabs(
  tabs: [for (final i in _shownTabs) i.tab],
  tab: tab,
  onSelect: onSelect,
  child: Material(
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
  ),
);

/// A finger sliding along the bar picks the tab under it as it goes, as on iOS: one light tick a tab. The tabs
/// count as equal widths here (the open one is wider on screen), so the tab under the finger doesn't jump as the
/// open one widens. `RIFLAY_NO_TAB_SWIPE` leaves only the taps.
class _SwipeTabs extends StatelessWidget {
  const _SwipeTabs({required this.tabs, required this.tab, required this.onSelect, required this.child});

  final List<PhoneTab> tabs;
  final PhoneTab tab;
  final ValueChanged<PhoneTab> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (DebugSwitches.noTabSwipe || tabs.length < 2) return child;
    return LayoutBuilder(
      builder: (context, box) {
        var current = tab;
        void at(Offset local) {
          if (box.maxWidth <= 0) return;
          final i = (local.dx / box.maxWidth * tabs.length).floor().clamp(0, tabs.length - 1);
          if (tabs[i] == current) return;
          current = tabs[i];
          HapticFeedback.selectionClick();
          onSelect(current);
        }

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (d) => current = tab,
          onHorizontalDragUpdate: (d) => at(d.localPosition),
          child: child,
        );
      },
    );
  }
}

/// The bar keeps the page stable during the scrub. Only the glass indicator
/// follows the pointer, and the tab opens once the gesture is committed.
class _DraggableGlassTabs extends StatefulWidget {
  const _DraggableGlassTabs({
    required this.tabs,
    required this.tab,
    required this.renderer,
    required this.onSelect,
    required this.onDragChanged,
    this.hideGlass = false,
  });

  final List<_TabInfo> tabs;
  final PhoneTab tab;
  final bool renderer;

  /// The open tab's glass is drawn elsewhere for now (the bar shrinking into its round button).
  final bool hideGlass;
  final ValueChanged<PhoneTab> onSelect;
  final ValueChanged<bool> onDragChanged;

  @override
  State<_DraggableGlassTabs> createState() => _DraggableGlassTabsState();
}

class _DraggableGlassTabsState extends State<_DraggableGlassTabs> {
  double? _finger;
  int? _target;
  bool _settling = false;
  Timer? _settleEnd;
  static const _snap = Duration(milliseconds: 160);

  /// The tab picked (tapped, or let go over) that the page hasn't switched to yet: the glass and the tab's colour go
  /// there at once, not after the new page has been built (a page taking a few frames left the glass on the old tab,
  /// then jumping).
  int? _picked;

  /// Where the glass settles to while [_settling]: the picked tab.
  int? _settleTo;

  @override
  void didUpdateWidget(_DraggableGlassTabs old) {
    super.didUpdateWidget(old);
    final now = widget.tabs.indexWhere((info) => info.tab == widget.tab);
    if (_picked != null && (now == _picked || old.tab != widget.tab)) _picked = null;
  }

  @override
  void dispose() {
    _settleEnd?.cancel();
    _forget?.cancel();
    super.dispose();
  }

  void _settle() {
    _settleEnd?.cancel();
    _settleEnd = Timer(_snap + const Duration(milliseconds: 32), () {
      if (mounted && _settling) setState(() => _settling = false);
    });
  }

  /// A tab that didn't open (it shows something over the page instead): the glass goes back to the page's tab.
  Timer? _forget;
  void _forgetPickLater(int index) {
    _forget?.cancel();
    _forget = Timer(const Duration(milliseconds: 800), () {
      if (mounted && _picked == index && widget.tabs[index].tab != widget.tab) setState(() => _picked = null);
    });
  }

  /// A tap: the glass slides from the tab shown to [index] (mounted where it was, then moved on the next frame, so it
  /// animates), and the tab opens.
  void _tap(int index, int shown) {
    final info = widget.tabs[index];
    if (index == shown || !LayoutPrefs.moves) {
      if (index != shown) {
        setState(() => _picked = index);
        _forgetPickLater(index);
      }
      widget.onSelect(info.tab);
      return;
    }
    setState(() {
      _picked = index;
      _settling = true;
      _settleTo = shown;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_settling) return;
      setState(() => _settleTo = index);
      _settle();
    });
    _forgetPickLater(index);
    widget.onSelect(info.tab);
  }

  void _update(double x, List<double> edges) {
    _settleEnd?.cancel();
    if (_finger == null) widget.onDragChanged(true);
    var index = 0;
    while (index < edges.length - 2 && x >= edges[index + 1]) {
      index++;
    }
    if (_target != index) HapticFeedback.selectionClick();
    setState(() {
      _finger = x;
      _target = index;
      _settling = false;
    });
  }

  void _finish({required bool commit}) {
    final target = _target;
    if (_finger == null) return;
    widget.onDragChanged(false);
    final opens = commit && target != null && target < widget.tabs.length && widget.tabs[target].tab != widget.tab;
    setState(() {
      _finger = null;
      _target = null;
      _settling = LayoutPrefs.moves;
      // Let go over another tab: the glass settles there, and stays there while its page is being built.
      if (opens) _picked = target;
      _settleTo = opens ? target : null;
    });
    if (_settling) _settle();
    if (opens) {
      _forgetPickLater(target);
      widget.onSelect(widget.tabs[target].tab);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final selected = widget.tabs.indexWhere((info) => info.tab == widget.tab);
      // What the glass and the tab's colour show: the tab picked, until the page catches up.
      final shown = _picked ?? selected;
      final unit = box.maxWidth / widget.tabs.length;
      final edges = <double>[0];
      for (var i = 0; i < widget.tabs.length; i++) {
        edges.add(edges.last + unit);
      }
      final finger = _finger;
      final moving = finger != null || _settling;
      final dragEnabled = !DebugSwitches.noTabSwipe && widget.tabs.length > 1;
      // The lens is a tab wide, swelling a little under the finger.
      final indicatorWidth = (unit * (finger != null ? 1.2 : 1.0)).clamp(40.0, math.max(40.0, box.maxWidth)).toDouble();
      final at = _settling ? (_settleTo ?? shown) : shown;
      final center = finger ?? (at < 0 ? indicatorWidth / 2 : (edges[at] + edges[at + 1]) / 2);
      final left = (center - indicatorWidth / 2).clamp(
        0.0,
        (box.maxWidth - indicatorWidth).clamp(0.0, double.infinity),
      );
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: !dragEnabled ? null : (details) => _update(details.localPosition.dx, edges),
        onHorizontalDragUpdate: !dragEnabled ? null : (details) => _update(details.localPosition.dx, edges),
        onHorizontalDragEnd: !dragEnabled ? null : (_) => _finish(commit: true),
        onHorizontalDragCancel: !dragEnabled ? null : () => _finish(commit: false),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            if (moving)
              AnimatedPositioned(
                duration: finger != null ? Duration.zero : _snap,
                curve: Curves.easeOutCubic,
                left: left,
                width: indicatorWidth,
                height: math.min(
                  box.maxHeight + (finger != null && !LayoutPrefs.lightweight ? 6 : 0),
                  box.maxHeight + 6,
                ),
                top: finger != null && !LayoutPrefs.lightweight ? -3 : 0,
                onEnd: () {
                  if (_settling && _finger == null) setState(() => _settling = false);
                },
                child: IgnorePointer(
                  child: _GlassButtonFace(
                    renderer: widget.renderer,
                    active: true,
                    child: CustomPaint(
                      foregroundPainter: LayoutPrefs.lightweight ? null : _GlassLensRim(active: finger != null),
                      child: const SizedBox.expand(key: ValueKey('glass-tab-drag-indicator')),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                for (final (i, info) in widget.tabs.indexed)
                  Expanded(
                    child: _TabButton(
                      info: info,
                      selected: i == selected,
                      onTap: () => _tap(i, shown),
                      child: AnimatedScale(
                        scale: finger != null && i == _target ? 1.12 : 1,
                        duration: LayoutPrefs.dur(const Duration(milliseconds: 115)),
                        child: _GlassTab(
                          info: info,
                          selected: i == shown,
                          renderer: widget.renderer,
                          paintGlass: !moving && !widget.hideGlass,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

/// The lens catches a thin split highlight on its edge, including on the Skia fallback.
class _GlassLensRim extends CustomPainter {
  const _GlassLensRim({required this.active});

  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).deflate(1);
    final edge = RRect.fromRectAndRadius(bounds, Radius.circular(bounds.height / 2));
    final strength = active ? 1.0 : 0.35;
    canvas.drawRRect(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF78F4ED).withValues(alpha: .8 * strength),
            Colors.white.withValues(alpha: .62 * strength),
            Colors.transparent,
            const Color(0xFFA98AFF).withValues(alpha: .65 * strength),
            const Color(0xFFFF8D79).withValues(alpha: .82 * strength),
          ],
          stops: const [0, .18, .52, .78, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_GlassLensRim oldDelegate) => oldDelegate.active != active;
}

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
              TabBarStyle.text when LayoutPrefs.instance.hidePhoneNavLabels => _IconAndDot(info: i, selected: selected),
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

/// How frosted the phone's glass is: about half the Appearance blur (or 10), so what is behind still reads; the
/// refraction ([riflayGlass]) carries the look.
double glassFrost() => (Appearance.instance.glass ? Appearance.instance.blur * 0.55 : 10.0).clamp(6.0, 20.0);

/// Floating and Capsule: a rounded bar on the raised surface, a soft shadow under it; on Liquid glass under a
/// Liquid preset's glass controls (Liquid Kawaii keeps its capsule).
class _FloatingBar extends StatelessWidget {
  const _FloatingBar({required this.style, required this.tab, required this.onSelect});

  final TabBarStyle style;
  final PhoneTab tab;
  final ValueChanged<PhoneTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final capsule = style == TabBarStyle.capsule;
    final radius = LayoutPrefs.corner(capsule ? 32 : 22);
    final bar = SizedBox(
      height: capsule ? 60 : 64,
      child: _tabRow(
        tab,
        onSelect,
        (i, selected) =>
            capsule ? _Capsule(info: i, selected: selected) : _IconOverLabel(info: i, selected: selected, pill: true),
        wideSelected: capsule,
      ),
    );
    if (LayoutPrefs.instance.playerGlassControls && !LayoutPrefs.lightweight) {
      final colors = AppColors.of(context);
      if (DebugSwitches.noGlassRenderer) {
        return _LiquidGlass(shape: _PillShape(radius.topLeft.x), colors: colors, child: bar);
      }
      return LiquidGlassLayer(
        settings: riflayGlass(brightness: colors.light ? Brightness.light : Brightness.dark, frost: glassFrost()),
        child: LiquidGlass(
          appearance: riflayGlassAppearance(themeIsLight: colors.light),
          shape: LiquidRoundedSuperellipse(borderRadius: radius.topLeft.x),
          child: Material(type: MaterialType.transparency, child: bar),
        ),
      );
    }
    return _RaisedSurface(radius: radius, child: bar);
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
  const _TabButton({super.key, required this.info, required this.selected, required this.onTap, required this.child});

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
        if (!LayoutPrefs.instance.hidePhoneNavLabels) ...[
          const SizedBox(height: 4),
          _TabLabel(info: info, selected: selected),
        ],
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
            if (!LayoutPrefs.instance.hidePhoneNavLabels) ...[
              const SizedBox(height: 4),
              _TabLabel(info: info, selected: selected),
            ],
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
Color _glassInk(AppColorsView colors) => switch (LayoutPrefs.instance.glassTint) {
  GlassTint.black => Colors.white,
  GlassTint.light => Colors.black,
  GlassTint.theme => colors.textPrimary,
};

class _GlassButtonFace extends StatelessWidget {
  const _GlassButtonFace({required this.renderer, required this.active, required this.child});
  final bool renderer, active;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    // The selection bubble: a drop of the accent inside the bar, so the open tab shows on clear, light or black
    // glass alike (a faint white one was lost on clear glass over a busy page).
    final colors = AppColors.of(context);
    final light = glassIsLight(colors.light);
    final bubble = colors.accent.withValues(alpha: light ? 0.26 : 0.32);
    if (!renderer) {
      return DecoratedBox(
        decoration: ShapeDecoration(shape: const StadiumBorder(), color: bubble),
        child: CustomPaint(
          foregroundPainter: _LiquidRim(const _StadiumShape(), light: light, strength: 0.7),
          child: child,
        ),
      );
    }
    return LiquidGlass(
      shape: const LiquidRoundedSuperellipse(borderRadius: 24),
      appearance: LiquidGlassAppearance.ios27Clear(tint: bubble),
      child: child,
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule({required this.info, required this.selected});

  final _TabInfo info;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final ink = colors.onAccent;
    return Center(
      child: AnimatedContainer(
        duration: LayoutPrefs.dur(const Duration(milliseconds: 220)),
        curve: Curves.easeOut,
        height: 40,
        padding: EdgeInsets.symmetric(horizontal: selected ? 10 : 0),
        decoration: BoxDecoration(
          color: selected ? colors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TabIcon(info: info, selected: selected, color: selected ? ink : colors.textSecondary),
            if (selected && !LayoutPrefs.instance.hidePhoneNavLabels) ...[
              const SizedBox(width: 6),
              Flexible(
                child: _TabLabel(info: info, selected: true, color: ink),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A Liquid glass tab: its icon over its name, the open one in the accent colour on a bubble of lighter glass.
class _GlassTab extends StatelessWidget {
  const _GlassTab({required this.info, required this.selected, required this.renderer, this.paintGlass = true});

  final _TabInfo info;
  final bool selected, renderer, paintGlass;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // The open tab sits on the accent bubble ([_GlassButtonFace]): its icon and name in the glass's full ink there,
    // the others a little softer.
    final ink = selected && paintGlass
        ? _glassInk(colors)
        : (selected ? colors.accent : _glassInk(colors).withValues(alpha: 0.78));
    final labels = !LayoutPrefs.instance.hidePhoneNavLabels;
    final face = SizedBox.expand(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TabIcon(info: info, selected: selected, color: ink),
          if (labels) ...[const SizedBox(height: 2), _TabLabel(info: info, selected: selected, color: ink)],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: paintGlass ? _GlassButtonFace(renderer: renderer, active: selected, child: face) : face,
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

/// Liquid glass. What scrolls behind is blurred and its colours lifted, then tinted with the theme's raised surface
/// (lighter at the top), edged with a rim that catches the light on top and fades towards the bottom. The shadow
/// is painted outside the clip, so it follows the shape.
class _LiquidGlass extends StatelessWidget {
  const _LiquidGlass({required this.shape, required this.colors, required this.child});

  final CustomClipper<Path> shape;
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

  /// How far in from the edge the glass bends what is behind it.
  static const _lens = 11.0;

  @override
  Widget build(BuildContext context) {
    final light = switch (LayoutPrefs.instance.glassTint) {
      GlassTint.black => false,
      GlassTint.light => true,
      _ => colors.light,
    };
    // Liquid glass without the shader: the page only lightly softened (and its colours kept), bent and magnified
    // in a band along the edge as a drop of glass bends it, edged with a rim that splits the light into colours,
    // and a glint where the light falls. A little shade keeps the labels readable over a busy page.
    return CustomPaint(
      painter: _GlassShadow(shape),
      child: RepaintBoundary(
        child: ClipPath(
          clipper: shape,
          child: LayoutBuilder(
            builder: (context, box) => Stack(
              fit: StackFit.expand,
              children: [
                BackdropFilter(
                  filter: ImageFilter.compose(outer: ImageFilter.blur(sigmaX: 1.2, sigmaY: 1.2), inner: _saturate(1.4)),
                  child: const SizedBox.expand(),
                ),
                // The bend, in steps that grow towards the edge (a smooth lens, not a ring): what is behind is
                // magnified about the middle, so near the rim it slides outward the most.
                for (final (depth, scale) in const [(_lens, 1.04), (_lens * 0.62, 1.08), (_lens * 0.3, 1.14)])
                  ClipPath(
                    clipper: _EdgeBand(shape, depth),
                    child: RawMagnifier(
                      size: box.biggest,
                      magnificationScale: scale,
                      decoration: const MagnifierDecoration(shadows: []),
                    ),
                  ),
                // One shade over all of it, so the bent edge and the middle read as one piece of glass.
                ColoredBox(
                  color: switch (LayoutPrefs.instance.glassTint) {
                    GlassTint.black => Colors.black.withValues(alpha: 0.72),
                    GlassTint.light => Colors.white.withValues(alpha: 0.45),
                    // A dark theme's glass is Black's.
                    GlassTint.theme =>
                      light ? Colors.white.withValues(alpha: 0.26) : Colors.black.withValues(alpha: 0.72),
                  },
                ),
                CustomPaint(painter: _LiquidRim(shape, light: light, strength: 0.7)),
                Material(type: MaterialType.transparency, child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The band along the inside of [shape], [width] deep: where liquid glass bends what is behind it.
class _EdgeBand extends CustomClipper<Path> {
  const _EdgeBand(this.shape, this.width);

  final CustomClipper<Path> shape;
  final double width;

  @override
  Path getClip(Size size) {
    final outer = shape.getClip(size);
    if (size.width <= width * 2 || size.height <= width * 2) return outer;
    final sx = (size.width - width * 2) / size.width, sy = (size.height - width * 2) / size.height;
    final inner = outer.transform(
      (Matrix4.identity()
            ..translateByDouble(width, width, 0, 1)
            ..scaleByDouble(sx, sy, 1, 1))
          .storage,
    );
    return Path.combine(PathOperation.difference, outer, inner);
  }

  @override
  bool shouldReclip(_EdgeBand old) => old.width != width || old.shape != shape;
}

/// A stadium (fully round ends) the size of what it is painted on.
class _StadiumShape extends CustomClipper<Path> {
  const _StadiumShape();

  @override
  Path getClip(Size size) =>
      Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.shortestSide / 2)));

  @override
  bool shouldReclip(_StadiumShape old) => false;
}

/// Liquid glass's light: a rim that splits into colours as it goes round, brightest where the light comes from
/// (top left), a glint there, and a little shade along the bottom inside.
class _LiquidRim extends CustomPainter {
  const _LiquidRim(this.shape, {required this.light, this.strength = 1});

  final CustomClipper<Path> shape;
  final bool light;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = shape.getClip(size);
    final rect = Offset.zero & size;
    // Shade low inside, so the glass reads as a body and not a flat film.
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: (light ? 0.06 : 0.16) * strength),
          ],
          stops: const [0.55, 1],
        ).createShader(rect),
    );
    // The glint: a soft spot of light near the top left.
    final glint = Rect.fromCenter(
      center: Offset(size.width * 0.18, size.height * 0.12),
      width: size.width * 0.5,
      height: size.height * 0.7,
    );
    canvas.drawOval(
      glint,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.22 * strength),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(glint),
    );
    canvas.restore();
    // The rim: a fine edge of light, only faintly cool on one side and warm on the other (a lens's dispersion,
    // kept quiet).
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = SweepGradient(
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.30 * strength),
            const Color(0xFFDDEEFF).withValues(alpha: 0.22 * strength),
            const Color(0xFFFFFFFF).withValues(alpha: 0.12 * strength),
            const Color(0xFFFFEEE6).withValues(alpha: 0.22 * strength),
            const Color(0xFFFFFFFF).withValues(alpha: 0.30 * strength),
          ],
        ).createShader(rect),
    );
    // ...and its highlight, bright at the top left and gone by the bottom right.
    canvas.drawPath(
      path.shift(const Offset(0.6, 0.6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.6 * strength),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.5],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_LiquidRim old) => old.light != light || old.strength != strength || old.shape != shape;
}

/// A bar without the glass: the theme's raised colour under a hairline, and the same shadow.
class _SolidSurface extends StatelessWidget {
  const _SolidSurface({required this.shape, required this.colors, required this.child});

  final CustomClipper<Path> shape;
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

  final CustomClipper<Path> shape;
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
  bool shouldRepaint(_Outline old) => old.color != color || _reshaped(old.shape, shape);
}

class _GlassShadow extends CustomPainter {
  const _GlassShadow(this.shape);

  final CustomClipper<Path> shape;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawShadow(shape.getClip(size), const Color(0x80000000), 6, true);

  @override
  bool shouldRepaint(_GlassShadow old) => _reshaped(old.shape, shape);
}

/// Whether [now] cuts a different outline than [old] did (a clipper only compares with its own kind).
bool _reshaped(CustomClipper<Path> old, CustomClipper<Path> now) =>
    old.runtimeType != now.runtimeType || now.shouldReclip(old);

/// A pill: a rectangle with ends as round as [radius] allows (a circle when square).
class _PillShape extends CustomClipper<Path> {
  const _PillShape(this.radius);

  final double radius;

  @override
  Path getClip(Size size) => Path()
    ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius.clamp(0, size.shortestSide / 2))));

  @override
  bool shouldReclip(_PillShape old) => old.radius != radius;
}
