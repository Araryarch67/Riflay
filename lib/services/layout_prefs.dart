import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/features.dart';
import '../platform/host.dart';
import '../ui/debug_switches.dart';
import 'page_motion.dart';
import 'language.dart';
import 'beta_features.dart';
export 'page_motion.dart' show PageMotionStyle, PageMotionSpeed;

/// Desktop controls can stay full width or sit inside a floating player.
/// The desktop's player bar. Every look sits flush along the window's foot; none floats over the page.
enum GlassTint { theme, light, black }

enum ExtraFeature {
  playlistSearch,
  recentPlaylist,
  undoRemoval,
  resumeLongTracks,
  playlistDownloadStatus,
  jumpToPlaying,
  copyLyrics,
  hideRecommendations;

  String get label => switch (this) {
    playlistSearch => tr.playlistSearch,
    recentPlaylist => tr.recentPlaylistPicker,
    undoRemoval => tr.undoRemoval,
    resumeLongTracks => tr.resumeLongTracks,
    playlistDownloadStatus => tr.playlistDownloadStatus,
    jumpToPlaying => tr.jumpToPlaying,
    copyLyrics => tr.copyLyricsLines,
    hideRecommendations => tr.hideRecommendations,
  };

  bool get enabled => LayoutPrefs.instance.extraFeatures.contains(this);
}

enum DesktopBarStyle {
  classic,
  compact,
  minimal;

  String get label => switch (this) {
    classic => tr.styleClassic,
    compact => tr.styleCompact,
    minimal => tr.styleMinimal,
  };
}

/// The desktop mini player: a small always-on-top window with the cover, or an island, a pill at the top of the
/// screen that opens into the controls when pointed at.
enum DesktopMiniStyle {
  window,
  island;

  String get label => switch (this) {
    window => tr.miniStyleWindow,
    island => tr.miniStyleIsland,
  };
}

/// Where the island sits: floating a little below the top of the screen (dragged anywhere), or docked to the top
/// edge like a notch (flat on top, round below; it slides only sideways).
enum IslandPlacement {
  floating,
  docked;

  String get label => switch (this) {
    floating => tr.islandFloating,
    docked => tr.islandDocked,
  };
}

/// The closed island's bars: following the music (its own audio levels, whatever the visualizer switch says),
/// moving on their own, or none.
enum IslandBars {
  music,
  animated,
  off;

  String get label => switch (this) {
    music => tr.islandBarsMusic,
    animated => tr.islandBarsAnimated,
    off => tr.off,
  };
}

/// What opens the island into its controls: the pointer resting on it, or a click.
enum IslandOpen {
  hover,
  click;

  String get label => switch (this) {
    hover => tr.islandOpenHover,
    click => tr.islandOpenClick,
  };
}

/// How wide the closed island is.
enum IslandWidth {
  compact(240),
  normal(300),
  wide(380);

  const IslandWidth(this.width);
  final double width;

  String get label => switch (this) {
    compact => tr.islandWidthCompact,
    normal => tr.islandWidthNormal,
    wide => tr.islandWidthWide,
  };
}

/// The island's colour: black, black with a breath of the cover's colour, or the cover's colour.
enum IslandColor {
  black(0),
  tinted(0.16),
  cover(0.42);

  const IslandColor(this.tint);

  /// How much of the cover's colour is mixed into the black.
  final double tint;

  String get label => switch (this) {
    black => tr.islandColorBlack,
    tinted => tr.islandColorTinted,
    cover => tr.islandColorCover,
  };
}

/// The same visual language in a player strip or a radial artwork surround.
enum VisualizerStyle {
  wave,
  bars,
  line,
  dots,
  mirror,
  twinWaves,
  pulse,
  orbit,
  petals,
  peaks;

  String get label => switch (this) {
    wave => tr.vizWave,
    bars => tr.vizBars,
    line => tr.vizLine,
    dots => tr.vizDots,
    mirror => tr.vizMirror,
    twinWaves => tr.vizTwinWaves,
    pulse => tr.vizPulse,
    orbit => tr.vizOrbit,
    petals => tr.vizPetals,
    peaks => tr.vizPeaks,
  };
  bool get radial => this == pulse || this == orbit || this == petals;

  /// The styles that can show with [cover]: the radial ones ring a framed cover, and Background has no frame.
  static List<VisualizerStyle> fitting(PlayerCover cover) => cover == PlayerCover.background
      ? [
          for (final s in values)
            if (!s.radial) s,
        ]
      : values;
}

/// The outline of a player cover (what [PlayerCover] comes to when the cover is not the background).
enum VisualizerCoverShape {
  flower,
  square;

  String get label => switch (this) {
    flower => tr.shapeFlower,
    square => tr.shapeSquare,
  };
}

