import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/features.dart';
import 'page_motion.dart';
export 'page_motion.dart' show PageMotionStyle, PageMotionSpeed;

/// Desktop controls can stay full width or sit inside a floating player.
/// The desktop's player bar. Every look sits flush along the window's foot; none floats over the page.
enum DesktopBarStyle {
  classic('Classic'),
  compact('Compact'),
  minimal('Minimal');

  const DesktopBarStyle(this.label);
  final String label;
}

/// The same visual language in a player strip or a radial artwork surround.
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

/// The outline of a player cover (what [PlayerCover] comes to when the cover is not the background).
enum VisualizerCoverShape {
  flower('Flower'),
  square('Square');

  const VisualizerCoverShape(this.label);
  final String label;
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

/// How music videos are decoded (mpv's `hwdec`). A setting of this computer, like [PerformanceMode]:
/// Reset leaves it alone.
enum VideoDecoder {
  automatic('Automatic', 'The graphics card when it is known to work, else the processor', 'auto-safe'),
  hardware('Graphics card', 'Always try the graphics card first. Lightest, if your drivers cope', 'auto'),
  software('Processor', 'Never the graphics card. Uses more power; try it if videos look wrong', 'no');

  const VideoDecoder(this.label, this.note, this.hwdec);
  final String label;
  final String note;

  /// mpv's `hwdec` value.
  final String hwdec;
}

/// How much the app spends on looks. [lightweight] caps the user's own Look & feel choices
/// (it never overwrites them); [heavy] lifts the frame-rate limits on decorations.
enum PerformanceMode {
  lightweight('Lightweight', 'Fewest effects. Best for older computers and battery.'),
  balanced('Balanced', 'Smooth animations with sensible limits.'),
  heavy('Heavy', 'Every effect at full speed. Uses more power.');

  const PerformanceMode(this.label, this.note);
  final String label;
  final String note;
}

enum ProgressBarStyle {
  thin('Thin', 4),
  thick('Thick', 9);

  const ProgressBarStyle(this.label, this.height);
  final String label;
  final double height;
}

enum ProgressBarShape {
  straight('Straight'),
  wavy('Wavy'),

  /// A thick rounded track with a pill of elapsed time and a bar for a thumb (the phone's player and the desktop bar).
  pill('Pill'),

  /// A flat 4 px track with round ends and no handle until it is dragged (the phone's player and the desktop bar).
  thin('Thin line');

  const ProgressBarShape(this.label);
  final String label;
}

enum PlayButtonShape {
  circle('Circle'),
  roundedSquare('Rounded square'),
  flower('Flower');

  const PlayButtonShape(this.label);
  final String label;
}

enum PhoneCoverSize {
  normal('Normal'),
  large('Large');

  const PhoneCoverSize(this.label);
  final String label;
}

/// The shape of the player's cover, on phones and desktop alike: a rounded square, a flower, or no frame at all
/// ([background]: the artwork fills the top of the page and fades into it).
enum PlayerCover {
  square('Square'),
  flower('Flower'),
  background('Background');

  const PlayerCover(this.label);
  final String label;
}

/// The top of Now Playing.
enum PlayerHeader {
  classic('Classic'),
  centered('Centred'),
  playingFrom('Playing from');

  const PlayerHeader(this.label);
  final String label;
}

/// The buttons beside the song's title.
enum TitleActions {
  classic('Classic'),
  boxed('Boxed'),
  plain('Plain');

  const TitleActions(this.label);
  final String label;
}

/// The previous / play / next controls.
enum PlayerTransport {
  classic('Classic'),
  pill('Pill'),
  plain('Plain');

  const PlayerTransport(this.label);
  final String label;
}

/// The row of buttons under the controls. Every one keeps a Lyrics button. [minimal] is icons only: Lyrics, a capsule
/// with the volume and the output / listen-together buttons, and Queue.
enum PlayerBottomRow {
  classic('Classic'),
  chips('Chips'),
  minimal('Icons');

  const PlayerBottomRow(this.label);
  final String label;
}

/// The lyrics page: its header and the player under the lyrics (on desktop a song card on top or at the bottom).
enum LyricsLayout {
  classic('Classic'),
  bottomCard('Bottom card'),
  topHeader('Top header');

  const LyricsLayout(this.label);
  final String label;
}

/// The phone's mini player above the tab bar: the bar as it has always been, or a floating pill with a flower cover,
/// round translucent previous / next and a round accent play button.
enum MiniPlayerStyle {
  classic('Classic'),
  capsule('Floating pill');

