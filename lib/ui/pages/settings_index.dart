import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../platform/features.dart';
import '../../platform/host.dart';
import '../../services/audio_engine.dart';
import '../../services/beta_features.dart';
import '../../services/device_setup.dart';
import '../../services/discord_presence.dart';
import '../../services/language.dart';
import '../../services/media_session.dart';
import '../../services/stay_awake.dart';
import '../../services/system_tray.dart';
import '../../services/ytdlp.dart';
import '../navigation.dart';
import '../shell_scope.dart';
import '../widgets/title_bar.dart' show hasNativeWindow;
import 'settings_page.dart';

/// Words in one language: a getter of [AppLocalizations], so the index can read every language, not only the one
/// shown.
typedef Words = String Function(AppLocalizations t);

/// A page of settings an option can sit on: a section of a group, or one of the pages straight under Settings.
enum SettingsPlace {
  playback(SettingsTopic.playback),
  dsp(SettingsTopic.dsp),
  output(SettingsTopic.advanced),
  appearance(SettingsTopic.appearance),
  layout(SettingsTopic.layout),
  library(SettingsTopic.library),
  downloads(SettingsTopic.downloads),
  history(SettingsTopic.history),
  backup(SettingsTopic.backup),
  account(SettingsTopic.account),
  scrobbling(SettingsTopic.scrobbling),
  integrations(SettingsTopic.integrations),
  extensions(SettingsTopic.extensions),
  power(null),
  about(null);

  const SettingsPlace(this.topic);

  /// The section this is, or null for Power & background and About.
  final SettingsTopic? topic;

  bool get available => topic?.available ?? (this != power || !Host.isWeb);

  String get label => switch (this) {
    power => tr.settingsPower,
    about => tr.about,
    _ => topic!.label,
  };

  /// "Look & feel › Layout", shown under a search result.
  String get trail => [?topic?.group.label, label].join(' › ');

  String get location => switch (this) {
    power => Locations.settingsTopic('power'),
    about => Locations.settingsTopic('about'),
    _ => topic!.location,
  };

  Widget get page => switch (this) {
    power => const SettingsPowerPage(),
    about => const SettingsAboutPage(),
    _ => SettingsTopicPage(section: topic!),
  };

  /// Opens this page, as its row on a Settings page does.
  void open(ShellScope shell) => shell.open(page, location: location);
}

/// What a [SettingPreview] shows: the real widgets the option changes, small (see `settings_preview.dart`).
enum SettingPreview { nowPlaying, lyrics, visualizer, cards, tabBar, desktopBar }

/// One option on a page of settings, as search finds it and as the page finds it again to scroll to.
///
/// Register a new option in [SettingsOptions.all] with the same words its row shows: the page needs no change.
class SettingsOption {
  const SettingsOption(
    this.id,
    this.place,
    this.title, {
    this.subtitle,
    this.find,
    this.locate,
    this.parent,
    this.preview,
    this.available,
  });

  /// Unique, stable: tests and the jump use it.
  final String id;
  final SettingsPlace place;

  /// The row's title, word for word as the row shows it.
  final Words title;

  /// The row's plain line, when it has a fixed one.
  final Words? subtitle;

  /// A few other words people might type for it, comma-separated.
  final Words? find;

  /// Text on the page that marks the row, when not [title] (a row without a fixed title).
  final Words? locate;

  /// The option shown in its place while this one is hidden (a part only shown once its switch is on).
  final String? parent;

  final SettingPreview? preview;

  /// Whether this build or device has the option at all; null for always.
  final bool Function()? available;

  bool get offered => place.available && (available?.call() ?? true);

  /// The words that mark its row on the page, in the language shown.
  String get marker => (locate ?? title)(tr);

  @override
  String toString() => 'SettingsOption($id)';
}

/// Every option search can find, in the order the pages show them.
abstract final class SettingsOptions {
  static SettingsOption? byId(String id) => _byId[id];
  static final _byId = {for (final o in all) o.id: o};

  static bool _native() => AudioEngine.supported;

  /// Power & background lists only Performance until keeping awake has started.
  static bool _awake() => StayAwake.instance != null;