/// How round the corners of covers, cards, menus and dialogs are.
enum CornerStyle {
  square(0),
  rounded(1),
  extraRound(2);

  const CornerStyle(this.scale);
  String get label => switch (this) {
    square => tr.shapeSquare,
    rounded => tr.shapeRounded,
    extraRound => tr.shapeExtraRound,
  };

  /// Multiplies every corner radius (1 is how the app has always looked).
  final double scale;
}

/// How tightly lists and grids are packed.
enum Density {
  comfortable,
  compact;

  String get label => switch (this) {
    comfortable => tr.densityComfortable,
    compact => tr.styleCompact,
  };
}

/// How big the covers in shelves and grids are.
enum CoverSize {
  small(0.8),
  medium(1),
  large(1.25);

  const CoverSize(this.scale);
  String get label => switch (this) {
    small => tr.sizeSmall,
    medium => tr.sizeMedium,
    large => tr.sizeLarge,
  };
  final double scale;
}

/// How much the app moves.
enum Motion {
  full,
  reduced,
  off;

  String get label => switch (this) {
    full => tr.motionFull,
    reduced => tr.motionReduced,
    off => tr.off,
  };
}

/// How music videos are decoded (mpv's `hwdec`). A setting of this computer, like [PerformanceMode]:
/// Reset leaves it alone.
enum VideoDecoder {
  automatic('auto-safe'),
  hardware('auto'),
  software('no');

  const VideoDecoder(this.hwdec);
  String get label => switch (this) {
    automatic => tr.decoderAuto,
    hardware => tr.decoderGpu,
    software => tr.decoderCpu,
  };
  String get note => switch (this) {
    automatic => tr.decoderAutoNote,
    hardware => tr.decoderGpuNote,
    software => tr.decoderCpuNote,
  };

  /// mpv's `hwdec` value.
  final String hwdec;
}

/// How much the app spends on looks. [lightweight] caps the user's own Look & feel choices
/// (Background covers become Square); [heavy] lifts the frame-rate limits on decorations.
enum PerformanceMode {
  lightweight,
  balanced,
  heavy;

  String get label => switch (this) {
    lightweight => tr.perfLight,
    balanced => tr.perfBalanced,
    heavy => tr.perfHeavy,
  };
  String get note => switch (this) {
    lightweight => tr.perfLightNote,
    balanced => tr.perfBalancedNote,
    heavy => tr.perfHeavyNote,
  };
}

enum ProgressBarStyle {
  thin(4),
  thick(9);

  const ProgressBarStyle(this.height);
  String get label => switch (this) {
    thin => tr.styleThin,
    thick => tr.styleThick,
  };
  final double height;
}

enum ProgressBarShape {
  straight,
  wavy,

  /// A thick rounded track with a pill of elapsed time and a bar for a thumb (the phone's player and the desktop bar).
  pill,

  /// A flat 4 px track with round ends and no handle until it is dragged (the phone's player and the desktop bar).
  thin,

  /// The song's loudness as bars across the track, lit up to where it is ([AudioReport.waveform]). Until the
  /// song is measured (a stream is, on Wi-Fi), the plain track.
  waveform;

  String get label => switch (this) {
    straight => tr.shapeStraight,
    wavy => tr.shapeWavy,
    pill => tr.shapePill,
    thin => tr.shapeThinLine,
    waveform => tr.shapeWaveform,
  };
}

enum PlayButtonShape {
  circle,
  roundedSquare,
  flower;

  String get label => switch (this) {
    circle => tr.shapeCircle,
    roundedSquare => tr.shapeRoundedSquare,
    flower => tr.shapeFlower,
  };
}

enum PhoneCoverSize {
  normal,
  large;

  String get label => switch (this) {
    normal => tr.sizeNormal,
    large => tr.sizeLarge,
  };
}

/// The order of playlists in Library, after pinned entries.
enum PlaylistOrder { library, nameAscending, nameDescending, custom }

/// The artwork treatment in the player, including a full-bleed cover or the Riflay mark.
enum PlayerCover {
  square,
  flower,
  background,
  logo;

  String get label => switch (this) {
    logo => tr.coverAppLogo,
    square => tr.shapeSquare,
    flower => tr.shapeFlower,
    background => tr.coverBackground,
  };
}

/// The top of Now Playing.
enum PlayerHeader {
  classic,
  centered,
  playingFrom;

  String get label => switch (this) {
    classic => tr.styleClassic,
    centered => tr.headerCentred,
    playingFrom => tr.headerPlayingFrom,
  };
}

/// The buttons beside the song's title.
enum TitleActions {
  classic,
  boxed,
  plain;

  String get label => switch (this) {
    classic => tr.styleClassic,
    boxed => tr.styleBoxed,
    plain => tr.stylePlain,
  };
}

/// The previous / play / next controls.
enum PlayerTransport {
  classic,
  pill,
  plain;