  const MiniPlayerStyle(this.label);
  final String label;
}

/// The header of an album or playlist page.
enum AlbumHeaderStyle {
  classic('Classic'),
  hero('Hero');

  const AlbumHeaderStyle(this.label);
  final String label;
}

/// The look of every slider in the app (Settings › Layout › Slider look); the progress bar has its own shape.
enum VolumeSliderShape {
  classic('Classic'),
  thin('Thin line'),
  pill('Pill');

  const VolumeSliderShape(this.label);
  final String label;
}

/// Where the sound-quality badge (FLAC, Opus 130 kbps...) sits on the phone's player.
enum QualityBadgePlace {
  underArtist('Under the artist'),
  timeRow('In the time row');

  const QualityBadgePlace(this.label);
  final String label;
}

/// How the song that is playing stands out in a list of songs.
enum PlayingRowStyle {
  classic('Classic'),
  card('Highlighted card');

  const PlayingRowStyle(this.label);
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

/// How many lyric lines are shown at once.
enum LyricsLines {
  all('All'),

  /// The previous, the current and the next line, far apart.
  focused('Focused');

  const LyricsLines(this.label);
  final String label;
}

/// How timed lyrics light up.
enum LyricsSync {
  /// Word by word where the lyrics have word timings (else line by line).
  word('Word by word'),

  /// The whole current line at once, even where the lyrics have word timings.
  line('Line by line');

  const LyricsSync(this.label);
  final String label;
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
/// ([instance]), loaded before the first frame. Fresh installs and Reset share
/// the same defaults.
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
  ProgressBarShape progressShape = ProgressBarShape.wavy;
  PlayButtonShape playButton = PlayButtonShape.circle;
  PhoneCoverSize phoneCover = PhoneCoverSize.normal;

  /// The player, part by part, on phones and desktop. The defaults are how it has always looked; Settings › Look & feel ›
  /// Layout › Player changes them one by one, and Presets sets several at once.
  PlayerCover playerCover = PlayerCover.flower;
  PlayerHeader playerHeader = PlayerHeader.classic;
  TitleActions titleActions = TitleActions.classic;
  bool showTimeLeft = false;
  PlayerTransport transport = PlayerTransport.classic;
  bool showVolumeRow = true;
  PlayerBottomRow bottomRow = PlayerBottomRow.classic;
  LyricsLayout lyricsLayout = LyricsLayout.classic;
  MiniPlayerStyle miniPlayer = MiniPlayerStyle.classic;
  AlbumHeaderStyle albumHeader = AlbumHeaderStyle.classic;
  PlayingRowStyle playingRow = PlayingRowStyle.classic;
  QualityBadgePlace qualityBadgePlace = QualityBadgePlace.underArtist;
  VolumeSliderShape volumeSlider = VolumeSliderShape.classic;

  /// The phone's tab bar: docked under the mini player like most music apps, by default.
  TabBarStyle tabBar = TabBarStyle.capsule;
  DesktopBarStyle desktopBar = DesktopBarStyle.classic;
  bool showQualityBadge = true;

  /// The Song / Video switch at the top of Now Playing, for a song with a music video. On in every preset.
  bool showVideoSwitch = true;
  bool visualizer = true;
  bool get visualizerEnabled => visualizer && Features.audioVisualizer;

  /// The outline of the cover (and of what the visualizer pulses around): Square is the rounded square, anything else
  /// the flower. It is the Cover setting of the Player group, not a setting of its own.
  VisualizerCoverShape get visualizerCoverShape =>
      playerCover == PlayerCover.square ? VisualizerCoverShape.square : VisualizerCoverShape.flower;
  VisualizerStyle visualizerStyle = VisualizerStyle.pulse;
  double visualizerRadius = 1.6;
  double visualizerThickness = 3;

  LyricsSize lyricsSize = LyricsSize.normal;
  LyricsAlign lyricsAlign = LyricsAlign.left;
  bool dimUnsungLyrics = true;
  LyricsLines lyricsLines = LyricsLines.all;
  LyricsSync lyricsSync = LyricsSync.word;

  /// Desktop: the library sidebar and the now-playing side panel, as dragged. Today's widths by default;
  /// the shell narrows them when the window is too small to give the pages their room.
  static const sidebarDefault = 300.0;
  static const sidebarMin = 200.0;
  static const sidebarMax = 420.0;
  static const sidePanelDefault = 332.0;
  static const sidePanelMin = 260.0;
  static const sidePanelMax = 520.0;
  double sidebarWidth = sidebarDefault;
  double sidePanelWidth = sidePanelDefault;

