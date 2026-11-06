import 'package:flutter/material.dart';

import '../../platform/features.dart';
import '../../services/appearance.dart';
import '../../services/layout_prefs.dart';
import '../../services/media_session.dart';
import '../../services/player_presets.dart';
import '../../services/beta_features.dart';
import '../../services/video_mode.dart';
import '../theme.dart';
import '../widgets/title_bar.dart' show hasNativeWindow;
import '../../platform/host.dart';
import 'player_presets_page.dart';
import 'sound_settings.dart';
import '../widgets/menus.dart';
import '../player_scope.dart';
import '../widgets/audio_reactive_view.dart';
import '../../services/language.dart';

/// Settings › Look & feel › Layout: corners, density, cover size, Home's sections, what the
/// player shows, lyrics and motion. Every default is how the app has always looked.
class LayoutSettings extends StatelessWidget {
  const LayoutSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPrefs.instance;
    final muted = settingsMuted(context);
    return ListenableBuilder(
      listenable: Listenable.merge([p, BetaFeatures.instance, Appearance.instance]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(tr.presets, hint: 'A whole look in one tap. Every part below can still be changed on its own'),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.auto_awesome_mosaic_rounded),
                title: Text(tr.presets),
                subtitle: Text(
                  playerPresetName() == null ? tr.custom : tr.matchesPreset('${playerPresetName()}'),
                  style: muted,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PlayerPresetsPage())),
              ),
            ],
          ),
          _Header(tr.nowPlayingTitle, hint: tr.fullScreenPlayerHint),
          SettingsCard(
            children: [
              SettingTile(
                icon: Icons.wallpaper_rounded,
                title: Text(tr.cover),
                subtitle: Text(tr.coverSubtitle, style: muted),
                control: OptionPicker<PlayerCover>(
                  value: p.playerCover,
                  onChanged: p.setPlayerCover,
                  options: [for (final v in PlayerCover.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.fit_screen_rounded,
                title: Text(tr.coverSizeOnPhones),
                subtitle: Text(tr.coverSizeOnPhonesSubtitle, style: muted),
                control: OptionPicker<PhoneCoverSize>(
                  value: p.phoneCover,
                  onChanged: p.setPhoneCover,
                  options: [for (final v in PhoneCoverSize.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.vertical_align_top_rounded,
                title: Text(tr.topOfPlayer),
                subtitle: Text(tr.topOfPlayerSubtitle, style: muted),
                control: OptionPicker<PlayerHeader>(
                  value: p.playerHeader,
                  onChanged: p.setPlayerHeader,
                  options: [for (final v in PlayerHeader.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.smart_button_rounded,
                title: Text(tr.buttonsByTitle),
                subtitle: Text(tr.buttonsByTitleSubtitle, style: muted),
                control: OptionPicker<TitleActions>(
                  value: p.titleActions,
                  onChanged: p.setTitleActions,
                  options: [for (final v in TitleActions.values) (v, v.label)],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.high_quality_outlined),
                title: Text(tr.showSoundQuality),
                subtitle: Text(tr.showSoundQualitySubtitle, style: muted),
                value: p.showQualityBadge,
                onChanged: p.setShowQualityBadge,
              ),
              SettingTile(
                icon: Icons.music_video_outlined,
                title: Text(tr.songVideoSwitch),
                subtitle: Text(tr.songVideoSwitchSubtitle, style: muted),
                // Not On / Off: even "on", it follows the song (nothing to switch to without a video).
                control: OptionPicker<bool>(
                  value: p.showVideoSwitch,
                  onChanged: p.setShowVideoSwitch,
                  options: [(true, tr.adaptive), (false, tr.off)],
                ),
              ),
              SettingTile(
                icon: Icons.high_quality_outlined,
                title: Text(tr.qualityBadge),
                subtitle: Text(tr.qualityBadgeSubtitle, style: muted),
                control: OptionPicker<QualityBadgePlace>(
                  value: p.qualityBadgePlace,
                  onChanged: p.setQualityBadgePlace,
                  options: [for (final v in QualityBadgePlace.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.wallpaper_rounded,
                title: Text(tr.background),
                subtitle: Text(Appearance.instance.nowPlaying.hint ?? tr.backgroundSubtitle, style: muted),
                control: OptionPicker<NowPlayingBackground>(
                  value: Appearance.instance.nowPlaying,
                  onChanged: Appearance.instance.setNowPlaying,
                  options: [for (final v in NowPlayingBackground.values) (v, v.label)],
                ),
              ),
              if (BetaFeature.videoMode.available) ...[
                SwitchListTile(
                  title: Text(tr.videoMode),
                  subtitle: Text(tr.videoModeSubtitle),
                  value: BetaFeatures.instance.isOn(BetaFeature.videoMode),
                  onChanged: (value) => BetaFeatures.instance.set(BetaFeature.videoMode, value),
                ),
                ListenableBuilder(
                  listenable: VideoMode.instance,
                  builder: (context, _) {
                    final now = VideoMode.instance.decoderInUse;
                    return SettingTile(
                      icon: Icons.memory_rounded,
                      title: Text(tr.videoDecoding),
                      subtitle: Text(
                        [
                          p.videoDecoder.note,
                          if (now != null) tr.decoderNow(now == 'no' ? tr.decoderNowCpu : tr.decoderNowGpu(now)),
                        ].join('. '),
                        style: muted,
                      ),
                      control: OptionPicker<VideoDecoder>(
                        value: p.videoDecoder,
                        onChanged: p.setVideoDecoder,
                        options: [for (final v in VideoDecoder.values) (v, v.label)],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
          _Header(tr.playbackControls, hint: tr.playbackControlsHint),
          SettingsCard(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.blur_on_rounded),
                title: Text(tr.liquidGlassControls),
                subtitle: Text(tr.liquidGlassControlsSubtitle, style: muted),
                value: p.playerGlassControls,
                onChanged: p.setPlayerGlassControls,
              ),
              // Which solid parts glass reaches too; only while the controls are glass at all.
              if (p.playerGlassControls) ...[
                SwitchListTile(
                  secondary: const Icon(Icons.linear_scale_rounded),
                  title: Text(tr.glassSeekBar),
                  value: p.glassSeekBar,
                  onChanged: p.setGlassSeekBar,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.play_circle_outline_rounded),
                  title: Text(tr.glassTransport),
                  subtitle: Text(tr.glassTransportSubtitle, style: muted),
                  value: p.glassTransport,
                  onChanged: p.setGlassTransport,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up_rounded),
                  title: Text(tr.glassVolume),
                  value: p.glassVolume,
                  onChanged: p.setGlassVolume,
                ),
              ],
              SettingTile(
                icon: Icons.waves_rounded,
                title: Text(tr.progressBarShape),
                subtitle: Text(
                  'Wavy curves the part played. Pill is a thick bar with a tall handle. Thin line is flat, with no handle until you drag',
                  style: muted,
                ),
                control: OptionPicker<ProgressBarShape>(
                  value: p.progressShape,
                  onChanged: p.setProgressShape,
                  options: [for (final v in ProgressBarShape.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.linear_scale_rounded,
                title: Text(tr.progressBar),
                subtitle: Text(tr.progressBarSubtitle, style: muted),
                control: OptionPicker<ProgressBarStyle>(
                  value: p.progressBar,
                  onChanged: p.setProgressBar,
                  options: [for (final v in ProgressBarStyle.values) (v, v.label)],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.timelapse_rounded),
                title: Text(tr.showTimeLeft),
                subtitle: Text(tr.showTimeLeftSubtitle, style: muted),
                value: p.showTimeLeft,
                onChanged: p.setShowTimeLeft,
              ),
              SettingTile(
                icon: Icons.play_circle_outline_rounded,
                title: Text(tr.controls),
                subtitle: Text(tr.controlsSubtitle, style: muted),
                control: OptionPicker<PlayerTransport>(
                  value: p.transport,
                  onChanged: p.setTransport,
                  options: [for (final v in PlayerTransport.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.play_circle_outline_rounded,
                title: Text(tr.playButton),
                subtitle: Text(tr.playButtonSubtitle, style: muted),
                control: OptionPicker<PlayButtonShape>(
                  value: p.playButton,
                  onChanged: p.setPlayButton,
                  options: [for (final v in PlayButtonShape.values) (v, v.label)],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.volume_up_rounded),
                title: Text(tr.volumeSlider),
                subtitle: Text(tr.volumeSliderSubtitle, style: muted),
                value: p.showVolumeRow,
                onChanged: p.setShowVolumeRow,
              ),
              SettingTile(
                icon: Icons.tune_rounded,
                title: Text(tr.sliderLook),
                subtitle: Text(tr.sliderLookSubtitle, style: muted),
                control: OptionPicker<VolumeSliderShape>(
                  value: p.volumeSlider,
                  onChanged: p.setVolumeSlider,
                  options: [for (final v in VolumeSliderShape.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.view_week_rounded,
                title: Text(tr.bottomButtons),
                subtitle: Text(tr.bottomButtonsSubtitle, style: muted),
                control: OptionPicker<PlayerBottomRow>(
                  value: p.bottomRow,
                  onChanged: p.setBottomRow,
                  options: [for (final v in PlayerBottomRow.values) (v, v.label)],
                ),
              ),
            ],
          ),
          _Header(tr.lyrics, hint: tr.lyricsHint),
          SettingsCard(
            children: [
              SettingTile(
                icon: Icons.lyrics_outlined,
                title: Text(tr.lyricsPage),
                subtitle: Text(tr.lyricsPageSubtitle, style: muted),
                control: OptionPicker<LyricsLayout>(
                  value: p.lyricsLayout,
                  onChanged: p.setLyricsLayout,
                  options: [for (final v in LyricsLayout.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.view_agenda_outlined,
                title: Text(tr.linesShown),
                subtitle: Text(tr.linesShownSubtitle, style: muted),
                control: OptionPicker<LyricsLines>(
                  value: p.lyricsLines,
                  onChanged: p.setLyricsLines,
                  options: [for (final v in LyricsLines.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.mic_external_on_outlined,
                title: Text(tr.sync),
                subtitle: Text(tr.syncSubtitle, style: muted),
                control: OptionPicker<LyricsSync>(
                  value: p.lyricsSync,
                  onChanged: p.setLyricsSync,
                  options: [for (final v in LyricsSync.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.format_size_rounded,
                title: Text(tr.textSize),
                subtitle: Text(tr.lyricsTextSizeSubtitle, style: muted),
                control: OptionPicker<LyricsSize>(
                  value: p.lyricsSize,
                  onChanged: p.setLyricsSize,
                  options: [for (final v in LyricsSize.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.format_align_left_rounded,
                title: Text(tr.alignment),
                subtitle: Text(tr.alignmentSubtitle, style: muted),
                control: OptionPicker<LyricsAlign>(
                  value: p.lyricsAlign,
                  onChanged: p.setLyricsAlign,
                  options: [for (final v in LyricsAlign.values) (v, v.label)],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.contrast_rounded),
                title: Text(tr.dimUnsung),
                subtitle: Text(tr.dimUnsungSubtitle, style: muted),
                value: p.dimUnsungLyrics,
                onChanged: p.setDimUnsungLyrics,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.highlight_rounded),
                title: Text(tr.highlightLyricLine),
                subtitle: Text(tr.highlightLyricLineSubtitle, style: muted),
                value: p.highlightLyricLine,
                onChanged: p.setHighlightLyricLine,
              ),
              if (MediaSession.lyricsSupported)
                ValueListenableBuilder(
                  valueListenable: MediaSession.showLyrics,
                  builder: (context, on, _) => SwitchListTile(
                    secondary: const Icon(Icons.lock_clock_rounded),
                    title: Text(tr.lockScreenLyrics),
                    subtitle: Text(tr.lockScreenLyricsSubtitle, style: muted),
                    value: on,
                    onChanged: (v) => MediaSession.showLyrics.value = v,
                  ),
                ),
            ],
          ),
          if (Features.audioVisualizer) ...[
            _Header(tr.visualizer, hint: tr.visualizerHint),
            _VisualizerSettings(prefs: p),
          ],
          _Header(tr.pages, hint: tr.pagesHint),
          SettingsCard(
            children: [
              SettingTile(
                icon: Icons.album_rounded,
                title: Text(tr.albumPlaylistTop),
                subtitle: Text(tr.albumPlaylistTopSubtitle, style: muted),
                control: OptionPicker<AlbumHeaderStyle>(
                  value: p.albumHeader,
                  onChanged: p.setAlbumHeader,
                  options: [for (final v in AlbumHeaderStyle.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.equalizer_rounded,
                title: Text(tr.songThatIsPlaying),
                subtitle: Text(tr.songThatIsPlayingSubtitle, style: muted),
                control: OptionPicker<PlayingRowStyle>(
                  value: p.playingRow,
                  onChanged: p.setPlayingRow,
                  options: [for (final v in PlayingRowStyle.values) (v, v.label)],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _HomeSections(),
          _Header(tr.bars, hint: tr.barsHint),
          SettingsCard(
            children: [
              SettingTile(
                icon: Icons.call_to_action_rounded,
                title: Text(tr.miniPlayer),
                subtitle: Text(tr.miniPlayerSubtitle, style: muted),
                control: OptionPicker<MiniPlayerStyle>(
                  value: p.miniPlayer,
                  onChanged: p.setMiniPlayer,
                  options: [for (final v in MiniPlayerStyle.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.call_to_action_outlined,
                title: Text(tr.tabBarOnPhones),
                subtitle: Text(tr.tabBarOnPhonesSubtitle, style: muted),
                control: OptionPicker<TabBarStyle>(
                  value: p.tabBar,
                  onChanged: p.setTabBar,
                  options: [for (final v in TabBarStyle.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.view_stream_rounded,
                title: Text(tr.desktopPlayerBar),
                subtitle: Text(tr.desktopPlayerBarSubtitle, style: muted),
                control: OptionPicker<DesktopBarStyle>(
                  value: p.desktopBar,
                  onChanged: p.setDesktopBar,
                  options: [for (final v in DesktopBarStyle.values) (v, v.label)],
                ),
              ),
            ],
          ),
          _Header(tr.shapesAndMotion),
          if (LayoutPrefs.lightweight)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(tr.motionOffLightweight, style: muted),
            ),
          SettingsCard(
            children: [
              SettingTile(
                icon: Icons.rounded_corner_rounded,
                title: Text(tr.corners),
                subtitle: Text(tr.cornersSubtitle, style: muted),
                control: OptionPicker<CornerStyle>(
                  value: p.corners,
                  onChanged: p.setCorners,
                  options: [for (final v in CornerStyle.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.density_medium_rounded,
                title: Text(tr.spacing),
                subtitle: Text(tr.spacingSubtitle, style: muted),
                control: OptionPicker<Density>(
                  value: p.density,
                  onChanged: p.setDensity,
                  options: [for (final v in Density.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.photo_size_select_large_rounded,
                title: Text(tr.coverSizeInGrids),
                subtitle: Text(tr.coverSizeInGridsSubtitle, style: muted),
                control: OptionPicker<CoverSize>(
                  value: p.coverSize,
                  onChanged: p.setCoverSize,
                  options: [for (final v in CoverSize.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.auto_awesome_motion_rounded,
                title: Text(tr.transitionStyle),
                subtitle: Text(tr.transitionStyleSubtitle, style: muted),
                control: OptionPicker<PageMotionStyle>(
                  value: p.pageMotion,
                  onChanged: LayoutPrefs.lightweight ? null : p.setPageMotion,
                  options: [for (final v in PageMotionStyle.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.speed_rounded,
                title: Text(tr.transitionSpeed),
                subtitle: Text(tr.transitionSpeedSubtitle, style: muted),
                control: OptionPicker<PageMotionSpeed>(
                  value: p.pageSpeed,
                  onChanged: LayoutPrefs.lightweight ? null : p.setPageSpeed,
                  options: [for (final v in PageMotionSpeed.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.animation_rounded,
                title: Text(tr.animations),
                subtitle: Text(tr.animationsSubtitle, style: muted),
                control: OptionPicker<Motion>(
                  value: p.motion,
                  onChanged: LayoutPrefs.lightweight ? null : p.setMotion,
                  options: [for (final v in Motion.values) (v, v.label)],
                ),
              ),
            ],
          ),
          if (hasNativeWindow && !Host.isMacOS) ...[
            _Header(tr.window, hint: tr.desktopOnly),
            SettingsCard(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.web_asset_rounded),
                  title: Text(tr.windowButtons),
                  subtitle: Text(tr.windowButtonsSubtitle, style: muted),
                  value: p.windowButtons,
                  onChanged: p.setWindowButtons,
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: p.isCustomised ? p.reset : null,
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(tr.resetLayout),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.label, {this.hint});

  final String label;

  /// One plain line under the label, for a group that needs it.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.labelLarge?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w700),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(hint!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
            ),
        ],
      ),
    );
  }
}

/// Home's sections: a switch to show or hide each, a handle to drag it to a new place.
class _HomeSections extends StatelessWidget {
  const _HomeSections();

  @override
  Widget build(BuildContext context) {
    final p = LayoutPrefs.instance;
    final muted = settingsMuted(context);
    return Material(
      color: AppColors.elevated,
      borderRadius: LayoutPrefs.corner(12),
      clipBehavior: Clip.antiAlias,
      child: ReorderableListView(
        shrinkWrap: true,
        buildDefaultDragHandles: false,
        physics: const NeverScrollableScrollPhysics(),
        onReorderItem: p.moveHomeSection,
        children: [
          for (final (i, s) in p.homeOrder.indexed)
            SwitchListTile(
              key: ValueKey(s),
              contentPadding: const EdgeInsets.only(left: 6, right: 18),
              secondary: ReorderableDragStartListener(
                index: i,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Tooltip(
                    message: tr.dragToMove,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(Icons.drag_handle_rounded, color: AppColors.textMuted),
                    ),
                  ),
                ),
              ),
              title: Text(s.label),
              subtitle: i == 0 ? Text(tr.dragToReorderSections, style: muted) : null,
              value: !p.homeHidden.contains(s),
              onChanged: (v) => p.setHomeSectionShown(s, v),
            ),
        ],
      ),
    );
  }
}

/// The visualizer's switch and style. Says why it can't show (Bit-perfect, Lightweight, reduced motion grey the switch
/// out; a music video or DoP hides it for one song), and offers only the styles the Cover setting can show.
class _VisualizerSettings extends StatelessWidget {
  const _VisualizerSettings({required this.prefs});
  final LayoutPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final p = prefs;
    final muted = settingsMuted(context);
    final c = context.getInheritedWidgetOfExactType<PlayerScope>()?.notifier;
    return ListenableBuilder(
      listenable: Listenable.merge([?c?.audio, ?c, VideoMode.instance]),
      builder: (context, _) {
        final blocked = c == null
            ? null
            : visualizerBlockedBy(c, reduceMotion: MediaQuery.disableAnimationsOf(context));
        final hidden = c == null || blocked != null || !p.visualizer ? null : visualizerHiddenBy(c);
        final on = p.visualizer && blocked == null;
        final styles = VisualizerStyle.fitting(p.playerCover);
        return SettingsCard(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.graphic_eq_rounded),
              title: Text(tr.audioVisualizer),
              subtitle: Text(blocked ?? hidden ?? tr.audioVisualizerSubtitle, style: muted),
              value: on,
              onChanged: blocked == null ? p.setVisualizer : null,
            ),
            if (on) ...[
              SettingTile(
                icon: Icons.multiline_chart_rounded,
                title: Text(tr.visualizerStyle),
                subtitle: Text(
                  p.playerCover == PlayerCover.background
                      ? tr.visualizerStyleBackground
                      : p.visualizerStyle.radial
                      ? tr.visualizerStyleRings
                      : tr.visualizerStyleEdge,
                  style: muted,
                ),
                control: OptionPicker<VisualizerStyle>(
                  value: p.visualizerStyle,
                  onChanged: p.setVisualizerStyle,
                  options: [for (final style in styles) (style, style.label)],
                ),
              ),
              if (p.visualizerStyle.radial) ...[
                SettingTile(
                  icon: Icons.open_in_full_rounded,
                  title: Text(tr.radiusMovement),
                  subtitle: Text(tr.radiusMovementSubtitle('${(p.visualizerRadius * 100).round()}'), style: muted),
                  control: SizedBox(
                    width: 220,
                    child: Slider(
                      value: p.visualizerRadius,
                      min: 0.5,
                      max: 2.5,
                      divisions: 20,
                      label: '${(p.visualizerRadius * 100).round()}%',
                      onChanged: p.setVisualizerRadius,
                    ),
                  ),
                ),
                SettingTile(
                  icon: Icons.line_weight_rounded,
                  title: Text(tr.lineThickness),
                  subtitle: Text('${p.visualizerThickness.toStringAsFixed(1)} px', style: muted),
                  control: SizedBox(
                    width: 220,
                    child: Slider(
                      value: p.visualizerThickness,
                      min: 1,
                      max: 8,
                      divisions: 14,
                      label: '${p.visualizerThickness.toStringAsFixed(1)} px',
                      onChanged: p.setVisualizerThickness,
                    ),
                  ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}