  String get label => switch (this) {
    classic => tr.styleClassic,
    pill => tr.shapePill,
    plain => tr.stylePlain,
  };
}

/// The row of buttons under the controls. Every one keeps a Lyrics button. [minimal] is icons only: Lyrics, a capsule
/// with the volume and the output / listen-together buttons, and Queue.
enum PlayerBottomRow {
  classic,
  chips,
  minimal;

  String get label => switch (this) {
    classic => tr.styleClassic,
    chips => tr.styleChips,
    minimal => tr.styleIcons,
  };
}

/// The lyrics page: its header and the player under the lyrics (on desktop a song card on top or at the bottom).
enum LyricsLayout {
  classic,
  bottomCard,
  topHeader;

  String get label => switch (this) {
    classic => tr.styleClassic,
    bottomCard => tr.styleBottomCard,
    topHeader => tr.styleTopHeader,
  };
}

/// The phone's mini player above the tab bar: the bar as it has always been, or a floating pill with a flower cover,
/// round translucent previous / next and a round accent play button.
enum MiniPlayerStyle {
  classic,
  capsule;

  String get label => switch (this) {
    classic => tr.styleClassic,
    capsule => tr.styleFloatingPill,
  };
}

/// The header of an album or playlist page.
enum AlbumHeaderStyle {
  classic,
  hero;

  String get label => switch (this) {
    classic => tr.styleClassic,
    hero => tr.styleHero,
  };
}

/// The look of every slider in the app (Settings › Now Playing › Slider look); the progress bar has its own shape.
enum VolumeSliderShape {
  classic,
  thin,
  pill;

  String get label => switch (this) {
    classic => tr.styleClassic,
    thin => tr.shapeThinLine,
    pill => tr.shapePill,
  };
}

/// Where the sound-quality badge (FLAC, Opus 130 kbps...) sits on the phone's player.
enum QualityBadgePlace {
  underArtist,
  timeRow;

  String get label => switch (this) {
    underArtist => tr.badgeUnderArtist,
    timeRow => tr.badgeTimeRow,
  };
}

/// How the song that is playing stands out in a list of songs.
enum PlayingRowStyle {
  classic,
  card;

  String get label => switch (this) {
    classic => tr.styleClassic,
    card => tr.styleHighlightedCard,
  };
}

enum LyricsSize {
  small(0.85),
  normal(1),
  large(1.2),
  largest(1.4);

  const LyricsSize(this.scale);
  String get label => switch (this) {
    small => tr.sizeSmall,
    normal => tr.sizeNormal,
    large => tr.sizeLarge,
    largest => tr.sizeLargest,
  };
  final double scale;
}

/// How many lyric lines are shown at once.
enum LyricsLines {
  all,

  /// The previous, the current and the next line, far apart.
  focused;

  String get label => switch (this) {
    all => tr.all,
    focused => tr.lyricsFocused,
  };
}

/// How timed lyrics light up.
enum LyricsSync {
  /// Word by word where the lyrics have word timings (else line by line).
  word,

  /// The whole current line at once, even where the lyrics have word timings.
  line;

  String get label => switch (this) {
    word => tr.lyricsWordByWord,
    line => tr.lyricsLineByLine,
  };
}

enum LyricsAlign {
  left,
  centre;

  String get label => switch (this) {
    left => tr.alignLeft,
    centre => tr.alignCentre,
  };
}

/// How the phone's tab bar looks. [docked] ones sit on the bottom edge; the others hover a little above it.
enum TabBarStyle {
  classic(docked: true),
  material(docked: true),
  underline(docked: true),
  minimal(docked: true),
  text(docked: true),
  floating,
  capsule,
  dock,
  glass;

  const TabBarStyle({this.docked = false});
  String get label => switch (this) {
    classic => tr.styleClassic,
    material => tr.styleMaterial,
    underline => tr.styleUnderline,
    minimal => tr.styleMinimal,
    text => tr.styleTextOnly,
    floating => tr.styleFloating,
    capsule => tr.styleCapsule,
    dock => tr.styleDock,
    glass => tr.styleLiquidGlass,
  };
  final bool docked;
}

/// The presentation of the Quick picks section.
enum HomeStyle {
  classic,
  carousel;

  String get label => switch (this) {
    classic => tr.homeStyleClassic,
    carousel => tr.homeStyleCarousel,
  };
}

/// The sections of Home, in their default order.
enum HomeSection {
  quickPicks,
  dailyMix,
  recentlyPlayed,
  playlists,
  albums,
  artists,
  discover,
  recentlyAdded;

  String get label => switch (this) {
    quickPicks => tr.quickPicks,
    dailyMix => tr.dailyMix,
    recentlyPlayed => tr.recentlyPlayed,
    playlists => tr.yourPlaylists,
    albums => tr.yourAlbums,
    artists => tr.artists,
    discover => tr.fromYoutubeMusic,
    recentlyAdded => tr.recentlyAdded,
  };
}

