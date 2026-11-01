import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'page_motion.dart';
export 'page_motion.dart' show PageMotionStyle, PageMotionSpeed;

/// Desktop controls can stay full width or sit inside a floating player.
enum DesktopBarStyle {
  classic('Classic'),
  floating('Floating'),
  capsule('Capsule'),
  compact('Compact'),
  minimal('Minimal');

  const DesktopBarStyle(this.label);
  final String label;
}

/// The same visual language, adapted to a desktop wave or a phone cover border.
enum VisualizerStyle {
  wave('Wave'),
  bars('Bars'),
  line('Line'),
  dots('Dots'),
  mirror('Mirror'),
  twinWaves('Twin waves'),
  pulse('Pulse'),
  orbit('Orbit'),
  petals('Petals'),
  peaks('Peaks');

  const VisualizerStyle(this.label);
  final String label;
  bool get radial => this == pulse || this == orbit || this == petals;
}

/// How round the corners of covers, cards, menus and dialogs are.
enum CornerStyle {
  square('Square', 0),
  rounded('Rounded', 1),
  extraRound('Extra round', 2);

  const CornerStyle(this.label, this.scale);
  final String label;

  /// Multiplies every corner radius (1 is how the app has always looked).
  final double scale;
}

/// How tightly lists and grids are packed.
enum Density {
  comfortable('Comfortable'),
  compact('Compact');

  const Density(this.label);
  final String label;
}

/// How big the covers in shelves and grids are.
enum CoverSize {
  small('Small', 0.8),
  medium('Medium', 1),
  large('Large', 1.25);

  const CoverSize(this.label, this.scale);
  final String label;
  final double scale;
}

/// How much the app moves.
enum Motion {
  full('Full'),
  reduced('Reduced'),
  off('Off');

  const Motion(this.label);
  final String label;
}

enum ProgressBarStyle {
  thin('Thin', 4),
  thick('Thick', 9);

  const ProgressBarStyle(this.label, this.height);
  final String label;
  final double height;
}

enum PlayButtonShape {
  circle('Circle'),
  roundedSquare('Rounded square');

  const PlayButtonShape(this.label);
  final String label;
}

enum PhoneCoverSize {
  normal('Normal'),
  large('Large');

  const PhoneCoverSize(this.label);
  final String label;
}

enum LyricsSize {
  small('Small', 0.85),
  normal('Normal', 1),
  large('Large', 1.2),
  largest('Largest', 1.4);

  const LyricsSize(this.label, this.scale);
  final String label;
  final double scale;
}

enum LyricsAlign {
  left('Left'),
  centre('Centre');

  const LyricsAlign(this.label);
  final String label;
}

/// How the phone's tab bar looks. [docked] ones sit on the bottom edge; the others hover a little above it.
enum TabBarStyle {
  classic('Classic', docked: true),
  material('Material', docked: true),
  underline('Underline', docked: true),
  minimal('Minimal', docked: true),
  text('Text only', docked: true),
  floating('Floating'),
  capsule('Capsule'),
  dock('Dock'),
  centre('Centre button'),
  glass('Liquid glass');

  const TabBarStyle(this.label, {this.docked = false});
  final String label;
  final bool docked;
}

/// The sections of Home, in today's order.
enum HomeSection {
  quickPicks('Quick picks'),
  recentlyPlayed('Recently played'),
  playlists('Your playlists'),
  albums('Your albums'),
  artists('Artists'),
  discover('From YouTube Music'),
  recentlyAdded('Recently added');

  const HomeSection(this.label);
  final String label;
}

/// How the app is laid out: corners, density, cover sizes, Home's sections, the
/// player's details, lyrics and motion. One instance for the whole app
/// ([instance]), loaded before the first frame. The defaults are how the app
/// has always looked.
class LayoutPrefs extends ChangeNotifier {
  LayoutPrefs._();

  static final instance = LayoutPrefs._();

  static const _key = 'layout.v1';

  CornerStyle corners = CornerStyle.rounded;
  Density density = Density.comfortable;
  CoverSize coverSize = CoverSize.medium;

