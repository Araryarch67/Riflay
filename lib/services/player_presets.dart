import '../platform/features.dart';
import 'appearance.dart';
import 'layout_prefs.dart';
import 'language.dart';

/// A look for the player, on phones and desktop, set up in one go. A preset is only a list of values for the
/// individual settings in Settings › Look & feel › Layout › Player: nothing remembers that one was applied, and
/// each setting can be changed afterwards.
/// [PlayerPreset.note] in the language shown; the names stay as they are.
String presetNote(PlayerPreset p) => switch (p.name) {
  'Classic' => tr.presetClassicNote,
  'Stacked' => tr.presetStackedNote,
  'Kawaii' => tr.presetKawaiiNote,
  _ => p.note,
};

class PlayerPreset {
  const PlayerPreset({
    required this.name,
    required this.note,
    this.cover = PlayerCover.flower,
    this.header = PlayerHeader.classic,
    this.titleActions = TitleActions.classic,
    this.progressBar = ProgressBarStyle.thin,
    this.progressShape = ProgressBarShape.wavy,
    this.timeLeft = false,
    this.transport = PlayerTransport.classic,
    this.volume = true,
    this.bottomRow = PlayerBottomRow.classic,
    this.lyrics = LyricsLayout.classic,
    this.mini = MiniPlayerStyle.classic,
    this.album = AlbumHeaderStyle.classic,
    this.playingRow = PlayingRowStyle.classic,
    this.badge = QualityBadgePlace.underArtist,
    this.lyricsLines = LyricsLines.all,
    this.volumeSlider = VolumeSliderShape.classic,
    this.background,
    this.tabBar,
    this.visualizer = false,
    this.visualizerStyle = VisualizerStyle.pulse,
    this.videoSwitch = true,
  });

  final String name;
  final String note;
  final PlayerCover cover;
  final PlayerHeader header;
  final TitleActions titleActions;
  final ProgressBarStyle progressBar;
  final ProgressBarShape progressShape;
  final bool timeLeft;
  final PlayerTransport transport;
  final bool volume;
  final PlayerBottomRow bottomRow;
  final LyricsLayout lyrics;
  final MiniPlayerStyle mini;
  final AlbumHeaderStyle album;
  final PlayingRowStyle playingRow;
  final QualityBadgePlace badge;

  /// All the lines, or Focused: the previous, current and next only.
  final LyricsLines lyricsLines;
  final VolumeSliderShape volumeSlider;

  /// The Now Playing background that goes with the look; null leaves the user's choice alone.
  final NowPlayingBackground? background;

  /// The phone's tab bar that goes with the look; null leaves the user's choice alone.
  final TabBarStyle? tabBar;

  /// The audio visualizer around the cover, and its style. Only counted where the visualizer exists (not on the web).
  final bool visualizer;
  final VisualizerStyle visualizerStyle;

  /// The Song / Video switch at the top of Now Playing: shown by every preset.
  final bool videoSwitch;

  /// Today's look, with the visualizer pulsing around the cover.
  static const classic = PlayerPreset(
    name: 'Classic',
    note: 'The player as it has always been, the cover pulsing with the music',
    visualizer: true,
  );

  static const stacked = PlayerPreset(
    name: 'Stacked',
    note: 'The cover as the page, joined buttons, a thick bar and a wide Play button',
    cover: PlayerCover.background,
    volume: true,
    header: PlayerHeader.centered,
    titleActions: TitleActions.boxed,
    progressBar: ProgressBarStyle.thick,
    progressShape: ProgressBarShape.pill,
    transport: PlayerTransport.pill,
    bottomRow: PlayerBottomRow.chips,
    lyrics: LyricsLayout.bottomCard,
    badge: QualityBadgePlace.timeRow,
    volumeSlider: VolumeSliderShape.pill,
  );

  /// Kawaii uses Capsule navigation; applying it must also leave Liquid Kawaii's glass bar behind.
  static const kawaii = PlayerPreset(
    name: 'Kawaii',
    note: 'The cover fades into the page, with plain icons, a wavy line and the volume behind a button',
    cover: PlayerCover.background,
    header: PlayerHeader.playingFrom,
    titleActions: TitleActions.plain,
    timeLeft: true,
    transport: PlayerTransport.plain,
    volume: false,
    bottomRow: PlayerBottomRow.minimal,
    lyrics: LyricsLayout.topHeader,
    mini: MiniPlayerStyle.capsule,
    album: AlbumHeaderStyle.hero,
    playingRow: PlayingRowStyle.card,
    badge: QualityBadgePlace.timeRow,
    background: NowPlayingBackground.video,
    volumeSlider: VolumeSliderShape.pill,
    tabBar: TabBarStyle.capsule,
  );

