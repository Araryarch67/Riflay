import '../platform/features.dart';
import 'appearance.dart';
import 'layout_prefs.dart';

/// A look for the player, on phones and desktop, set up in one go. A preset is only a list of values for the
/// individual settings in Settings › Look & feel › Layout › Player: nothing remembers that one was applied, and
/// each setting can be changed afterwards.
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
    this.visualizer = false,
    this.visualizerStyle = VisualizerStyle.pulse,
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

  /// The audio visualizer around the cover, and its style. Only counted where the visualizer exists (not on the web).
  final bool visualizer;
  final VisualizerStyle visualizerStyle;

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
  );

  static const all = [classic, stacked, kawaii];

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
    if (background != null) differ(Appearance.instance.nowPlaying, background!);
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
      p.visualizer = visualizer;
      if (visualizer) p.visualizerStyle = visualizerStyle;
    });
    if (background != null) await Appearance.instance.setNowPlaying(background!);
  }
}

/// The name of the preset the current settings match, or null for a custom mix.
String? playerPresetName([LayoutPrefs? prefs]) {
  final p = prefs ?? LayoutPrefs.instance;
  for (final preset in PlayerPreset.all) {
    if (preset.matches(p)) return preset.name;
  }
  return null;
}