/// How the app is laid out: corners, density, cover sizes, Home's sections, the
/// player's details, lyrics and motion. One instance for the whole app
/// ([instance]), loaded before the first frame. Fresh installs and Reset share
/// the same defaults.
class LayoutPrefs extends ChangeNotifier {
  LayoutPrefs._();

  static final instance = LayoutPrefs._().._watchBeta();

  void _watchBeta() => BetaFeatures.instance.addListener(notifyListeners);

  static const _key = 'layout.v1';

  CornerStyle corners = CornerStyle.rounded;
  Density density = Density.comfortable;
  CoverSize coverSize = CoverSize.medium;

  /// Home's sections in the order shown, and the ones switched off.
  List<HomeSection> homeOrder = List.of(HomeSection.values);
  Set<HomeSection> homeHidden = {};
  HomeStyle homeStyle = HomeStyle.classic;

  ProgressBarStyle progressBar = ProgressBarStyle.thin;
  ProgressBarShape progressShape = ProgressBarShape.wavy;
  PlayButtonShape playButton = PlayButtonShape.flower;
  PhoneCoverSize phoneCover = PhoneCoverSize.normal;

  /// The player, part by part, on phones and desktop. The defaults are how it has always looked; Settings › Look & feel ›
  /// Layout › Player changes them one by one, and Presets sets several at once.
  PlayerCover playerCover = PlayerCover.flower;

  /// Background artwork is unavailable in Lightweight; framed covers stay selectable.
  List<PlayerCover> get playerCoverChoices => performance == PerformanceMode.lightweight
      ? const [PlayerCover.flower, PlayerCover.square, PlayerCover.logo]
      : PlayerCover.values;

  void _fitPlayerOptions() {
    if (performance == PerformanceMode.lightweight && playerCover == PlayerCover.background) {
      playerCover = PlayerCover.square;
    }
    if (showVolumeRow && bottomRow == PlayerBottomRow.minimal) bottomRow = PlayerBottomRow.classic;
  }

  PlayerHeader playerHeader = PlayerHeader.classic;
  TitleActions titleActions = TitleActions.classic;
  bool showTimeLeft = false;
  PlayerTransport transport = PlayerTransport.classic;
  bool showVolumeRow = true;

  /// Icons include their own volume control; a visible slider uses Classic or Chips.
  List<PlayerBottomRow> get bottomRowChoices =>
      showVolumeRow ? const [PlayerBottomRow.classic, PlayerBottomRow.chips] : PlayerBottomRow.values;

  /// Liquid presets frost the player's transparent control surfaces.
  String startupTab = 'home', libraryChip = '';
  int swipeDistance = 72;
  Set<String> hiddenCollections = {};
  PlaylistOrder playlistOrder = PlaylistOrder.library;
  List<String> customPlaylistOrder = const [];
  Set<String> pinnedPlaylists = const {};
  Map<String, Set<String>> pinnedTracks = const {};
  List<String> likedTrackOrder = const [];
  Set<ExtraFeature> extraFeatures = const {};
  String? lastPlaylistChoice;
  Set<String> hiddenRecommendations = const {};

  Future<void> hideRecommendation(String id) => _set(() => hiddenRecommendations = {...hiddenRecommendations, id});

  Future<void> setExtraFeature(ExtraFeature feature, bool enabled) => _set(() {
    extraFeatures = {...extraFeatures};
    if (enabled) {
      extraFeatures.add(feature);
    } else {
      extraFeatures.remove(feature);
    }
  });

  Future<void> rememberPlaylist(String key) => _set(() => lastPlaylistChoice = key);

  Future<void> toggleTrackPin(String collection, String id) => _set(() {
    final pins = {...?pinnedTracks[collection]};
    if (!pins.remove(id)) pins.add(id);
    pinnedTracks = {...pinnedTracks};
    if (pins.isEmpty) {
      pinnedTracks.remove(collection);
    } else {
      pinnedTracks[collection] = pins;
    }
  });

  Future<void> setLikedTrackOrder(List<String> ids) => _set(() => likedTrackOrder = List.of(ids));

  Future<void> setPlaylistOrder(PlaylistOrder order) => _set(() => playlistOrder = order);

  Future<void> movePlaylist(List<String> visible, String moved, int delta) {
    final at = visible.indexOf(moved);
    final to = at + delta;
    if (at < 0 || to < 0 || to >= visible.length) return Future.value();
    final order = [...visible];
    order.insert(to, order.removeAt(at));
    return _set(() {
      final visibleKeys = visible.toSet();
      customPlaylistOrder = [...order, ...customPlaylistOrder.where((key) => !visibleKeys.contains(key))];
      playlistOrder = PlaylistOrder.custom;
    });
  }

