import 'package:flutter/material.dart';

import '../../platform/features.dart';
import '../../services/appearance.dart';
import '../../services/layout_prefs.dart';
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
          const _Header('Presets', hint: 'A whole look in one tap. Every part below can still be changed on its own'),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.auto_awesome_mosaic_rounded),
                title: const Text('Presets'),
                subtitle: Text(playerPresetName() == null ? 'Custom' : 'Matches ${playerPresetName()}', style: muted),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PlayerPresetsPage())),
              ),
            ],
          ),
          const _Header('Now Playing', hint: 'The full-screen player'),
          SettingsCard(
            children: [
              SettingTile(
                icon: Icons.wallpaper_rounded,
                title: const Text('Cover'),
                subtitle: Text(
                  'Square or flower frame the cover. Background has no frame: it fills the top and fades into the page',
                  style: muted,
                ),
                control: OptionPicker<PlayerCover>(
                  value: p.playerCover,
                  onChanged: p.setPlayerCover,
                  options: [for (final v in PlayerCover.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.fit_screen_rounded,
                title: const Text('Cover size on phones'),
                subtitle: Text('Large reaches nearly the edges of the screen', style: muted),
                control: OptionPicker<PhoneCoverSize>(
                  value: p.phoneCover,
                  onChanged: p.setPhoneCover,
                  options: [for (final v in PhoneCoverSize.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.vertical_align_top_rounded,
                title: const Text('Top of the player'),
                subtitle: Text('What the top shows beside the close arrow, or above the song on desktop', style: muted),
                control: OptionPicker<PlayerHeader>(
                  value: p.playerHeader,
                  onChanged: p.setPlayerHeader,
                  options: [for (final v in PlayerHeader.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.smart_button_rounded,
                title: const Text('Buttons by the title'),
                subtitle: Text(
                  'Like and More as they are, a joined Share and heart pair, or plain icons. The song menu stays on desktop',
                  style: muted,
                ),
                control: OptionPicker<TitleActions>(
                  value: p.titleActions,
                  onChanged: p.setTitleActions,
                  options: [for (final v in TitleActions.values) (v, v.label)],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.high_quality_outlined),
                title: const Text('Show sound quality'),
                subtitle: Text('The small label under the song title, such as FLAC or Hi-Res', style: muted),
                value: p.showQualityBadge,
                onChanged: p.setShowQualityBadge,
              ),
              SettingTile(
                icon: Icons.music_video_outlined,
                title: const Text('Song / Video switch'),
                subtitle: Text(
                  'At the top of Now Playing. Adaptive shows it only when the song has a music video',
                  style: muted,
                ),
                // Not On / Off: even "on", it follows the song (nothing to switch to without a video).
                control: OptionPicker<bool>(
                  value: p.showVideoSwitch,
                  onChanged: p.setShowVideoSwitch,
                  options: const [(true, 'Adaptive'), (false, 'Off')],
                ),
              ),
              SettingTile(
                icon: Icons.high_quality_outlined,
                title: const Text('Quality badge'),
                subtitle: Text(
                  'Where FLAC or Opus 130 kbps sits on the phone player: under the artist, or between the two times',
                  style: muted,
                ),
                control: OptionPicker<QualityBadgePlace>(
                  value: p.qualityBadgePlace,
                  onChanged: p.setQualityBadgePlace,
                  options: [for (final v in QualityBadgePlace.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.wallpaper_rounded,
                title: const Text('Background'),
                subtitle: Text(
                  Appearance.instance.nowPlaying.hint ??
                      'What fills the page behind the player. Cover: Background replaces it',
                  style: muted,
                ),
                control: OptionPicker<NowPlayingBackground>(
                  value: Appearance.instance.nowPlaying,
                  onChanged: Appearance.instance.setNowPlaying,
                  options: [for (final v in NowPlayingBackground.values) (v, v.label)],
                ),
              ),
              if (BetaFeature.videoMode.available) ...[
                SwitchListTile(
                  title: const Text('Video mode'),
                  subtitle: const Text('Watch music videos in sync with the song'),
                  value: BetaFeatures.instance.isOn(BetaFeature.videoMode),
                  onChanged: (value) => BetaFeatures.instance.set(BetaFeature.videoMode, value),
                ),
                ListenableBuilder(
                  listenable: VideoMode.instance,
                  builder: (context, _) {
                    final now = VideoMode.instance.decoderInUse;
                    return SettingTile(
                      icon: Icons.memory_rounded,
                      title: const Text('Video decoding'),
                      subtitle: Text(
                        [
                          p.videoDecoder.note,
                          if (now != null) 'Now: ${now == 'no' ? 'the processor' : 'graphics card ($now)'}',
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
          const _Header('Playback controls', hint: 'The progress bar, the buttons and the row under them'),
          SettingsCard(
            children: [
              SettingTile(
                icon: Icons.waves_rounded,
                title: const Text('Progress bar shape'),
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
                title: const Text('Progress bar'),
                subtitle: Text('How thick the bar you drag to skip around is', style: muted),
                control: OptionPicker<ProgressBarStyle>(
                  value: p.progressBar,
                  onChanged: p.setProgressBar,
                  options: [for (final v in ProgressBarStyle.values) (v, v.label)],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.timelapse_rounded),
                title: const Text('Show time left'),
                subtitle: Text(
                  'The right time counts down instead of showing the total, also on the desktop bar',
                  style: muted,
                ),
                value: p.showTimeLeft,
                onChanged: p.setShowTimeLeft,
              ),
              SettingTile(
                icon: Icons.play_circle_outline_rounded,
                title: const Text('Controls'),
                subtitle: Text(
                  'Previous, play and next as circles, a wide Play pill, or plain big icons, also on the desktop bar',
                  style: muted,
                ),
                control: OptionPicker<PlayerTransport>(
                  value: p.transport,
                  onChanged: p.setTransport,
                  options: [for (final v in PlayerTransport.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.play_circle_outline_rounded,
                title: const Text('Play button'),
                subtitle: Text('The shape of the big play and pause button', style: muted),
                control: OptionPicker<PlayButtonShape>(
                  value: p.playButton,
                  onChanged: p.setPlayButton,
                  options: [for (final v in PlayButtonShape.values) (v, v.label)],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.volume_up_rounded),
                title: const Text('Volume slider'),
                subtitle: Text(
                  'At the very bottom of the phone player. Off, it opens from the speaker button (Icons) or the desktop bar button',
                  style: muted,
                ),
                value: p.showVolumeRow,
                onChanged: p.setShowVolumeRow,
              ),
              SettingTile(
                icon: Icons.tune_rounded,
                title: const Text('Slider look'),
                subtitle: Text(
                  'Every slider: volume, the equalizer and settings. Classic, a thin line, or a thick pill with a bar handle',
                  style: muted,
                ),
                control: OptionPicker<VolumeSliderShape>(
                  value: p.volumeSlider,
                  onChanged: p.setVolumeSlider,
                  options: [for (final v in VolumeSliderShape.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.view_week_rounded,
                title: const Text('Bottom buttons'),
                subtitle: Text(
                  'Lyrics and Queue; a joined row of icon buttons; or Lyrics, a speaker and person capsule and Queue. Icons only, Lyrics is always there',
                  style: muted,
                ),
                control: OptionPicker<PlayerBottomRow>(
                  value: p.bottomRow,
                  onChanged: p.setBottomRow,
                  options: [for (final v in PlayerBottomRow.values) (v, v.label)],
                ),
              ),
            ],
          ),
          const _Header('Lyrics', hint: 'The lyrics page, and the lyrics beside the cover on desktop'),
          SettingsCard(
            children: [
              SettingTile(
                icon: Icons.lyrics_outlined,
                title: const Text('Lyrics page'),
                subtitle: Text(
                  'Where the player sits on the lyrics page. Desktop gets a song card on top or at the bottom',
                  style: muted,
                ),
                control: OptionPicker<LyricsLayout>(
                  value: p.lyricsLayout,
                  onChanged: p.setLyricsLayout,
                  options: [for (final v in LyricsLayout.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.view_agenda_outlined,
                title: const Text('Lines shown'),
                subtitle: Text(
                  'All keeps the whole song in view. Focused shows only the previous, the current and the next line',
                  style: muted,
                ),
                control: OptionPicker<LyricsLines>(
                  value: p.lyricsLines,
                  onChanged: p.setLyricsLines,
                  options: [for (final v in LyricsLines.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.mic_external_on_outlined,
                title: const Text('Sync'),
                subtitle: Text(
                  'Word by word fills each word as it is sung, where the lyrics have word timings. Line by line lights the whole line',
                  style: muted,
                ),
                control: OptionPicker<LyricsSync>(
                  value: p.lyricsSync,
                  onChanged: p.setLyricsSync,
                  options: [for (final v in LyricsSync.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.format_size_rounded,
                title: const Text('Text size'),
                subtitle: Text('How big the lyrics are', style: muted),
                control: OptionPicker<LyricsSize>(
                  value: p.lyricsSize,
                  onChanged: p.setLyricsSize,
                  options: [for (final v in LyricsSize.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.format_align_left_rounded,
                title: const Text('Alignment'),
                subtitle: Text('Lines start at the left edge, or sit in the middle', style: muted),
                control: OptionPicker<LyricsAlign>(
                  value: p.lyricsAlign,
                  onChanged: p.setLyricsAlign,
                  options: [for (final v in LyricsAlign.values) (v, v.label)],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.contrast_rounded),
                title: const Text('Dim lines not yet sung'),
                subtitle: Text('Only the line being sung and the ones before it stay bright', style: muted),
                value: p.dimUnsungLyrics,
                onChanged: p.setDimUnsungLyrics,
              ),
            ],
          ),
          if (Features.audioVisualizer) ...[
            const _Header('Visualizer', hint: 'Shapes that move with the music'),
            _VisualizerSettings(prefs: p),
          ],
          const _Header('Pages', hint: 'Album, playlist and artist pages, song lists and Home'),
          SettingsCard(
            children: [
              SettingTile(
                icon: Icons.album_rounded,
                title: const Text('Album and playlist top'),
                subtitle: Text(
                  'Hero: a big cover fading behind the title, round buttons around a Play pill. Also on artist pages',
                  style: muted,
                ),
                control: OptionPicker<AlbumHeaderStyle>(
                  value: p.albumHeader,
                  onChanged: p.setAlbumHeader,
                  options: [for (final v in AlbumHeaderStyle.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.equalizer_rounded,
                title: const Text('Song that is playing'),
                subtitle: Text(
                  'In a list of songs: coloured text, or a filled rounded card with the bars',
                  style: muted,
                ),
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
          const _Header('Bars', hint: 'The mini player and the bars that hold the controls'),
          SettingsCard(
            children: [
              SettingTile(
                icon: Icons.call_to_action_rounded,
                title: const Text('Mini player'),
                subtitle: Text(
                  'The bar above the tabs when a song plays, on phones. Floating pill has a flower cover and round buttons',
                  style: muted,
                ),
                control: OptionPicker<MiniPlayerStyle>(
                  value: p.miniPlayer,
                  onChanged: p.setMiniPlayer,
                  options: [for (final v in MiniPlayerStyle.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.call_to_action_outlined,
                title: const Text('Tab bar on phones'),
                subtitle: Text(
                  'Classic sits at the bottom edge; Floating and Liquid glass hover above it',
                  style: muted,
                ),
                control: OptionPicker<TabBarStyle>(
                  value: p.tabBar,
                  onChanged: p.setTabBar,
                  options: [for (final v in TabBarStyle.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.view_stream_rounded,
                title: const Text('Desktop player bar'),
                subtitle: Text(
                  'Along the window\'s foot: full-width controls, a compact row beside the song, or a minimal strip',
                  style: muted,
                ),
                control: OptionPicker<DesktopBarStyle>(
                  value: p.desktopBar,
                  onChanged: p.setDesktopBar,
                  options: [for (final v in DesktopBarStyle.values) (v, v.label)],
                ),
              ),
            ],
          ),
          const _Header('Shapes and motion'),
          if (LayoutPrefs.lightweight)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Performance is set to Lightweight, so the motion settings stay off.', style: muted),
            ),
          SettingsCard(
            children: [
              SettingTile(
                icon: Icons.rounded_corner_rounded,
                title: const Text('Corners'),
                subtitle: Text('Covers, cards, menus, dialogs and the mini player', style: muted),
                control: OptionPicker<CornerStyle>(
                  value: p.corners,
                  onChanged: p.setCorners,
                  options: [for (final v in CornerStyle.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.density_medium_rounded,
                title: const Text('Spacing'),
                subtitle: Text('Compact fits more songs and cards on screen', style: muted),
                control: OptionPicker<Density>(
                  value: p.density,
                  onChanged: p.setDensity,
                  options: [for (final v in Density.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.photo_size_select_large_rounded,
                title: const Text('Cover size in grids'),
                subtitle: Text('The albums and playlists on Home and in "Show all"', style: muted),
                control: OptionPicker<CoverSize>(
                  value: p.coverSize,
                  onChanged: p.setCoverSize,
                  options: [for (final v in CoverSize.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.auto_awesome_motion_rounded,
                title: const Text('Transition style'),
                subtitle: Text('Coordinated page, tab and player transitions', style: muted),
                control: OptionPicker<PageMotionStyle>(
                  value: p.pageMotion,
                  onChanged: LayoutPrefs.lightweight ? null : p.setPageMotion,
                  options: [for (final v in PageMotionStyle.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.speed_rounded,
                title: const Text('Transition speed'),
                subtitle: Text('Choose a brisk or more relaxed pace', style: muted),
                control: OptionPicker<PageMotionSpeed>(
                  value: p.pageSpeed,
                  onChanged: LayoutPrefs.lightweight ? null : p.setPageSpeed,
                  options: [for (final v in PageMotionSpeed.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.animation_rounded,
                title: const Text('Animations'),
                subtitle: Text(
                  'Reduced keeps quick fades only. Full follows your system when it asks for less motion',
                  style: muted,
                ),
                control: OptionPicker<Motion>(
                  value: p.motion,
                  onChanged: LayoutPrefs.lightweight ? null : p.setMotion,
                  options: [for (final v in Motion.values) (v, v.label)],
                ),
              ),
            ],
          ),
          if (hasNativeWindow && !Host.isMacOS) ...[
            const _Header('Window', hint: 'Desktop only'),
            SettingsCard(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.web_asset_rounded),
                  title: const Text('Window buttons'),
                  subtitle: Text(
                    'Minimize, maximize and close in the title bar. Turn off with a tiling window manager',
                    style: muted,
                  ),
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
              label: const Text('Reset layout to default'),
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
                    message: 'Drag to move',
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(Icons.drag_handle_rounded, color: AppColors.textMuted),
                    ),
                  ),
                ),
              ),
              title: Text(s.label),
              subtitle: i == 0 ? Text('Drag the handle to put sections in a different order', style: muted) : null,
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
              title: const Text('Audio visualizer'),
              subtitle: Text(
                blocked ?? hidden ?? 'Shapes that move with the music around the cover and under it',
                style: muted,
              ),
              value: on,
              onChanged: blocked == null ? p.setVisualizer : null,
            ),
            if (on) ...[
              SettingTile(
                icon: Icons.multiline_chart_rounded,
                title: const Text('Visualizer style'),
                subtitle: Text(
                  p.playerCover == PlayerCover.background
                      ? 'A strip under the song. Pulse, Orbit and Petals ring the cover: pick Square or Flower for them'
                      : p.visualizerStyle.radial
                      ? 'Rings the cover'
                      : 'Moves along the cover\'s edge, with a strip under the song',
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
                  title: const Text('Radius movement'),
                  subtitle: Text(
                    '${(p.visualizerRadius * 100).round()}% · How far the shape expands with the music',
                    style: muted,
                  ),
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
                  title: const Text('Line thickness'),
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