  static final List<SettingsOption> all = [
    // Sound › Playback
    SettingsOption(
      'autoplay',
      .playback,
      (t) => t.autoplay,
      subtitle: (t) => t.autoplayKeepGoing,
      find: (t) => t.kwAutoplay,
    ),
    SettingsOption(
      'gapless',
      .playback,
      (t) => t.gaplessPlayback,
      subtitle: (t) => t.gaplessPlaybackSubtitle,
      find: (t) => t.kwGapless,
      available: _native,
    ),
    SettingsOption(
      'skipSilence',
      .playback,
      (t) => t.skipSilence,
      subtitle: (t) => t.skipSilenceSubtitle,
      find: (t) => t.kwSkipSilence,
      available: () => AudioEngine.hasSkipSilence,
    ),
    // Sound › Sound effects
    SettingsOption('equalizer', .dsp, (t) => t.equalizer, find: (t) => t.kwEqualizer),
    SettingsOption(
      'volumeLeveling',
      .dsp,
      (t) => t.volumeLeveling,
      subtitle: (t) => t.volumeLevelingSubtitle,
      find: (t) => t.kwVolumeLeveling,
      available: _native,
    ),
    SettingsOption(
      'crossfade',
      .dsp,
      (t) => t.crossfade,
      subtitle: (t) => t.crossfadeSubtitle,
      find: (t) => t.kwCrossfade,
      available: _native,
    ),
    SettingsOption(
      'fadeLength',
      .dsp,
      (t) => t.fadeLength,
      find: (t) => t.kwFadeLength,
      parent: 'crossfade',
      available: _native,
    ),
    SettingsOption(
      'skipForAlbums',
      .dsp,
      (t) => t.skipForAlbums,
      subtitle: (t) => t.skipForAlbumsSubtitle,
      parent: 'crossfade',
      available: _native,
    ),
    SettingsOption(
      'virtualSpeakers',
      .dsp,
      (t) => t.virtualSpeakers,
      subtitle: (t) => t.virtualSpeakersSubtitle,
      find: (t) => t.kwVirtualSpeakers,
      available: _native,
    ),
    SettingsOption(
      'virtualSpeakerLevel',
      .dsp,
      (t) => t.virtualSpeakerLevel,
      parent: 'virtualSpeakers',
      available: _native,
    ),
    SettingsOption('crossfeed', .dsp, (t) => t.headphoneCrossfeed, find: (t) => t.kwCrossfeed),
    SettingsOption('crossfeedSoundstage', .dsp, (t) => t.crossfeedSoundstage, parent: 'crossfeed'),
    SettingsOption('mono', .dsp, (t) => t.monoAudio, subtitle: (t) => t.monoAudioSubtitle, find: (t) => t.kwMono),
    SettingsOption(
      'audioPlugins',
      .dsp,
      (t) => t.audioPlugins,
      subtitle: (t) => t.audioPluginsSubtitle,
      find: (t) => t.kwAudioPlugins,
      available: () => _native() && AudioEngine.pluginBridge != null,
    ),
    SettingsOption(
      'roomCorrection',
      .dsp,
      (t) => t.roomCorrection,
      find: (t) => t.kwRoomCorrection,
      available: _native,
    ),
    SettingsOption(
      'roomCorrectionHeadroom',
      .dsp,
      (t) => t.roomCorrectionHeadroom,
      parent: 'roomCorrection',
      available: _native,
    ),
    SettingsOption(
      'dspSignalPath',
      .dsp,
      (t) => t.signalPath,
      subtitle: (t) => t.signalPathSubtitle,
      find: (t) => t.kwSignalPath,
      available: _native,
    ),
    // Sound › Output & quality
    SettingsOption(
      'output',
      .output,
      (t) => t.output,
      find: (t) => t.kwOutputDevice,
      available: () => AudioEngine.hasRoutePicker,
    ),
    SettingsOption(
      'outputDevice',
      .output,
      (t) => t.outputDevice,
      find: (t) => t.kwOutputDevice,
      available: () => AudioEngine.hasOutputChoice || Host.isAndroid,
    ),
    SettingsOption('bitPerfect', .output, (t) => t.bitPerfectMode, find: (t) => t.kwBitPerfect),
    SettingsOption(
      'directUsb',
      .output,
      (t) => t.directUsbBeta,
      find: (t) => t.kwDirectUsb,
      available: () => Host.isAndroid,
    ),
    SettingsOption('nativeDsd', .output, (t) => t.nativeDsd, find: (t) => t.kwNativeDsd, parent: 'bitPerfect'),
    SettingsOption(
      'exclusiveMode',
      .output,
      (t) => t.exclusiveMode,
      find: (t) => t.kwExclusiveMode,
      available: () => AudioEngine.hasExclusiveMode,
    ),
    SettingsOption('sampleRate', .output, (t) => t.outputSampleRate, find: (t) => t.kwSampleRate),
    SettingsOption(
      'hqResampler',
      .output,
      (t) => t.hqResampler,
      subtitle: (t) => t.hqResamplerSubtitle,
      find: (t) => t.kwSampleRate,
    ),
    SettingsOption('buffer', .output, (t) => t.buffer, subtitle: (t) => t.bufferSubtitle, find: (t) => t.kwBuffer),
    SettingsOption(
      'outputSignalPath',
      .output,
      (t) => t.signalPath,
      subtitle: (t) => t.signalPathSubtitleExact,
      find: (t) => t.kwSignalPath,
    ),
    // Look & feel › Appearance
    SettingsOption(
      'language',
      .appearance,
      (t) => t.language,
      subtitle: (t) => t.languageSubtitle,
      find: (t) => t.kwLanguage,
    ),
    SettingsOption('theme', .appearance, (t) => t.theme, find: (t) => t.kwTheme),
    SettingsOption(
      'matugen',
      .appearance,
      (t) => t.matugenColors,
      find: (t) => t.kwTheme,
      parent: 'theme',
      available: () => Host.isLinux,
    ),
    SettingsOption(
      'backgroundColour',
      .appearance,
      (t) => t.backgroundColour,
      subtitle: (t) => t.backgroundColourSubtitle,
      find: (t) => t.kwColours,
      parent: 'theme',
    ),
    SettingsOption('textColour', .appearance, (t) => t.textColour, find: (t) => t.kwColours, parent: 'theme'),
    SettingsOption(
      'mode',
      .appearance,
      (t) => t.mode,
      subtitle: (t) => t.modeSubtitle,
      find: (t) => t.kwMode,
      parent: 'theme',
    ),
    SettingsOption('accent', .appearance, (t) => t.accentColour, find: (t) => t.kwColours, parent: 'theme'),
    SettingsOption(
      'coverColours',
      .appearance,
      (t) => t.coloursFromCoverArt,
      find: (t) => t.kwCoverColours,
      parent: 'theme',
    ),
    SettingsOption(
      'colourStrength',
      .appearance,
      (t) => t.colourStrength,
      subtitle: (t) => t.colourStrengthSubtitle,
      find: (t) => t.kwCoverColours,
      parent: 'coverColours',
    ),
    SettingsOption(
      'highContrast',
      .appearance,
      (t) => t.highContrast,
      subtitle: (t) => t.highContrastSubtitle,
      find: (t) => t.kwHighContrast,
    ),
    SettingsOption('textSize', .appearance, (t) => t.textSize, find: (t) => t.kwTextSize),
    SettingsOption('font', .appearance, (t) => t.font, find: (t) => t.kwFont),
    SettingsOption(
      'nowPlayingBackground',
      .appearance,
      (t) => t.nowPlayingBackground,
      subtitle: (t) => t.nowPlayingBackgroundSubtitle,
      find: (t) => t.kwPlayerBackground,
      preview: .nowPlaying,
    ),
    SettingsOption(
      'frostedGlass',
      .appearance,
      (t) => t.frostedGlass,
      subtitle: (t) => t.frostedGlassSubtitle,
      find: (t) => t.kwFrostedGlass,
    ),
    SettingsOption(
      'blurStrength',
      .appearance,
      (t) => t.blurStrength,
      find: (t) => t.kwFrostedGlass,
      parent: 'frostedGlass',
    ),
    SettingsOption(
      'componentOpacity',
      .appearance,
      (t) => t.componentOpacity,
      subtitle: (t) => t.componentOpacitySubtitle,
      find: (t) => t.kwOpacity,
      parent: 'frostedGlass',
    ),
    SettingsOption(
      'backgroundOpacity',
      .appearance,
      (t) => t.backgroundOpacity,
      find: (t) => t.kwOpacity,
      parent: 'frostedGlass',
    ),
    // Look & feel › Layout
    SettingsOption('presets', .layout, (t) => t.presets, find: (t) => t.kwPresets),
    SettingsOption(
      'cover',
      .layout,
      (t) => t.cover,
      subtitle: (t) => t.coverSubtitle,
      find: (t) => t.kwCover,
      preview: .nowPlaying,
    ),
    SettingsOption(
      'phoneCover',
      .layout,
      (t) => t.coverSizeOnPhones,
      subtitle: (t) => t.coverSizeOnPhonesSubtitle,
      find: (t) => t.kwCover,
      preview: .nowPlaying,
    ),
    SettingsOption(
      'playerHeader',
      .layout,
      (t) => t.topOfPlayer,
      subtitle: (t) => t.topOfPlayerSubtitle,
      find: (t) => t.kwPlayerHeader,
      preview: .nowPlaying,
    ),
    SettingsOption(
      'titleActions',
      .layout,
      (t) => t.buttonsByTitle,
      subtitle: (t) => t.buttonsByTitleSubtitle,
      find: (t) => t.kwTitleButtons,
      preview: .nowPlaying,
    ),
    SettingsOption(
      'showQualityBadge',
      .layout,
      (t) => t.showSoundQuality,
      subtitle: (t) => t.showSoundQualitySubtitle,
      find: (t) => t.kwQualityBadge,
      preview: .nowPlaying,
    ),
    SettingsOption(
      'videoSwitch',
      .layout,
      (t) => t.songVideoSwitch,
      subtitle: (t) => t.songVideoSwitchSubtitle,
      find: (t) => t.kwMusicVideo,
    ),
    SettingsOption(
      'qualityBadgePlace',
      .layout,
      (t) => t.qualityBadge,
      subtitle: (t) => t.qualityBadgeSubtitle,
      find: (t) => t.kwQualityBadge,
      preview: .nowPlaying,
    ),
    SettingsOption(
      'playerBackground',
      .layout,
      (t) => t.background,
      find: (t) => t.kwPlayerBackground,
      preview: .nowPlaying,
    ),
    SettingsOption(
      'videoMode',
      .layout,
      (t) => t.videoMode,
      subtitle: (t) => t.videoModeSubtitle,
      find: (t) => t.kwMusicVideo,
      available: () => BetaFeature.videoMode.available,
    ),
    SettingsOption(
      'videoDecoding',
      .layout,
      (t) => t.videoDecoding,
      find: (t) => t.kwVideoDecoding,
      available: () => BetaFeature.videoMode.available,
    ),
    SettingsOption(
      'glassControls',
      .layout,
      (t) => t.liquidGlassControls,
      subtitle: (t) => t.liquidGlassControlsSubtitle,
      find: (t) => t.kwLiquidGlass,
      preview: .nowPlaying,
    ),
    SettingsOption(
      'glassSeekBar',
      .layout,
      (t) => t.glassSeekBar,
      find: (t) => t.kwLiquidGlass,
      parent: 'glassControls',
      preview: .nowPlaying,
    ),
    SettingsOption(
      'glassTransport',
      .layout,
      (t) => t.glassTransport,
      subtitle: (t) => t.glassTransportSubtitle,
      find: (t) => t.kwLiquidGlass,
      parent: 'glassControls',
      preview: .nowPlaying,
    ),
    SettingsOption(
      'glassVolume',
      .layout,
      (t) => t.glassVolume,
      find: (t) => t.kwLiquidGlass,
      parent: 'glassControls',
      preview: .nowPlaying,
    ),
    SettingsOption('progressShape', .layout, (t) => t.progressBarShape, find: (t) => t.kwSeekBar, preview: .nowPlaying),
    SettingsOption(
      'progressBar',
      .layout,
      (t) => t.progressBar,
      subtitle: (t) => t.progressBarSubtitle,
      find: (t) => t.kwSeekBar,
      preview: .nowPlaying,
    ),
    SettingsOption(
      'showTimeLeft',
      .layout,
      (t) => t.showTimeLeft,
      subtitle: (t) => t.showTimeLeftSubtitle,
      find: (t) => t.kwTimeLeft,
      preview: .nowPlaying,
    ),
    SettingsOption(
      'transport',
      .layout,
      (t) => t.controls,
      subtitle: (t) => t.controlsSubtitle,
      find: (t) => t.kwTransport,
      preview: .nowPlaying,
    ),
    SettingsOption(
      'playButton',
      .layout,
      (t) => t.playButton,
      subtitle: (t) => t.playButtonSubtitle,
      find: (t) => t.kwTransport,
      preview: .nowPlaying,
    ),
    SettingsOption(
      'volumeRow',
      .layout,
      (t) => t.volumeSlider,
      subtitle: (t) => t.volumeSliderSubtitle,
      find: (t) => t.kwVolumeSlider,
      preview: .nowPlaying,
    ),
    SettingsOption(
      'sliderLook',
      .layout,
      (t) => t.sliderLook,
      subtitle: (t) => t.sliderLookSubtitle,
      find: (t) => t.kwVolumeSlider,
      preview: .nowPlaying,
    ),
    SettingsOption(
      'bottomRow',
      .layout,
      (t) => t.bottomButtons,
      subtitle: (t) => t.bottomButtonsSubtitle,
      find: (t) => t.kwBottomButtons,
      preview: .nowPlaying,
    ),
    SettingsOption(
      'lyricsLayout',
      .layout,
      (t) => t.lyricsPage,
      subtitle: (t) => t.lyricsPageSubtitle,
      find: (t) => t.kwLyrics,
      preview: .lyrics,
    ),
    SettingsOption(
      'lyricsLines',
      .layout,
      (t) => t.linesShown,
      subtitle: (t) => t.linesShownSubtitle,
      find: (t) => t.kwLyrics,
      preview: .lyrics,
    ),
    SettingsOption(
      'lyricsSync',
      .layout,
      (t) => t.sync,
      subtitle: (t) => t.syncSubtitle,
      find: (t) => t.kwKaraoke,
      preview: .lyrics,
    ),
    SettingsOption(
      'lyricsSize',
      .layout,
      (t) => t.textSize,
      subtitle: (t) => t.lyricsTextSizeSubtitle,
      find: (t) => t.kwLyricsSize,
      preview: .lyrics,
    ),
    SettingsOption(
      'lyricsAlign',
      .layout,
      (t) => t.alignment,
      subtitle: (t) => t.alignmentSubtitle,
      find: (t) => t.kwLyricsAlign,
      preview: .lyrics,
    ),
    SettingsOption(
      'dimUnsung',
      .layout,
      (t) => t.dimUnsung,
      subtitle: (t) => t.dimUnsungSubtitle,
      find: (t) => t.kwKaraoke,
      preview: .lyrics,
    ),
    SettingsOption(
      'highlightLine',
      .layout,
      (t) => t.highlightLyricLine,
      subtitle: (t) => t.highlightLyricLineSubtitle,
      find: (t) => t.kwLyrics,
      preview: .lyrics,
    ),
    SettingsOption(
      'lockScreenLyrics',
      .layout,
      (t) => t.lockScreenLyrics,
      subtitle: (t) => t.lockScreenLyricsSubtitle,
      find: (t) => t.kwLyrics,
      available: () => MediaSession.lyricsSupported,
    ),
    SettingsOption(
      'visualizer',
      .layout,
      (t) => t.audioVisualizer,
      find: (t) => t.kwVisualizer,
      preview: .visualizer,
      available: () => Features.audioVisualizer,
    ),
    SettingsOption(
      'visualizerStyle',
      .layout,
      (t) => t.visualizerStyle,
      find: (t) => t.kwVisualizer,
      parent: 'visualizer',
      preview: .visualizer,
      available: () => Features.audioVisualizer,
    ),
    SettingsOption(
      'visualizerRadius',
      .layout,
      (t) => t.radiusMovement,
      find: (t) => t.kwVisualizer,
      parent: 'visualizerStyle',
      preview: .visualizer,
      available: () => Features.audioVisualizer,
    ),
    SettingsOption(
      'visualizerThickness',
      .layout,
      (t) => t.lineThickness,
      find: (t) => t.kwVisualizer,
      parent: 'visualizerStyle',
      preview: .visualizer,
      available: () => Features.audioVisualizer,
    ),
    SettingsOption(
      'albumHeader',
      .layout,
      (t) => t.albumPlaylistTop,
      subtitle: (t) => t.albumPlaylistTopSubtitle,
      find: (t) => t.kwAlbumHeader,
    ),
    SettingsOption(
      'playingRow',
      .layout,
      (t) => t.songThatIsPlaying,
      subtitle: (t) => t.songThatIsPlayingSubtitle,
      find: (t) => t.kwPlayingRow,
    ),
    SettingsOption(
      'homeSections',
      .layout,
      (t) => t.homeSectionsOption,
      subtitle: (t) => t.dragToReorderSections,
      find: (t) => t.kwHomeSections,
      locate: (t) => t.dragToReorderSections,
    ),
    SettingsOption(
      'miniPlayer',
      .layout,
      (t) => t.miniPlayer,
      subtitle: (t) => t.miniPlayerSubtitle,
      find: (t) => t.kwMiniPlayer,
      preview: .tabBar,
    ),
    SettingsOption(
      'tabBar',
      .layout,
      (t) => t.tabBarOnPhones,
      subtitle: (t) => t.tabBarOnPhonesSubtitle,
      find: (t) => t.kwTabBar,
      preview: .tabBar,
    ),
    SettingsOption(
      'desktopBar',
      .layout,
      (t) => t.desktopPlayerBar,
      subtitle: (t) => t.desktopPlayerBarSubtitle,
      find: (t) => t.kwDesktopBar,
      preview: .desktopBar,
    ),
    SettingsOption(
      'corners',
      .layout,
      (t) => t.corners,
      subtitle: (t) => t.cornersSubtitle,
      find: (t) => t.kwCorners,
      preview: .cards,
    ),
    SettingsOption(
      'density',
      .layout,
      (t) => t.spacing,
      subtitle: (t) => t.spacingSubtitle,
      find: (t) => t.kwDensity,
      preview: .cards,
    ),
    SettingsOption(
      'coverSize',
      .layout,
      (t) => t.coverSizeInGrids,
      subtitle: (t) => t.coverSizeInGridsSubtitle,
      find: (t) => t.kwCoverSize,
      preview: .cards,
    ),
    SettingsOption(
      'pageMotion',
      .layout,
      (t) => t.transitionStyle,
      subtitle: (t) => t.transitionStyleSubtitle,
      find: (t) => t.kwMotion,
    ),
    SettingsOption(
      'pageSpeed',
      .layout,
      (t) => t.transitionSpeed,
      subtitle: (t) => t.transitionSpeedSubtitle,
      find: (t) => t.kwMotion,
    ),
    SettingsOption(
      'motion',
      .layout,
      (t) => t.animations,
      subtitle: (t) => t.animationsSubtitle,
      find: (t) => t.kwMotion,
    ),
    SettingsOption(
      'windowButtons',
      .layout,
      (t) => t.windowButtons,
      subtitle: (t) => t.windowButtonsSubtitle,
      find: (t) => t.kwWindowButtons,
      available: () => hasNativeWindow && !Host.isMacOS,
    ),
    // Power & background
    SettingsOption('performance', .power, (t) => t.performance, find: (t) => t.kwPerformance, preview: .nowPlaying),
    SettingsOption(
      'deviceSetup',
      .power,
      (t) => t.deviceSetupAgain,
      subtitle: (t) => t.deviceSetupAgainNote,
      find: (t) => t.kwPerformance,
      available: () => DeviceSetup.offered,
    ),
    SettingsOption('keepScreenOn', .power, (t) => t.keepScreenOn, find: (t) => t.kwScreen, available: _awake),
    SettingsOption(
      'dontSleep',
      .power,
      (t) => t.dontSleepWhilePlaying,
      subtitle: (t) => t.dontSleepSubtitle,
      find: (t) => t.kwSleep,
      available: () => _awake() && StayAwake.isDesktop,
    ),
    SettingsOption(
      'closeToTray',
      .power,
      (t) => t.closeToTray,
      subtitle: (t) => t.closeToTraySubtitle,
      find: (t) => t.kwTray,
      available: () => _awake() && SystemTray.offered,
    ),
    SettingsOption(
      'keepPlayingScreenOff',
      .power,
      (t) => t.keepPlayingScreenOff,
      find: (t) => t.kwBattery,
      available: () => _awake() && BatteryExemption.supported,
    ),
    // Library & downloads
    SettingsOption('keepLibrary', .library, (t) => t.keepLibraryUpToDate, find: (t) => t.kwMusicFolders),
    SettingsOption('checkNow', .library, (t) => t.checkNow, find: (t) => t.kwMusicFolders),
    SettingsOption(
      'duplicates',
      .library,
      (t) => t.findDuplicates,
      subtitle: (t) => t.findDuplicatesSubtitle,
      find: (t) => t.kwDuplicates,
    ),
    SettingsOption('saveAs', .downloads, (t) => t.saveAs, find: (t) => t.kwDownloadFormat),
    SettingsOption('videoFormat', .downloads, (t) => t.videoFormat, find: (t) => t.kwDownloadFormat, parent: 'saveAs'),
    SettingsOption('format', .downloads, (t) => t.format, find: (t) => t.kwDownloadFormat),
    SettingsOption(
      'bitDepth',
      .downloads,
      (t) => t.bitDepthSampleRate,
      find: (t) => t.kwDownloadQuality,
      parent: 'format',
    ),
    SettingsOption('bitrate', .downloads, (t) => t.bitrate, find: (t) => t.kwDownloadQuality, parent: 'format'),
    SettingsOption(
      'askEveryTime',
      .downloads,
      (t) => t.askEveryTime,
      subtitle: (t) => t.askEveryTimeSubtitle,
      find: (t) => t.kwDownloadFormat,
    ),
    SettingsOption(
      'mobileData',
      .downloads,
      (t) => t.downloadOverMobile,
      find: (t) => t.kwMobileData,
      available: () => Host.isAndroid || Host.isIOS,
    ),
    SettingsOption('downloadsFolder', .downloads, (t) => t.downloadsFolder, find: (t) => t.kwDownloadsFolder),
    SettingsOption('ytDlp', .downloads, (t) => t.ytDlp, find: (t) => t.kwYtDlp, available: () => YtDlp.supported),
    SettingsOption(
      'keepHistory',
      .history,
      (t) => t.keepHistory,
      subtitle: (t) => t.keepHistorySubtitle,
      find: (t) => t.kwHistory,
    ),
    SettingsOption(
      'wrapNotification',
      .history,
      (t) => t.wrapNotification,
      subtitle: (t) => t.wrapNotificationSubtitle,
      find: (t) => t.kwWrap,
      available: () => Features.systemNotifications,
    ),
    SettingsOption(
      'listeningStats',
      .history,
      (t) => t.yourListeningStats,
      subtitle: (t) => t.yourListeningStatsSubtitle,
      find: (t) => t.kwWrap,
    ),
    SettingsOption('clearHistory', .history, (t) => t.clearHistory, find: (t) => t.kwHistory),
    SettingsOption(
      'saveBackup',
      .backup,
      (t) => t.saveABackup,
      subtitle: (t) => t.saveABackupSubtitle,
      find: (t) => t.kwBackup,
    ),
    SettingsOption(
      'restoreBackup',
      .backup,
      (t) => t.restoreABackup,
      subtitle: (t) => t.restoreABackupSubtitle,
      find: (t) => t.kwBackup,
    ),
    // Accounts & services
    SettingsOption(
      'youtubeMusic',
      .account,
      (t) => t.topicAccount,
      subtitle: (t) => t.topicAccountSummary,
      find: (t) => t.kwYoutubeAccount,
      locate: (t) => t.signInWithGoogle,
    ),
    SettingsOption(
      'ytHistory',
      .account,
      (t) => t.addToYtHistory,
      subtitle: (t) => t.addToYtHistorySubtitle,
      find: (t) => t.kwYoutubeAccount,
      parent: 'youtubeMusic',
    ),
    SettingsOption(
      'scrobbling',
      .scrobbling,
      (t) => t.topicScrobbling,
      subtitle: (t) => t.topicScrobblingSummary,
      find: (t) => t.kwScrobbling,
      locate: (t) => t.scrobbleBody,
    ),
    SettingsOption(
      'musixmatch',
      .integrations,
      (t) => t.musixmatchLyrics,
      subtitle: (t) => t.musixmatchLyricsSubtitle,
      find: (t) => t.kwLyricsServices,
    ),
    SettingsOption(
      'discord',
      .integrations,
      (t) => t.discordRichPresence,
      subtitle: (t) => t.discordRichPresenceSubtitle,
      find: (t) => t.kwDiscord,
      available: () => DiscordPresence.supported,
    ),
    SettingsOption(
      'discordCover',
      .integrations,
      (t) => t.discordSongCover,
      find: (t) => t.kwDiscord,
      parent: 'discord',
      available: () => DiscordPresence.supported,
    ),
    SettingsOption(
      'discordTime',
      .integrations,
      (t) => t.discordTime,
      find: (t) => t.kwDiscord,
      parent: 'discord',
      available: () => DiscordPresence.supported,
    ),
    SettingsOption(
      'discordSongInList',
      .integrations,
      (t) => t.discordSongInList,
      find: (t) => t.kwDiscord,
      parent: 'discord',
      available: () => DiscordPresence.supported,
    ),
    SettingsOption(
      'discordListenButton',
      .integrations,
      (t) => t.discordListenButton,
      find: (t) => t.kwDiscord,
      parent: 'discord',
      available: () => DiscordPresence.supported,
    ),
    SettingsOption(
      'discordAppButton',
      .integrations,
      (t) => t.discordAppButton,
      find: (t) => t.kwDiscord,
      parent: 'discord',
      available: () => DiscordPresence.supported,
    ),
    SettingsOption(
      'discordWhilePaused',
      .integrations,
      (t) => t.discordWhilePaused,
      find: (t) => t.kwDiscord,
      parent: 'discord',
      available: () => DiscordPresence.supported,
    ),
    SettingsOption(
      'discordQuality',
      .integrations,
      (t) => t.discordShowQuality,
      find: (t) => t.kwDiscord,
      parent: 'discord',
      available: () => DiscordPresence.supported,
    ),
    SettingsOption('betterLyrics', .integrations, (t) => t.betterLyricsKey, find: (t) => t.kwLyricsServices),
    SettingsOption('repositories', .extensions, (t) => t.repositories, find: (t) => t.kwExtensions),
    // About
    SettingsOption(
      'updates',
      .about,
      (t) => t.checkForUpdates,
      find: (t) => t.kwUpdates,
      available: () => Features.appUpdates,
    ),
    SettingsOption(
      'deleteExecutables',
      .about,
      (t) => t.deleteExecutables,
      subtitle: (t) => t.downloadedToolsSubtitle,
      find: (t) => t.kwYtDlp,
      available: () => Features.downloadedTools,
    ),
    SettingsOption('version', .about, (t) => t.version, find: (t) => t.kwVersion),
    SettingsOption('whatsNew', .about, (t) => t.whatsNew, find: (t) => t.kwVersion),
    SettingsOption('reportProblem', .about, (t) => t.reportProblem, find: (t) => t.kwVersion),
    SettingsOption('supportArtists', .about, (t) => t.supportArtists, find: (t) => t.kwVersion),
    SettingsOption('supportRiflay', .about, (t) => t.supportRiflay, find: (t) => t.kwVersion),
    SettingsOption('sourceCode', .about, (t) => t.sourceCode, find: (t) => t.kwVersion),
    SettingsOption('licence', .about, (t) => t.licence, find: (t) => t.kwVersion),
    SettingsOption('licences', .about, (t) => t.openSourceLicences, find: (t) => t.kwVersion),
  ];