  Future<void> togglePinnedPlaylist(String key) => _set(() {
    final pins = {...pinnedPlaylists};
    if (!pins.remove(key)) pins.add(key);
    pinnedPlaylists = pins;
  });
  Future<void> setStartupTab(String value) => _set(() => startupTab = value);
  Future<void> setLibraryChip(String value) => _set(() => libraryChip = value);
  Future<void> setSwipeDistance(int value) => _set(() => swipeDistance = value.clamp(32, 120));
  Future<void> showCollection(String key, bool show) => _set(() {
    hiddenCollections = {...hiddenCollections};
    if (show) {
      hiddenCollections.remove(key);
    } else {
      hiddenCollections.add(key);
    }
  });
  GlassTint glassTint = GlassTint.theme;
  GlassTint playerGlassTint = GlassTint.theme;
  GlassTint miniGlassTint = GlassTint.theme;
  bool playerGlassControls = false;

  /// Which solid parts Liquid Glass controls also frost; off by default, so only the buttons around them are glass.
  bool glassSeekBar = false;
  bool glassTransport = false;
  bool glassVolume = false;
  PlayerBottomRow bottomRow = PlayerBottomRow.classic;
  LyricsLayout lyricsLayout = LyricsLayout.classic;
  MiniPlayerStyle miniPlayer = MiniPlayerStyle.classic;
  AlbumHeaderStyle albumHeader = AlbumHeaderStyle.classic;
  PlayingRowStyle playingRow = PlayingRowStyle.classic;
  QualityBadgePlace qualityBadgePlace = QualityBadgePlace.timeRow;
  VolumeSliderShape volumeSlider = VolumeSliderShape.classic;

  /// The Classic preset uses the Capsule navigation surface.
  TabBarStyle tabBar = TabBarStyle.capsule;
  bool keepPhoneNavOpen = false;
  bool hidePhoneNavLabels = false;
  DesktopBarStyle desktopBar = DesktopBarStyle.classic;
  DesktopMiniStyle desktopMini = DesktopMiniStyle.window;

  /// The line being sung, in the desktop mini player (its Lyrics button).
  bool miniLyrics = true;

  /// The desktop mini player's look and what it shows (Settings › Pages & navigation › Desktop mini player).
  IslandPlacement islandPlacement = IslandPlacement.floating;
  IslandBars islandBars = IslandBars.music;
  IslandOpen islandOpen = IslandOpen.hover;
  IslandWidth islandWidth = IslandWidth.normal;
  IslandColor islandColor = IslandColor.tinted;
  bool miniOnTop = true;
  bool miniVolume = true;
  bool miniShuffleRepeat = true;
  bool miniQuality = true;
  bool showPlayerClose = false;
  bool showQualityBadge = true;

  /// The Song / Video switch at the top of Now Playing, for a song with a music video. On in every preset.
  bool showVideoSwitch = true;
  bool visualizer = true;
  bool get visualizerEnabled =>
      visualizer && Features.audioVisualizer && BetaFeatures.instance.isOn(BetaFeature.audioVisualizer);

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

  /// The line being sung sits on a dark pane of frosted glass, faint, from one side of the line to the other.
  bool highlightLyricLine = true;
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
    final d = dur(Duration(milliseconds: (base * p.pageSpeed.factor).round()));
    // Frugal Balanced on a computer: the same motion, quicker. Each frame of a page sliding in costs the Linux main
    // thread ~10 ms (the whole window composited); 440 ms was ~26 frames, a one-sample spike in btop on every page.
    if (frugal) {
      final most = Duration(milliseconds: reverse ? 120 : 160);
      return d < most ? d : most;
    }
    return d;
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
  /// The player in its Classic style as far as its top goes, whatever its quality badge's place or volume slider's
  /// shape (they sit lower down): it keeps its Close arrow, as Classic always has. The other styles show it with
  /// [showPlayerClose].
  bool get classicPlayerStyle =>
      playerCover != PlayerCover.background &&
      playerHeader == PlayerHeader.classic &&
      titleActions == TitleActions.classic &&
      transport == PlayerTransport.classic &&
      bottomRow == PlayerBottomRow.classic &&
      !playerGlassControls;

  bool get classicPlayerFace =>
      playerCover != PlayerCover.background &&
      playerHeader == PlayerHeader.classic &&
      titleActions == TitleActions.classic &&
      transport == PlayerTransport.classic &&
      bottomRow == PlayerBottomRow.classic &&
      volumeSlider == VolumeSliderShape.classic &&
      !playerGlassControls &&
      showVolumeRow;

  /// Performance mode: Lightweight turns off every effect that isn't needed to use the app.
  static bool get lightweight => instance.performance == PerformanceMode.lightweight;