  Motion motion = Motion.full;

  /// Classic by default: the reveals felt like too much to many as the first thing they saw.
  PageMotionStyle pageMotion = PageMotionStyle.classic;
  PageMotionSpeed pageSpeed = PageMotionSpeed.relaxed;
  PerformanceMode performance = PerformanceMode.balanced;
  VideoDecoder videoDecoder = VideoDecoder.automatic;

  /// Desktop: minimize, maximize and close in the title bar. Off for tiling window managers, which place and
  /// close windows themselves. A setting of this computer, like [performance].
  bool windowButtons = true;

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
    if (lightweight) return Motion.off;
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

  /// The phone player's parts are all as they have always been (Classic keeps its original layout).
  bool get classicPlayerFace =>
      playerCover != PlayerCover.background &&
      playerHeader == PlayerHeader.classic &&
      titleActions == TitleActions.classic &&
      transport == PlayerTransport.classic &&
      bottomRow == PlayerBottomRow.classic &&
      qualityBadgePlace == QualityBadgePlace.underArtist &&
      volumeSlider == VolumeSliderShape.classic &&
      showVolumeRow;

  /// Performance mode: Lightweight turns off every effect that isn't needed to use the app.
  static bool get lightweight => instance.performance == PerformanceMode.lightweight;

  /// Performance mode: Heavy runs decorations and the seek bar at the display's full rate.
  static bool get heavy => instance.performance == PerformanceMode.heavy;

