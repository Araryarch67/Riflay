import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/features.dart';
import 'appearance.dart';
import 'layout_prefs.dart';
import 'language.dart';

/// A look for the player, on phones and desktop, set up in one go. A preset is only a list of values for the
/// individual settings in Settings › Look & feel › Now Playing: nothing remembers that one was applied, and
/// each setting can be changed afterwards.
/// [PlayerPreset.note] in the language shown; the names stay as they are.
String presetNote(PlayerPreset p) => switch (p.name) {
  'Classic' => tr.presetClassicNote,
  'Stacked' => tr.presetStackedNote,
  'Liquid Stacked' => tr.presetLiquidStackedNote,
  'Kawaii' => tr.presetKawaiiNote,
  'Liquid Kawaii' => tr.presetLiquidKawaiiNote,
  _ when p.custom => tr.presetCustomNote,
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
    this.glassControls = false,
    this.glassTransport,
    this.glassSeekBar,
    this.glassVolume,
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
    this.custom = false,
  });

  /// The player as it is set up now, under [name]: a preset of the user's own ([CustomPresets]).
  factory PlayerPreset.fromCurrent(String name, [LayoutPrefs? prefs]) {
    final p = prefs ?? LayoutPrefs.instance;
    return PlayerPreset(
      name: name,
      note: '',
      cover: p.playerCover,
      header: p.playerHeader,
      titleActions: p.titleActions,
      progressBar: p.progressBar,
      progressShape: p.progressShape,
      timeLeft: p.showTimeLeft,
      transport: p.transport,
      volume: p.showVolumeRow,
      glassControls: p.playerGlassControls,
      glassTransport: p.glassTransport,
      glassSeekBar: p.glassSeekBar,
      glassVolume: p.glassVolume,
      bottomRow: p.bottomRow,
      lyrics: p.lyricsLayout,
      mini: p.miniPlayer,
      album: p.albumHeader,
      playingRow: p.playingRow,
      badge: p.qualityBadgePlace,
      lyricsLines: p.lyricsLines,
      volumeSlider: p.volumeSlider,
      background: Appearance.instance.nowPlaying,
      tabBar: p.tabBar,
      visualizer: p.visualizer,
      visualizerStyle: p.visualizerStyle,
      videoSwitch: p.showVideoSwitch,
      custom: true,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'cover': cover.name,
    'header': header.name,
    'titleActions': titleActions.name,
    'progressBar': progressBar.name,
    'progressShape': progressShape.name,
    'timeLeft': timeLeft,
    'transport': transport.name,
    'volume': volume,
    'glassControls': glassControls,
    'glassTransport': glassTransport,
    'glassSeekBar': glassSeekBar,
    'glassVolume': glassVolume,
    'bottomRow': bottomRow.name,
    'lyrics': lyrics.name,
    'mini': mini.name,
    'album': album.name,
    'playingRow': playingRow.name,
    'badge': badge.name,
    'lyricsLines': lyricsLines.name,
    'volumeSlider': volumeSlider.name,
    'background': background?.name,
    'tabBar': tabBar?.name,
    'visualizer': visualizer,
    'visualizerStyle': visualizerStyle.name,
    'videoSwitch': videoSwitch,
  };

  /// A saved preset of the user's own; a value an older or newer Riflay doesn't know falls back to the default.
  factory PlayerPreset.fromJson(Map<String, dynamic> j) {
    const d = PlayerPreset(name: '', note: '');
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) => values.asNameMap()[name] ?? fallback;
    T? maybe<T extends Enum>(List<T> values, Object? name) => values.asNameMap()[name];
    return PlayerPreset(
      name: j['name'] as String? ?? '',
      note: '',
      cover: pick(PlayerCover.values, j['cover'], d.cover),
      header: pick(PlayerHeader.values, j['header'], d.header),
      titleActions: pick(TitleActions.values, j['titleActions'], d.titleActions),
      progressBar: pick(ProgressBarStyle.values, j['progressBar'], d.progressBar),
      progressShape: pick(ProgressBarShape.values, j['progressShape'], d.progressShape),
      timeLeft: j['timeLeft'] as bool? ?? d.timeLeft,
      transport: pick(PlayerTransport.values, j['transport'], d.transport),
      volume: j['volume'] as bool? ?? d.volume,
      glassControls: j['glassControls'] as bool? ?? d.glassControls,
      glassTransport: j['glassTransport'] as bool?,
      glassSeekBar: j['glassSeekBar'] as bool?,
      glassVolume: j['glassVolume'] as bool?,
      bottomRow: pick(PlayerBottomRow.values, j['bottomRow'], d.bottomRow),
      lyrics: pick(LyricsLayout.values, j['lyrics'], d.lyrics),
      mini: pick(MiniPlayerStyle.values, j['mini'], d.mini),
      album: pick(AlbumHeaderStyle.values, j['album'], d.album),
      playingRow: pick(PlayingRowStyle.values, j['playingRow'], d.playingRow),
      badge: pick(QualityBadgePlace.values, j['badge'], d.badge),
      lyricsLines: pick(LyricsLines.values, j['lyricsLines'], d.lyricsLines),
      volumeSlider: pick(VolumeSliderShape.values, j['volumeSlider'], d.volumeSlider),
      background: maybe(NowPlayingBackground.values, j['background']),
      tabBar: maybe(TabBarStyle.values, j['tabBar']),
      visualizer: j['visualizer'] as bool? ?? d.visualizer,
      visualizerStyle: pick(VisualizerStyle.values, j['visualizerStyle'], d.visualizerStyle),
      videoSwitch: j['videoSwitch'] as bool? ?? d.videoSwitch,
      custom: true,
    );
  }

  /// [name] in place of this one's.
  PlayerPreset renamed(String name) => PlayerPreset.fromJson({...toJson(), 'name': name});

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
  final bool glassControls;

  /// Glass previous and next (`LayoutPrefs.glassTransport`, set with [glassControls]); the Pill's play button stays
  /// solid either way. Null leaves the switch as it is, as the other glass part switches survive presets.
  final bool? glassTransport;

  /// Glass seek bar and volume (`LayoutPrefs.glassSeekBar`, `glassVolume`); null leaves them as they are.
  final bool? glassSeekBar;
  final bool? glassVolume;
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

  /// Made by the user ([CustomPresets]), rather than one of Riflay's own.
  final bool custom;

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
    tabBar: TabBarStyle.capsule,
  );

  /// Stacked's player controls, with Liquid glass navigation instead of Capsule.
  static const liquidStacked = PlayerPreset(
    name: 'Liquid Stacked',
    note: 'Stacked, with Liquid Glass controls and glass tabs on phones',
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
    tabBar: TabBarStyle.glass,
    glassControls: true,
    // Glass previous and next beside the solid play pill.
    glassTransport: true,
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
    note: 'Kawaii, with Liquid Glass controls and glass tabs on phones',
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
    glassControls: true,
    // Only the buttons around the solid parts are glass: the seek bar, playback and volume stay plain.
    glassTransport: false,
    glassSeekBar: false,
    glassVolume: false,
  );

  static const all = [classic, stacked, liquidStacked, kawaii, liquidKawaii];

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
    differ(p.playerGlassControls, glassControls);
    if (glassTransport != null) differ(p.glassTransport, glassTransport!);
    if (glassSeekBar != null) differ(p.glassSeekBar, glassSeekBar!);
    if (glassVolume != null) differ(p.glassVolume, glassVolume!);
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
      p.playerGlassControls = glassControls;
      if (glassTransport != null) p.glassTransport = glassTransport!;
      if (glassSeekBar != null) p.glassSeekBar = glassSeekBar!;
      if (glassVolume != null) p.glassVolume = glassVolume!;
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
    ...CustomPresets.instance.presets,
  ]) {
    if (preset.matches(p)) return preset.name;
  }
  return null;
}