  /// Home's sections in the order shown, and the ones switched off.
  List<HomeSection> homeOrder = List.of(HomeSection.values);
  Set<HomeSection> homeHidden = {};

  ProgressBarStyle progressBar = ProgressBarStyle.thin;
  PlayButtonShape playButton = PlayButtonShape.circle;
  PhoneCoverSize phoneCover = PhoneCoverSize.normal;

  /// The phone's tab bar: docked under the mini player like most music apps, by default.
  TabBarStyle tabBar = TabBarStyle.capsule;
  DesktopBarStyle desktopBar = DesktopBarStyle.classic;
  bool showQualityBadge = true;
  bool visualizer = false;
  VisualizerStyle visualizerStyle = VisualizerStyle.wave;

  LyricsSize lyricsSize = LyricsSize.normal;
  LyricsAlign lyricsAlign = LyricsAlign.left;
  bool dimUnsungLyrics = true;

  Motion motion = Motion.full;
  PageMotionStyle pageMotion = PageMotionStyle.classic;
  PageMotionSpeed pageSpeed = PageMotionSpeed.balanced;

  // Shorthands for widgets. They read the one instance, like AppColors does.

  /// [base] (the radius the app has always used) for the chosen corners.
  static double radius(double base) => base * instance.corners.scale;
  static BorderRadius corner(double base) => BorderRadius.circular(radius(base));

  static bool get compact => instance.density == Density.compact;

  /// [comfortable] or [compact], by density.
  static double dense(double comfortable, double compact) => LayoutPrefs.compact ? compact : comfortable;

  /// What the motion setting comes to: "Full" gives way to "Reduced" when the
  /// system asks for less motion.
  static Motion get effectiveMotion {
    final m = instance.motion;
    if (m != Motion.full) return m;
    return PlatformDispatcher.instance.accessibilityFeatures.disableAnimations ? Motion.reduced : Motion.full;
  }

  /// [d] for full motion, shorter when reduced, none when off.
  static Duration dur(Duration d) => switch (effectiveMotion) {
    Motion.full => d,
    Motion.reduced => d ~/ 3,
    Motion.off => Duration.zero,
  };

  /// A chosen transition's duration; Reduced and Off always take precedence.
  static Duration pageDuration({bool reverse = false, bool player = false}) {
    final p = instance;
    final base = p.pageMotion == PageMotionStyle.classic
        ? (player ? (reverse ? 260 : 320) : (reverse ? 180 : 220))
        : (p.pageMotion == PageMotionStyle.circularReveal ||
              p.pageMotion == PageMotionStyle.diamondReveal ||
              p.pageMotion == PageMotionStyle.reveal ||
              p.pageMotion == PageMotionStyle.wipe)
        ? (reverse ? 480 : 620)
        : (reverse ? 340 : 440);
    return dur(Duration(milliseconds: (base * p.pageSpeed.factor).round()));
  }