  /// Performance mode: Heavy runs decorations and the seek bar at the display's full rate.
  static bool get heavy => instance.performance == PerformanceMode.heavy;

  /// Balanced on a computer: the flower, wave, karaoke and seek bar move together every [frugalEvery], and the
  /// visualizer at 10 fps on every other of those beats. A playing song in a focused window then takes ~0.25% of the
  /// whole processor; at 20 fps it was ~0.5%. Heavy keeps every effect. `RIFLAY_FULL_BALANCED` turns this off.
  static bool get frugal =>
      instance.performance == PerformanceMode.balanced &&
      (Host.isLinux || Host.isWindows || Host.isMacOS) &&
      !DebugSwitches.fullBalanced;

  /// 5 fps: what [frugal] moves at, one beat shared by everything that moves.
  static const frugalEvery = Duration(milliseconds: 200);

  /// Sliding, scaling and bouncing; only with full motion. Fades stay otherwise.
  static bool get moves => effectiveMotion == Motion.full;

  Future<void> load() async {
    await BetaFeatures.instance.load();
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
    final legacyShape = switch (j['visualizerCoverShape']) {
      'square' => PlayerCover.square,
      'flower' => PlayerCover.flower,
      _ => d.playerCover,
    };
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
    startupTab = j['startupTab'] as String? ?? d.startupTab;
    libraryChip = j['libraryChip'] as String? ?? d.libraryChip;
    playlistOrder = pick(PlaylistOrder.values, 'playlistOrder', d.playlistOrder);
    customPlaylistOrder = (j['customPlaylistOrder'] as List?)?.whereType<String>().toList() ?? const [];
    pinnedPlaylists = (j['pinnedPlaylists'] as List?)?.whereType<String>().toSet() ?? const {};
    pinnedTracks = {
      for (final entry in (j['pinnedTracks'] as Map? ?? const {}).entries)
        if (entry.key is String && entry.value is List)
          entry.key as String: (entry.value as List).whereType<String>().toSet(),
    };
    likedTrackOrder = (j['likedTrackOrder'] as List?)?.whereType<String>().toList() ?? const [];
    extraFeatures = {
      for (final key in (j['extraFeatures'] as List? ?? const []).whereType<String>())
        ?ExtraFeature.values.asNameMap()[key],
    };
    lastPlaylistChoice = j['lastPlaylistChoice'] as String?;
    hiddenRecommendations = (j['hiddenRecommendations'] as List?)?.whereType<String>().toSet() ?? const {};
    swipeDistance = (j['swipeDistance'] as num?)?.round().clamp(32, 120) ?? d.swipeDistance;
    hiddenCollections = (j['hiddenCollections'] as List?)?.whereType<String>().toSet() ?? {...d.hiddenCollections};
    glassTint = pick(GlassTint.values, 'glassTint', d.glassTint);
    playerGlassTint = pick(GlassTint.values, 'playerGlassTint', d.playerGlassTint);
    miniGlassTint = pick(GlassTint.values, 'miniGlassTint', d.miniGlassTint);
    playerGlassControls = j['playerGlassControls'] as bool? ?? d.playerGlassControls;
    glassSeekBar = j['glassSeekBar'] as bool? ?? d.glassSeekBar;
    glassTransport = j['glassTransport'] as bool? ?? d.glassTransport;
    glassVolume = j['glassVolume'] as bool? ?? d.glassVolume;
    bottomRow = pick(PlayerBottomRow.values, 'bottomRow', d.bottomRow);
    lyricsLayout = pick(LyricsLayout.values, 'lyricsLayout', d.lyricsLayout);
    miniPlayer = pick(MiniPlayerStyle.values, 'miniPlayer', d.miniPlayer);
    albumHeader = pick(AlbumHeaderStyle.values, 'albumHeader', d.albumHeader);
    playingRow = pick(PlayingRowStyle.values, 'playingRow', d.playingRow);
    qualityBadgePlace = pick(QualityBadgePlace.values, 'qualityBadgePlace', d.qualityBadgePlace);
    volumeSlider = pick(VolumeSliderShape.values, 'volumeSlider', d.volumeSlider);
    tabBar = pick(TabBarStyle.values, 'tabBar', d.tabBar);
    keepPhoneNavOpen = j['keepPhoneNavOpen'] as bool? ?? d.keepPhoneNavOpen;
    hidePhoneNavLabels = j['hidePhoneNavLabels'] as bool? ?? d.hidePhoneNavLabels;
    // The floating looks are gone: Floating became Classic, Capsule (a one-row floating dock) Compact.
    desktopBar = switch (j['desktopBar']) {
      'floating' => DesktopBarStyle.classic,
      'capsule' => DesktopBarStyle.compact,
      _ => pick(DesktopBarStyle.values, 'desktopBar', d.desktopBar),
    };
    desktopMini = pick(DesktopMiniStyle.values, 'desktopMini', d.desktopMini);
    miniLyrics = j['miniLyrics'] as bool? ?? d.miniLyrics;
    islandPlacement = pick(IslandPlacement.values, 'islandPlacement', d.islandPlacement);
    islandBars = pick(IslandBars.values, 'islandBars', d.islandBars);
    islandOpen = pick(IslandOpen.values, 'islandOpen', d.islandOpen);
    islandWidth = pick(IslandWidth.values, 'islandWidth', d.islandWidth);
    islandColor = pick(IslandColor.values, 'islandColor', d.islandColor);
    miniOnTop = j['miniOnTop'] as bool? ?? d.miniOnTop;
    miniVolume = j['miniVolume'] as bool? ?? d.miniVolume;
    miniShuffleRepeat = j['miniShuffleRepeat'] as bool? ?? d.miniShuffleRepeat;
    miniQuality = j['miniQuality'] as bool? ?? d.miniQuality;
    showPlayerClose = j['showPlayerClose'] as bool? ?? d.showPlayerClose;
    showQualityBadge = j['showQualityBadge'] as bool? ?? d.showQualityBadge;
    showVideoSwitch = j['showVideoSwitch'] as bool? ?? d.showVideoSwitch;
    visualizer = j['visualizer'] as bool? ?? d.visualizer;
    visualizerStyle = j['visualizerVersion'] == 3
        ? pick(VisualizerStyle.values, 'visualizerStyle', d.visualizerStyle)
        : VisualizerStyle.pulse;
    fitVisualizerStyle();
    visualizerRadius = (j['visualizerRadius'] as num?)?.toDouble().clamp(0.5, 2.5) ?? d.visualizerRadius;
    visualizerThickness = (j['visualizerThickness'] as num?)?.toDouble().clamp(1, 8) ?? d.visualizerThickness;
    lyricsSize = pick(LyricsSize.values, 'lyricsSize', d.lyricsSize);
    lyricsAlign = pick(LyricsAlign.values, 'lyricsAlign', d.lyricsAlign);
    dimUnsungLyrics = j['dimUnsungLyrics'] as bool? ?? d.dimUnsungLyrics;
    highlightLyricLine = j['highlightLyricLine'] as bool? ?? d.highlightLyricLine;
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
    homeStyle = pick(HomeStyle.values, 'homeStyle', d.homeStyle);
    final byName = HomeSection.values.asNameMap();
    final order = <HomeSection>[for (final n in (j['homeOrder'] as List?) ?? const []) ?byName[n]];
    // A section added by a newer version joins at its default place.
    for (final s in HomeSection.values) {
      if (!order.contains(s)) order.insert(order.length.clamp(0, s.index), s);
    }
    homeOrder = order.toSet().toList();
    homeHidden = {for (final n in (j['homeHidden'] as List?) ?? const []) ?byName[n]};
    _fitPlayerOptions();
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
    'startupTab': startupTab,
    'libraryChip': libraryChip,
    'playlistOrder': playlistOrder.name,
    'customPlaylistOrder': customPlaylistOrder,
    'pinnedPlaylists': pinnedPlaylists.toList(),
    'pinnedTracks': {for (final entry in pinnedTracks.entries) entry.key: entry.value.toList()},
    'likedTrackOrder': likedTrackOrder,
    'extraFeatures': [
      for (final feature in ExtraFeature.values)
        if (extraFeatures.contains(feature)) feature.name,
    ],
    'lastPlaylistChoice': lastPlaylistChoice,
    'hiddenRecommendations': hiddenRecommendations.toList(),
    'swipeDistance': swipeDistance,
    'hiddenCollections': hiddenCollections.toList(),
    'glassTint': glassTint.name,
    'playerGlassTint': playerGlassTint.name,
    'miniGlassTint': miniGlassTint.name,
    'playerGlassControls': playerGlassControls,
    'glassSeekBar': glassSeekBar,
    'glassTransport': glassTransport,
    'glassVolume': glassVolume,
    'bottomRow': bottomRow.name,
    'lyricsLayout': lyricsLayout.name,
    'miniPlayer': miniPlayer.name,
    'albumHeader': albumHeader.name,
    'playingRow': playingRow.name,
    'qualityBadgePlace': qualityBadgePlace.name,
    'volumeSlider': volumeSlider.name,
    'tabBar': tabBar.name,
    'keepPhoneNavOpen': keepPhoneNavOpen,
    'hidePhoneNavLabels': hidePhoneNavLabels,
    'desktopBar': desktopBar.name,
    'desktopMini': desktopMini.name,
    'miniLyrics': miniLyrics,
    'islandPlacement': islandPlacement.name,
    'islandBars': islandBars.name,
    'islandOpen': islandOpen.name,
    'islandWidth': islandWidth.name,
    'islandColor': islandColor.name,
    'miniOnTop': miniOnTop,
    'miniVolume': miniVolume,
    'miniShuffleRepeat': miniShuffleRepeat,
    'miniQuality': miniQuality,
    'showPlayerClose': showPlayerClose,
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
    'highlightLyricLine': highlightLyricLine,
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
    'homeStyle': homeStyle.name,
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
    _fitPlayerOptions();
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
  Future<void> setPlayerCover(PlayerCover v) => _set(() {
    playerCover = v;
    fitVisualizerStyle();
  });

  /// A radial style with a Background cover has nothing to ring: it becomes Wave, the style the settings offer first.
  void fitVisualizerStyle() {
    if (!VisualizerStyle.fitting(playerCover).contains(visualizerStyle)) visualizerStyle = VisualizerStyle.wave;
  }

  Future<void> setPlayerHeader(PlayerHeader v) => _set(() => playerHeader = v);
  Future<void> setTitleActions(TitleActions v) => _set(() => titleActions = v);
  Future<void> setShowTimeLeft(bool v) => _set(() => showTimeLeft = v);
  Future<void> setTransport(PlayerTransport v) => _set(() => transport = v);
  Future<void> setShowVolumeRow(bool v) => _set(() => showVolumeRow = v);
  Future<void> setGlassTint(GlassTint value) => _set(() => glassTint = value);
  Future<void> setPlayerGlassTint(GlassTint value) => _set(() => playerGlassTint = value);
  Future<void> setMiniGlassTint(GlassTint value) => _set(() => miniGlassTint = value);
  Future<void> setPlayerGlassControls(bool v) => _set(() => playerGlassControls = v);
  Future<void> setGlassSeekBar(bool v) => _set(() => glassSeekBar = v);
  Future<void> setGlassTransport(bool v) => _set(() => glassTransport = v);
  Future<void> setGlassVolume(bool v) => _set(() => glassVolume = v);
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
  Future<void> setDesktopMini(DesktopMiniStyle v) => _set(() => desktopMini = v);
  Future<void> setMiniLyrics(bool v) => _set(() => miniLyrics = v);
  Future<void> setIslandPlacement(IslandPlacement v) => _set(() => islandPlacement = v);
  Future<void> setIslandBars(IslandBars v) => _set(() => islandBars = v);
  Future<void> setIslandOpen(IslandOpen v) => _set(() => islandOpen = v);
  Future<void> setIslandWidth(IslandWidth v) => _set(() => islandWidth = v);
  Future<void> setIslandColor(IslandColor v) => _set(() => islandColor = v);
  Future<void> setMiniOnTop(bool v) => _set(() => miniOnTop = v);
  Future<void> setMiniVolume(bool v) => _set(() => miniVolume = v);
  Future<void> setMiniShuffleRepeat(bool v) => _set(() => miniShuffleRepeat = v);
  Future<void> setMiniQuality(bool v) => _set(() => miniQuality = v);
  Future<void> setHidePhoneNavLabels(bool value) => _set(() => hidePhoneNavLabels = value);
  Future<void> setKeepPhoneNavOpen(bool value) => _set(() => keepPhoneNavOpen = value);
  Future<void> setTabBar(TabBarStyle v) => _set(() => tabBar = v);
  Future<void> setVisualizerStyle(VisualizerStyle v) => _set(() => visualizerStyle = v);
  Future<void> setVisualizerCoverShape(VisualizerCoverShape v) =>
      _set(() => playerCover = v == VisualizerCoverShape.square ? PlayerCover.square : PlayerCover.flower);
  Future<void> setVisualizerRadius(double v) => _set(() => visualizerRadius = v.clamp(0.5, 2.5));
  Future<void> setVisualizerThickness(double v) => _set(() => visualizerThickness = v.clamp(1, 8));
  Future<void> setVisualizer(bool v) async {
    await BetaFeatures.instance.set(BetaFeature.audioVisualizer, v);
    await _set(() => visualizer = v);
  }

  Future<void> setShowPlayerClose(bool v) => _set(() => showPlayerClose = v);
  Future<void> setShowQualityBadge(bool v) => _set(() => showQualityBadge = v);
  Future<void> setShowVideoSwitch(bool v) => _set(() => showVideoSwitch = v);
  Future<void> setLyricsSize(LyricsSize v) => _set(() => lyricsSize = v);
  Future<void> setLyricsAlign(LyricsAlign v) => _set(() => lyricsAlign = v);
  Future<void> setDimUnsungLyrics(bool v) => _set(() => dimUnsungLyrics = v);
  Future<void> setHighlightLyricLine(bool v) => _set(() => highlightLyricLine = v);
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

  Future<void> setHomeStyle(HomeStyle style) => _set(() => homeStyle = style);

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