  /// Sliding, scaling and bouncing; only with full motion. Fades stay otherwise.
  static bool get moves => effectiveMotion == Motion.full;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      // The visualizer used to be a Beta feature with a switch of its own, and was only on with both: a save from
      // then keeps it on only if that switch was.
      if (j['visualizerStable'] != true && j['visualizer'] == true) {
        final optedIn = prefs.getBool('features.audioVisualizer') ?? prefs.getBool('beta.audioVisualizer') ?? false;
        if (!optedIn) j['visualizer'] = false;
      }
      restore(j);
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
    progressShape = pick(ProgressBarShape.values, 'progressShape', d.progressShape);
    playButton = pick(PlayButtonShape.values, 'playButton', d.playButton);
    phoneCover = pick(PhoneCoverSize.values, 'phoneCover', d.phoneCover);
    // Older versions had a card or a full-width cover, and a separate flower / square setting for the card.
    final legacyShape = j['visualizerCoverShape'] == 'square' ? PlayerCover.square : PlayerCover.flower;
    playerCover = switch (j['playerCover']) {
      'fullBleed' => PlayerCover.background,
      'card' => legacyShape,
      final name => PlayerCover.values.asNameMap()[name] ?? legacyShape,
    };
    playerHeader = pick(PlayerHeader.values, 'playerHeader', d.playerHeader);
    titleActions = pick(TitleActions.values, 'titleActions', d.titleActions);
    showTimeLeft = j['showTimeLeft'] as bool? ?? d.showTimeLeft;
    transport = pick(PlayerTransport.values, 'transport', d.transport);
    showVolumeRow = j['showVolumeRow'] as bool? ?? d.showVolumeRow;
    bottomRow = pick(PlayerBottomRow.values, 'bottomRow', d.bottomRow);
    lyricsLayout = pick(LyricsLayout.values, 'lyricsLayout', d.lyricsLayout);
    miniPlayer = pick(MiniPlayerStyle.values, 'miniPlayer', d.miniPlayer);
    albumHeader = pick(AlbumHeaderStyle.values, 'albumHeader', d.albumHeader);
    playingRow = pick(PlayingRowStyle.values, 'playingRow', d.playingRow);
    qualityBadgePlace = pick(QualityBadgePlace.values, 'qualityBadgePlace', d.qualityBadgePlace);
    volumeSlider = pick(VolumeSliderShape.values, 'volumeSlider', d.volumeSlider);
    tabBar = pick(TabBarStyle.values, 'tabBar', d.tabBar);
    // The floating looks are gone: Floating became Classic, Capsule (a one-row floating dock) Compact.
    desktopBar = switch (j['desktopBar']) {
      'floating' => DesktopBarStyle.classic,
      'capsule' => DesktopBarStyle.compact,
      _ => pick(DesktopBarStyle.values, 'desktopBar', d.desktopBar),
    };
    showQualityBadge = j['showQualityBadge'] as bool? ?? d.showQualityBadge;
    showVideoSwitch = j['showVideoSwitch'] as bool? ?? d.showVideoSwitch;
    visualizer = j['visualizer'] as bool? ?? d.visualizer;
    visualizerStyle = j['visualizerVersion'] == 3
        ? pick(VisualizerStyle.values, 'visualizerStyle', d.visualizerStyle)
        : VisualizerStyle.pulse;
    visualizerRadius = (j['visualizerRadius'] as num?)?.toDouble().clamp(0.5, 2.5) ?? d.visualizerRadius;
    visualizerThickness = (j['visualizerThickness'] as num?)?.toDouble().clamp(1, 8) ?? d.visualizerThickness;
    lyricsSize = pick(LyricsSize.values, 'lyricsSize', d.lyricsSize);
    lyricsAlign = pick(LyricsAlign.values, 'lyricsAlign', d.lyricsAlign);
    dimUnsungLyrics = j['dimUnsungLyrics'] as bool? ?? d.dimUnsungLyrics;
    lyricsLines = pick(LyricsLines.values, 'lyricsLines', d.lyricsLines);
    lyricsSync = pick(LyricsSync.values, 'lyricsSync', d.lyricsSync);
    sidebarWidth = (j['sidebarWidth'] as num?)?.toDouble().clamp(sidebarMin, sidebarMax) ?? d.sidebarWidth;
    sidePanelWidth = (j['sidePanelWidth'] as num?)?.toDouble().clamp(sidePanelMin, sidePanelMax) ?? d.sidePanelWidth;
    motion = pick(Motion.values, 'motion', d.motion);
    // Side reveal was the default until 1.1.3, and every save holds it: those saves start on Classic, the new
    // default. A choice made since is kept (`pageMotionVersion`).
    pageMotion = j['pageMotionVersion'] == null && j['pageMotion'] == PageMotionStyle.wipe.name
        ? PageMotionStyle.classic
        : pick(PageMotionStyle.values, 'pageMotion', d.pageMotion);
    pageSpeed = pick(PageMotionSpeed.values, 'pageSpeed', d.pageSpeed);
    performance = pick(PerformanceMode.values, 'performance', d.performance);
    videoDecoder = pick(VideoDecoder.values, 'videoDecoder', d.videoDecoder);
    windowButtons = j['windowButtons'] as bool? ?? d.windowButtons;
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
    'progressShape': progressShape.name,
    'playButton': playButton.name,
    'phoneCover': phoneCover.name,
    'playerCover': playerCover.name,
    'playerHeader': playerHeader.name,
    'titleActions': titleActions.name,
    'showTimeLeft': showTimeLeft,
    'transport': transport.name,
    'showVolumeRow': showVolumeRow,
    'bottomRow': bottomRow.name,
    'lyricsLayout': lyricsLayout.name,
    'miniPlayer': miniPlayer.name,
    'albumHeader': albumHeader.name,
    'playingRow': playingRow.name,
    'qualityBadgePlace': qualityBadgePlace.name,
    'volumeSlider': volumeSlider.name,
    'tabBar': tabBar.name,
    'desktopBar': desktopBar.name,
    'showQualityBadge': showQualityBadge,
    'showVideoSwitch': showVideoSwitch,
    'visualizer': visualizer,
    'visualizerStyle': visualizerStyle.name,
    'visualizerVersion': 3,
    'visualizerStable': true,
    'visualizerRadius': visualizerRadius,
    'visualizerThickness': visualizerThickness,
    'lyricsSize': lyricsSize.name,
    'lyricsAlign': lyricsAlign.name,
    'dimUnsungLyrics': dimUnsungLyrics,
    'lyricsLines': lyricsLines.name,
    'lyricsSync': lyricsSync.name,
    'sidebarWidth': sidebarWidth,
    'sidePanelWidth': sidePanelWidth,
    'motion': motion.name,
    'pageMotion': pageMotion.name,
    'pageMotionVersion': 2,
    'pageSpeed': pageSpeed.name,
    'performance': performance.name,
    'videoDecoder': videoDecoder.name,
    'windowButtons': windowButtons,
    'homeOrder': [for (final s in homeOrder) s.name],
    'homeHidden': [for (final s in homeHidden) s.name],
  };