  static Widget pageTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondary,
    Widget child, {
    bool player = false,
  }) => PageMotion.build(
    animation,
    secondary,
    child,
    style: instance.pageMotion,
    player: player,
    reduced: effectiveMotion == Motion.reduced || MediaQuery.disableAnimationsOf(context),
    disabled: effectiveMotion == Motion.off,
  );

  /// Sliding, scaling and bouncing; only with full motion. Fades stay otherwise.
  static bool get moves => effectiveMotion == Motion.full;

  Future<void> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      restore(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Layout settings unreadable, using defaults: $e');
    }
  }

  /// Reads saved settings; anything missing or unknown keeps its default.
  @visibleForTesting
  void restore(Map<String, dynamic> j) {
    final d = LayoutPrefs._();
    T pick<T extends Enum>(List<T> all, String key, T fallback) => all.asNameMap()[j[key]] ?? fallback;
    corners = pick(CornerStyle.values, 'corners', d.corners);
    density = pick(Density.values, 'density', d.density);
    coverSize = pick(CoverSize.values, 'coverSize', d.coverSize);
    progressBar = pick(ProgressBarStyle.values, 'progressBar', d.progressBar);
    playButton = pick(PlayButtonShape.values, 'playButton', d.playButton);
    phoneCover = pick(PhoneCoverSize.values, 'phoneCover', d.phoneCover);
    tabBar = pick(TabBarStyle.values, 'tabBar', d.tabBar);
    desktopBar = pick(DesktopBarStyle.values, 'desktopBar', d.desktopBar);
    showQualityBadge = j['showQualityBadge'] as bool? ?? d.showQualityBadge;
    visualizer = j['visualizer'] as bool? ?? d.visualizer;
    visualizerStyle = pick(VisualizerStyle.values, 'visualizerStyle', d.visualizerStyle);
    lyricsSize = pick(LyricsSize.values, 'lyricsSize', d.lyricsSize);
    lyricsAlign = pick(LyricsAlign.values, 'lyricsAlign', d.lyricsAlign);
    dimUnsungLyrics = j['dimUnsungLyrics'] as bool? ?? d.dimUnsungLyrics;
    motion = pick(Motion.values, 'motion', d.motion);
    pageMotion = pick(PageMotionStyle.values, 'pageMotion', d.pageMotion);
    pageSpeed = pick(PageMotionSpeed.values, 'pageSpeed', d.pageSpeed);
    final byName = HomeSection.values.asNameMap();
    final order = <HomeSection>[for (final n in (j['homeOrder'] as List?) ?? const []) ?byName[n]];
    // A section added by a newer version joins at its default place.
    for (final s in HomeSection.values) {
      if (!order.contains(s)) order.insert(order.length.clamp(0, s.index), s);
    }
    homeOrder = order.toSet().toList();
    homeHidden = {for (final n in (j['homeHidden'] as List?) ?? const []) ?byName[n]};
  }

  Map<String, dynamic> toJson() => {
    'corners': corners.name,
    'density': density.name,
    'coverSize': coverSize.name,
    'progressBar': progressBar.name,
    'playButton': playButton.name,
    'phoneCover': phoneCover.name,
    'tabBar': tabBar.name,
    'desktopBar': desktopBar.name,
    'showQualityBadge': showQualityBadge,
    'visualizer': visualizer,
    'visualizerStyle': visualizerStyle.name,
    'lyricsSize': lyricsSize.name,
    'lyricsAlign': lyricsAlign.name,
    'dimUnsungLyrics': dimUnsungLyrics,
    'motion': motion.name,
    'pageMotion': pageMotion.name,
    'pageSpeed': pageSpeed.name,
    'homeOrder': [for (final s in homeOrder) s.name],
    'homeHidden': [for (final s in homeHidden) s.name],
  };

  /// Whether anything differs from the defaults.
  bool get isCustomised => jsonEncode(toJson()) != jsonEncode(LayoutPrefs._().toJson());

  Future<void> _set(VoidCallback change) async {
    change();
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(toJson()));
    } catch (e) {
      debugPrint('Layout settings not saved: $e');
    }
  }

  Future<void> setCorners(CornerStyle v) => _set(() => corners = v);
  Future<void> setDensity(Density v) => _set(() => density = v);
  Future<void> setCoverSize(CoverSize v) => _set(() => coverSize = v);
  Future<void> setProgressBar(ProgressBarStyle v) => _set(() => progressBar = v);
  Future<void> setPlayButton(PlayButtonShape v) => _set(() => playButton = v);
  Future<void> setPhoneCover(PhoneCoverSize v) => _set(() => phoneCover = v);
  Future<void> setDesktopBar(DesktopBarStyle v) => _set(() => desktopBar = v);
  Future<void> setTabBar(TabBarStyle v) => _set(() => tabBar = v);
  Future<void> setVisualizerStyle(VisualizerStyle v) => _set(() => visualizerStyle = v);
  Future<void> setVisualizer(bool v) => _set(() => visualizer = v);
  Future<void> setShowQualityBadge(bool v) => _set(() => showQualityBadge = v);
  Future<void> setLyricsSize(LyricsSize v) => _set(() => lyricsSize = v);
  Future<void> setLyricsAlign(LyricsAlign v) => _set(() => lyricsAlign = v);
  Future<void> setDimUnsungLyrics(bool v) => _set(() => dimUnsungLyrics = v);
  Future<void> setPageMotion(PageMotionStyle v) => _set(() => pageMotion = v);
  Future<void> setPageSpeed(PageMotionSpeed v) => _set(() => pageSpeed = v);
  Future<void> setMotion(Motion v) => _set(() => motion = v);

  Future<void> setHomeSectionShown(HomeSection s, bool shown) =>
      _set(() => shown ? homeHidden.remove(s) : homeHidden.add(s));

  /// Moves a section to [newIndex], counted after it is taken out (a [ReorderableListView]'s onReorderItem).
  Future<void> moveHomeSection(int oldIndex, int newIndex) => _set(() {
    homeOrder.insert(newIndex, homeOrder.removeAt(oldIndex));
  });

  /// Home's sections that are switched on, in order.
  List<HomeSection> get homeShown => [
    for (final s in homeOrder)
      if (!homeHidden.contains(s)) s,
  ];

  Future<void> reset() => _set(() => restore(const {}));

  /// [base] with the corner and motion settings applied to menus, dialogs,
  /// buttons and page transitions. Unchanged for the defaults.
  ThemeData themed(ThemeData base) {
    final corner = corners;
    final motionNow = effectiveMotion;
    if (corner == CornerStyle.rounded &&
        motionNow == Motion.full &&
        pageMotion == PageMotionStyle.classic &&
        pageSpeed == PageMotionSpeed.balanced) {
      return base;
    }
    var t = base;
    if (corner != CornerStyle.rounded) {
      final s = corner.scale;
      RoundedRectangleBorder shape(double r, [BorderSide side = BorderSide.none]) =>
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(r * s), side: side);
      final menuSide = base.popupMenuTheme.shape is RoundedRectangleBorder
          ? (base.popupMenuTheme.shape! as RoundedRectangleBorder).side
          : BorderSide.none;
      final snackSide = base.snackBarTheme.shape is RoundedRectangleBorder
          ? (base.snackBarTheme.shape! as RoundedRectangleBorder).side
          : BorderSide.none;
      // Buttons are pills today; only square corners change them.
      final buttonShape = corner == CornerStyle.square ? const RoundedRectangleBorder() : null;
      t = t.copyWith(
        popupMenuTheme: base.popupMenuTheme.copyWith(shape: shape(12, menuSide)),
        snackBarTheme: base.snackBarTheme.copyWith(shape: shape(10, snackSide)),
        dialogTheme: base.dialogTheme.copyWith(shape: shape(28)),
        bottomSheetTheme: base.bottomSheetTheme.copyWith(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28 * s))),
        ),
        filledButtonTheme: buttonShape == null
            ? null
            : FilledButtonThemeData(
                style: (base.filledButtonTheme.style ?? FilledButton.styleFrom()).copyWith(
                  shape: WidgetStatePropertyAll(buttonShape),
                ),
              ),
        outlinedButtonTheme: buttonShape == null
            ? null
            : OutlinedButtonThemeData(
                style: (base.outlinedButtonTheme.style ?? OutlinedButton.styleFrom()).copyWith(
                  shape: WidgetStatePropertyAll(buttonShape),
                ),
              ),
        textButtonTheme: buttonShape == null
            ? null
            : TextButtonThemeData(
                style: (base.textButtonTheme.style ?? TextButton.styleFrom()).copyWith(
                  shape: WidgetStatePropertyAll(buttonShape),
                ),
              ),
        chipTheme: corner == CornerStyle.square ? base.chipTheme.copyWith(shape: const RoundedRectangleBorder()) : null,
      );
    }
    if (motionNow != Motion.full || pageMotion != PageMotionStyle.classic || pageSpeed != PageMotionSpeed.balanced) {
      final builder = PresetPageTransitions(
        style: pageMotion,
        duration: pageDuration(),
        reduced: motionNow == Motion.reduced,
        disabled: motionNow == Motion.off,
      );
      t = t.copyWith(
        splashFactory: motionNow == Motion.off ? NoSplash.splashFactory : base.splashFactory,
        pageTransitionsTheme: PageTransitionsTheme(builders: {for (final p in TargetPlatform.values) p: builder}),
      );
    }
    return t;
  }
}