/// The presets the user made and named in Settings › Presets: the player as it was set up when saved.
class CustomPresets extends ChangeNotifier {
  CustomPresets._();
  static final instance = CustomPresets._();

  static const _key = 'presets.custom.v1';

  List<PlayerPreset> presets = const [];

  /// Riflay's own and the user's, by [name] (ignoring case); null when there is none.
  static PlayerPreset? named(String name) {
    final want = name.trim().toLowerCase();
    for (final p in [...PlayerPreset.all, ...instance.presets]) {
      if (p.name.toLowerCase() == want) return p;
    }
    return null;
  }

  /// Whether [name] is one of Riflay's own presets' (those can't be replaced).
  static bool isBuiltIn(String name) => PlayerPreset.all.any((p) => p.name.toLowerCase() == name.trim().toLowerCase());

  Future<void> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      presets = [for (final j in jsonDecode(raw) as List<dynamic>) PlayerPreset.fromJson(j as Map<String, dynamic>)]
          .where((p) => p.name.isNotEmpty)
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Custom presets not read: $e');
    }
  }

  Future<void> _save() async {
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_key, jsonEncode([for (final p in presets) p.toJson()]));
  }

  /// Saves the player as it is now under [name]; one of the user's own with that name is replaced in place.
  Future<PlayerPreset> saveCurrent(String name) async {
    final preset = PlayerPreset.fromCurrent(name.trim());
    final at = presets.indexWhere((p) => p.name.toLowerCase() == preset.name.toLowerCase());
    presets = [...presets];
    at < 0 ? presets.add(preset) : presets[at] = preset;
    await _save();
    return preset;
  }

  Future<void> rename(PlayerPreset preset, String name) async {
    presets = [for (final p in presets) p.name == preset.name ? p.renamed(name.trim()) : p];
    await _save();
  }

  Future<void> remove(PlayerPreset preset) async {
    presets = presets.where((p) => p.name != preset.name).toList();
    await _save();
  }
}