  /// Kawaii, with the Liquid glass tab bar on phones.
  static const liquidKawaii = PlayerPreset(
    name: 'Liquid Kawaii',
    note: 'Kawaii, with glass tabs on phones that shrink to one row as you scroll',
    cover: PlayerCover.background,
    header: PlayerHeader.playingFrom,
    titleActions: TitleActions.plain,
    timeLeft: true,
    transport: PlayerTransport.plain,
    volume: false,
    bottomRow: PlayerBottomRow.minimal,
    lyrics: LyricsLayout.topHeader,
    mini: MiniPlayerStyle.capsule,
    album: AlbumHeaderStyle.hero,
    playingRow: PlayingRowStyle.card,
    badge: QualityBadgePlace.timeRow,
    background: NowPlayingBackground.video,
    volumeSlider: VolumeSliderShape.pill,
    tabBar: TabBarStyle.glass,
  );

  static const all = [classic, stacked, kawaii, liquidKawaii];

  /// The settings that would change if this preset were applied to [p].
  int changesTo(LayoutPrefs p) {
    var n = 0;
    void differ(Object a, Object b) => n += a == b ? 0 : 1;
    differ(p.playerCover, cover);
    differ(p.playerHeader, header);
    differ(p.titleActions, titleActions);
    differ(p.progressBar, progressBar);
    differ(p.progressShape, progressShape);
    differ(p.showTimeLeft, timeLeft);
    differ(p.transport, transport);
    differ(p.showVolumeRow, volume);
    differ(p.bottomRow, bottomRow);
    differ(p.lyricsLayout, lyrics);
    differ(p.miniPlayer, mini);
    differ(p.albumHeader, album);
    differ(p.playingRow, playingRow);
    differ(p.qualityBadgePlace, badge);
    differ(p.lyricsLines, lyricsLines);
    differ(p.volumeSlider, volumeSlider);
    differ(p.showVideoSwitch, videoSwitch);
    if (background != null) differ(Appearance.instance.nowPlaying, background!);
    if (tabBar != null) differ(p.tabBar, tabBar!);
    if (Features.audioVisualizer) {
      differ(p.visualizer, visualizer);
      // The style only shows while it is on.
      if (visualizer) differ(p.visualizerStyle, visualizerStyle);
    }
    return n;
  }

  /// Whether every setting a preset covers is as it sets it (the background counts only if the preset has one).
  bool matches(LayoutPrefs p) => changesTo(p) == 0;

  /// Writes each setting (one save, one notify for the layout ones).
  Future<void> apply(LayoutPrefs p) async {
    await p.change(() {
      p.playerCover = cover;
      p.playerHeader = header;
      p.titleActions = titleActions;
      p.progressBar = progressBar;
      p.progressShape = progressShape;
      p.showTimeLeft = timeLeft;
      p.transport = transport;
      p.showVolumeRow = volume;
      p.bottomRow = bottomRow;
      p.lyricsLayout = lyrics;
      p.miniPlayer = mini;
      p.albumHeader = album;
      p.playingRow = playingRow;
      p.qualityBadgePlace = badge;
      p.lyricsLines = lyricsLines;
      p.volumeSlider = volumeSlider;
      p.showVideoSwitch = videoSwitch;
      if (tabBar != null) p.tabBar = tabBar!;
      p.visualizer = visualizer;
      if (visualizer) p.visualizerStyle = visualizerStyle;
      p.fitVisualizerStyle();
    });
    if (background != null) await Appearance.instance.setNowPlaying(background!);
  }
}

/// The name of the preset the current settings match, or null for a custom mix.
String? playerPresetName([LayoutPrefs? prefs]) {
  final p = prefs ?? LayoutPrefs.instance;
  // Prefer presets that also specify navigation over player-only presets.
  for (final preset in [
    ...PlayerPreset.all.where((preset) => preset.tabBar != null),
    ...PlayerPreset.all.where((preset) => preset.tabBar == null),
  ]) {
    if (preset.matches(p)) return preset.name;
  }
  return null;
}
