import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../../services/language.dart';
import '../../platform/features.dart';
import '../../services/appearance.dart';
import '../../services/layout_prefs.dart';
import '../../models/track.dart';
import '../../services/player_controller.dart';
import '../debug_switches.dart';
import '../pages/search/search_input.dart';
import '../player/mini_player.dart';
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
/// - Centre button: Home raised in the middle, in a notch cut into a plain bar.
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
                      TabBarStyle.centre => _NotchBar(tab: tab, onSelect: onSelect),
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
    if (DebugSwitches.noTabBarCollapse || m.pixels <= m.minScrollExtent + _top) {
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

  late final _collapse = _anim(widget.link.collapsed.value && !DebugSwitches.noTabBarCollapse);
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
    _to(_collapse, widget.link.collapsed.value && !DebugSwitches.noTabBarCollapse);
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
      builder: (context, track, _) => AnimatedBuilder(
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
      ),
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
    final field = Rect.lerp(
      Rect.fromLTWH(side, row, width - 2 * side, _size),
      Rect.fromLTWH(0, row, full, _size),
      typing,
    )!;
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
      Positioned.fromRect(rect: searchRect, child: _searchPill(colors, searchRect.width, field.width, search)),
      if (search > 0)
        Positioned.fromRect(
          rect: corner,
          child: _fade(
            search,
            IgnorePointer(
              ignoring: search < 0.5,
              child: _round(
                tooltip: tr.close,
                onTap: _close,
                child: Icon(Icons.close_rounded, color: colors.textPrimary, size: 26),
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
            _glass(colors, GlassMiniPlayer(track: track, onOpen: widget.onOpenPlayer, compact: collapse)),
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
    // As in the Capsule style: the open tab widens into an accent capsule with its name, the others are icons,
    // which leaves the four tabs and Search room on a small phone.
    int flex(_TabInfo i) => widget.tab == i.tab ? 2 : 1;
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
    return _glass(
      colors,
      Stack(
        children: [
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
                    child: Row(
                      children: [
                        for (final i in shown)
                          Expanded(
                            flex: flex(i),
                            child: _TabButton(
                              info: i,
                              selected: widget.tab == i.tab,
                              onTap: () => widget.onSelect(i.tab),
                              child: _Capsule(info: i, selected: widget.tab == i.tab),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (shrink > 0)
            Positioned(
              left: lerpDouble(centre - _size / 2, 0, shrink),
              top: 0,
              width: _size,
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
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: search > 0.5 ? colors.accent.withValues(alpha: 0) : colors.accent,
                        ),
                        child: SizedBox.square(
                          dimension: 44,
                          child: Center(
                            child: _TabIcon(
                              info: last,
                              selected: true,
                              color: search > 0.5 ? colors.textPrimary : colors.onAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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
                        // Focus follows the field when it mounts, while the pill is still growing.
                        _input.focus.requestFocus();
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
            child: IgnorePointer(
              child: Icon(
                Icons.search_rounded,
                size: 24,
                color: search > 0.5 ? colors.textSecondary : colors.textPrimary,
              ),
            ),
          ),
          // Built as soon as Search opens, so "focus the search box" finds it before the field has grown.
          if (open)
            Positioned(
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
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: PhoneBottomBar.searchFieldKey,
            controller: _input.controller,
            focusNode: _input.focus,
            textInputAction: TextInputAction.search,
            onSubmitted: _input.submit,
            style: text.bodyLarge?.copyWith(color: colors.textPrimary),
            cursorColor: colors.accent,
            // The pill is the field: no fill or outline of the theme's, focused or not.
            decoration: InputDecoration(
              isCollapsed: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: tr.searchHint,
              hintStyle: text.bodyLarge?.copyWith(color: colors.textSecondary),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: _input.controller,
          builder: (context, _) => _input.controller.text.isEmpty
              ? const SizedBox(width: 12)
              : IconButton(
                  tooltip: tr.clear,
                  color: colors.textSecondary,
                  iconSize: 20,
                  onPressed: _input.controller.clear,
                  icon: const Icon(Icons.cancel_rounded),
                ),
        ),
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
  static bool get _renderer => !LayoutPrefs.lightweight && !DebugSwitches.noGlassRenderer;

  /// The one layer every pill of the bar renders into, the pills melting together where they come closer than
  /// [_gap] (as the mini player passes over the tabs).
  Widget _layer(BuildContext context, Widget child) {
    if (!_renderer) return child;
    // The preset's own frost (4.5) leans on refraction for the look; FakeGlass (Android, desktop) has none and
    // read almost clear. As frosted as the rest of the app's glass, and a little more tint to keep text legible.
    final blur = Appearance.instance.glass ? Appearance.instance.blur.clamp(18.0, 40.0) : 24.0;
    return LiquidGlassLayer(
      settings: LiquidGlassSettings.ios27Regular(
        brightness: AppColors.of(context).light ? Brightness.light : Brightness.dark,
        frost: blur,
        tintAmount: 0.4,
      ),
      child: LiquidGlassBlendGroup(blend: _gap - 2, child: child),
    );
  }

  /// [child] faded to [visibility]: the renderer's glass fades through its own scope, which [Opacity] doesn't reach.
  Widget _fade(double visibility, Widget child) => _renderer
      ? LiquidGlassVisibility(visibility: visibility, child: child)
      : Opacity(opacity: visibility, child: child);

  /// [child] on a glass pill.
  Widget _glass(AppColorsView colors, Widget child) {
    final radius = math.min(LayoutPrefs.radius(_size / 2), _size / 2);
    if (_renderer) {
      return LiquidGlass.grouped(
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

/// Centre button: Search raised in a notch in the middle of the bar, the other tabs as icons with a dot under the
/// selected one.
class _NotchBar extends StatelessWidget {
  const _NotchBar({required this.tab, required this.onSelect});

  final PhoneTab tab;
  final ValueChanged<PhoneTab> onSelect;

  static const _height = 60.0;

  /// The Search button's size, and how far it stands above the bar.
  static const _hub = 56.0;
  static const _rise = 34.0;

  static const _left = [PhoneTab.home, PhoneTab.library];
  static const _right = [PhoneTab.downloads, PhoneTab.settings];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final radius = LayoutPrefs.corner(28);
    final shape = _NotchedBar(radius: radius, hub: _hub, rise: _rise);
    Widget cell(PhoneTab t) => Expanded(
      child: _BarTab(info: _info(t), selected: tab == t, onTap: () => onSelect(t)),
    );
    // Each side takes half of what the Search button leaves, however many tabs it has (the web build has no Downloads).
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
        // Under the Search button: its dot, when Search is the tab shown.
        SizedBox(
          width: _hub + 24,
          child: Align(
            alignment: const Alignment(0, 0.62),
            child: _Dot(on: tab == PhoneTab.search),
          ),
        ),
        side(_right),
      ],
    );
    final surface = _SolidSurface(shape: shape, colors: colors, child: row);
    return SizedBox(
      height: _height + _rise,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(left: 0, right: 0, bottom: 0, height: _height, child: surface),
          Positioned(
            top: 0,
            child: _SearchHub(size: _hub, selected: tab == PhoneTab.search, onTap: () => onSelect(PhoneTab.search)),
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

/// Search: the round accent button standing in the bar's notch.
class _SearchHub extends StatelessWidget {
  const _SearchHub({required this.size, required this.selected, required this.onTap});

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
        message: tr.navSearch,
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
              child: Icon(
                selected ? Icons.manage_search_rounded : Icons.search_rounded,
                color: colors.onAccent,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
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

class _GlassFace extends CustomPainter {
  const _GlassFace(this.shape, this.tint, {required this.light});

  final CustomClipper<Path> shape;
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
  bool shouldRepaint(_GlassFace old) => old.tint != tint || old.light != light || _reshaped(old.shape, shape);
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

/// The bar's outline: a rounded rectangle with a smooth notch around the Search button.
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