  /// Options on [place] this device has, that show a preview.
  static Iterable<SettingsOption> previewedOn(SettingsPlace place) =>
      all.where((o) => o.place == place && o.preview != null && o.offered);
}

/// One search result: the option, and how well it matched.
typedef SettingsHit = ({SettingsOption option, int score});

/// Lower case, without the accents a person may leave out ("Rosé", "café").
String _fold(String s) {
  const from = 'àáâäãåèéêëìíîïòóôöõùúûüñç', to = 'aaaaaaeeeeiiiiooooouuuunc';
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    b.write(i < 0 ? ch : to[i]);
  }
  return b.toString();
}

/// Every language, looked up once: an option is found by its words in any of them (an Indonesian speaker typing
/// "equalizer", a Japanese one typing "lyrics").
final _languages = [for (final l in AppLocalizations.supportedLocales) lookupAppLocalizations(l)];

/// The options whose words match [query], best first: the title in the language shown, then the other words for
/// it, the line under it and the page it is on, then the same in the other languages.
List<SettingsOption> searchSettings(String query) {
  final words = _fold(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  final whole = words.join(' ');
  final shown = tr;
  final hits = <SettingsHit>[];
  for (final o in SettingsOptions.all) {
    if (!o.offered) continue;
    var best = 0;
    for (final t in [
      shown,
      for (final l in _languages)
        if (l.localeName != shown.localeName) l,
    ]) {
      // The language shown counts for more than another.
      final weight = identical(t, shown) ? 2 : 1;
      final title = _fold(o.title(t));
      final rest = _fold([o.find?.call(t), o.subtitle?.call(t), o.place.topic?.label].nonNulls.join(' '));
      final int score;
      if (title.startsWith(whole)) {
        score = 50;
      } else if (title.contains(whole)) {
        score = 40;
      } else if (words.every(title.contains)) {
        score = 30;
      } else if (words.every((w) => title.contains(w) || rest.contains(w))) {
        score = 10;
      } else {
        continue;
      }
      if (score * weight > best) best = score * weight;
    }
    if (best > 0) hits.add((option: o, score: best));
  }
  // Stable: equal scores keep the pages' order.
  final ranked = [for (final (i, h) in hits.indexed) (i, h)]
    ..sort((a, b) => b.$2.score != a.$2.score ? b.$2.score - a.$2.score : a.$1 - b.$1);
  return [for (final (_, h) in ranked) h.option];
}