  /// Whether anything differs from the defaults (Performance, the video decoder and the window buttons are
  /// about this computer, so they don't count).
  bool get isCustomised =>
      jsonEncode(toJson()) !=
      jsonEncode(
        (LayoutPrefs._()
              ..performance = performance
              ..videoDecoder = videoDecoder
              ..windowButtons = windowButtons)
            .toJson(),
      );

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
  Future<void> setProgressShape(ProgressBarShape v) => _set(() => progressShape = v);
  Future<void> setPlayButton(PlayButtonShape v) => _set(() => playButton = v);
  Future<void> setPhoneCover(PhoneCoverSize v) => _set(() => phoneCover = v);
  Future<void> setPlayerCover(PlayerCover v) => _set(() => playerCover = v);
  Future<void> setPlayerHeader(PlayerHeader v) => _set(() => playerHeader = v);
  Future<void> setTitleActions(TitleActions v) => _set(() => titleActions = v);
  Future<void> setShowTimeLeft(bool v) => _set(() => showTimeLeft = v);
  Future<void> setTransport(PlayerTransport v) => _set(() => transport = v);
  Future<void> setShowVolumeRow(bool v) => _set(() => showVolumeRow = v);
  Future<void> setBottomRow(PlayerBottomRow v) => _set(() => bottomRow = v);
  Future<void> setLyricsLayout(LyricsLayout v) => _set(() => lyricsLayout = v);
  Future<void> setMiniPlayer(MiniPlayerStyle v) => _set(() => miniPlayer = v);
  Future<void> setAlbumHeader(AlbumHeaderStyle v) => _set(() => albumHeader = v);
  Future<void> setPlayingRow(PlayingRowStyle v) => _set(() => playingRow = v);
  Future<void> setQualityBadgePlace(QualityBadgePlace v) => _set(() => qualityBadgePlace = v);
  Future<void> setVolumeSlider(VolumeSliderShape v) => _set(() => volumeSlider = v);

  /// Several settings at once (a preset): one notify, one save.
  Future<void> change(VoidCallback changes) => _set(changes);
  Future<void> setDesktopBar(DesktopBarStyle v) => _set(() => desktopBar = v);
  Future<void> setTabBar(TabBarStyle v) => _set(() => tabBar = v);
  Future<void> setVisualizerStyle(VisualizerStyle v) => _set(() => visualizerStyle = v);
  Future<void> setVisualizerCoverShape(VisualizerCoverShape v) =>
      _set(() => playerCover = v == VisualizerCoverShape.square ? PlayerCover.square : PlayerCover.flower);
  Future<void> setVisualizerRadius(double v) => _set(() => visualizerRadius = v.clamp(0.5, 2.5));
  Future<void> setVisualizerThickness(double v) => _set(() => visualizerThickness = v.clamp(1, 8));
  Future<void> setVisualizer(bool v) => _set(() => visualizer = v);
  Future<void> setShowQualityBadge(bool v) => _set(() => showQualityBadge = v);
  Future<void> setShowVideoSwitch(bool v) => _set(() => showVideoSwitch = v);
  Future<void> setLyricsSize(LyricsSize v) => _set(() => lyricsSize = v);
  Future<void> setLyricsAlign(LyricsAlign v) => _set(() => lyricsAlign = v);
  Future<void> setDimUnsungLyrics(bool v) => _set(() => dimUnsungLyrics = v);
  Future<void> setLyricsLines(LyricsLines v) => _set(() => lyricsLines = v);
  Future<void> setLyricsSync(LyricsSync v) => _set(() => lyricsSync = v);
  Future<void> setPageMotion(PageMotionStyle v) => _set(() => pageMotion = v);
  Future<void> setPageSpeed(PageMotionSpeed v) => _set(() => pageSpeed = v);
  Future<void> setSidebarWidth(double v) => _set(() => sidebarWidth = v.clamp(sidebarMin, sidebarMax));
  Future<void> setSidePanelWidth(double v) => _set(() => sidePanelWidth = v.clamp(sidePanelMin, sidePanelMax));
  Future<void> setMotion(Motion v) => _set(() => motion = v);
  Future<void> setPerformance(PerformanceMode v) => _set(() => performance = v);
  Future<void> setVideoDecoder(VideoDecoder v) => _set(() => videoDecoder = v);
  Future<void> setWindowButtons(bool v) => _set(() => windowButtons = v);

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

  /// Back to the defaults, except Performance, the video decoder and the window buttons: those are about this
  /// computer, not about looks.
  Future<void> reset() => _set(() {
    final mode = performance, decoder = videoDecoder, buttons = windowButtons;
    restore(const {});
    performance = mode;
    videoDecoder = decoder;
    windowButtons = buttons;
  });

  /// [base] with the corner and motion settings applied to menus, dialogs,
  /// buttons and page transitions.
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
