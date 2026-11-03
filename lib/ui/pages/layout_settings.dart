import 'package:flutter/material.dart';

import '../../services/layout_prefs.dart';
import '../../services/player_presets.dart';
import '../../services/beta_features.dart';
import '../theme.dart';
import 'player_presets_page.dart';
import 'sound_settings.dart';
import '../widgets/menus.dart';

/// Settings › Look & feel › Layout: corners, density, cover size, Home's sections, what the
/// player shows, lyrics and motion. Every default is how the app has always looked.
class LayoutSettings extends StatelessWidget {
  const LayoutSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPrefs.instance;
    final muted = settingsMuted(context);
    return ListenableBuilder(
      listenable: Listenable.merge([p, BetaFeatures.instance]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (BetaFeature.videoMode.available)
            SettingsCard(
              children: [
                SwitchListTile(
                  title: const Text('Video mode'),
                  subtitle: const Text('Watch music videos in sync with the song'),
                  value: BetaFeatures.instance.isOn(BetaFeature.videoMode),
                  onChanged: (value) => BetaFeatures.instance.set(BetaFeature.videoMode, value),
                ),
              ],
            ),
          const _Header('Shapes and sizes'),
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
                subtitle: Text('Full-width controls, a floating dock, or a compact row beside the song', style: muted),
                control: OptionPicker<DesktopBarStyle>(
                  value: p.desktopBar,
                  onChanged: p.setDesktopBar,
                  options: [for (final v in DesktopBarStyle.values) (v, v.label)],
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
            ],
          ),
          const _Header('Home page'),
          const _HomeSections(),
          const _Header('Now playing'),
          SettingsCard(
            children: [
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
              SettingTile(
                icon: Icons.waves_rounded,
                title: const Text('Progress bar shape'),
                subtitle: Text('Wavy curves the part played. Pill is a thick bar, on phones', style: muted),
                control: OptionPicker<ProgressBarShape>(
                  value: p.progressShape,
                  onChanged: p.setProgressShape,
                  options: [for (final v in ProgressBarShape.values) (v, v.label)],
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
              SwitchListTile(
                secondary: const Icon(Icons.high_quality_outlined),
                title: const Text('Show sound quality'),
                subtitle: Text('The small label under the song title, such as FLAC or Hi-Res', style: muted),
                value: p.showQualityBadge,
                onChanged: p.setShowQualityBadge,
              ),
            ],
          ),
          const _Header('Player on phones'),
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
              SettingTile(
                icon: Icons.wallpaper_rounded,
                title: const Text('Cover'),
                subtitle: Text('A card with margins, or the whole width at the top', style: muted),
                control: OptionPicker<PlayerCover>(
                  value: p.playerCover,
                  onChanged: p.setPlayerCover,
                  options: [for (final v in PlayerCover.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.vertical_align_top_rounded,
                title: const Text('Top of the player'),
                subtitle: Text('What the top shows beside the close arrow', style: muted),
                control: OptionPicker<PlayerHeader>(
                  value: p.playerHeader,
                  onChanged: p.setPlayerHeader,
                  options: [for (final v in PlayerHeader.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.smart_button_rounded,
                title: const Text('Buttons by the title'),
                subtitle: Text('Like and More as they are, boxed with Share, or plain icons', style: muted),
                control: OptionPicker<TitleActions>(
                  value: p.titleActions,
                  onChanged: p.setTitleActions,
                  options: [for (final v in TitleActions.values) (v, v.label)],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.timelapse_rounded),
                title: const Text('Show time left'),
                subtitle: Text('The right time counts down instead of showing the total', style: muted),
                value: p.showTimeLeft,
                onChanged: p.setShowTimeLeft,
              ),
              SettingTile(
                icon: Icons.play_circle_outline_rounded,
                title: const Text('Controls'),
                subtitle: Text('Previous, play and next as circles, a wide pill, or plain icons', style: muted),
                control: OptionPicker<PlayerTransport>(
                  value: p.transport,
                  onChanged: p.setTransport,
                  options: [for (final v in PlayerTransport.values) (v, v.label)],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.volume_up_rounded),
                title: const Text('Volume slider'),
                subtitle: Text('Shown at the very bottom of the player', style: muted),
                value: p.showVolumeRow,
                onChanged: p.setShowVolumeRow,
              ),
              SettingTile(
                icon: Icons.view_week_rounded,
                title: const Text('Bottom buttons'),
                subtitle: Text(
                  'Lyrics and Queue, a row of small buttons, or a minimal row. Lyrics is always there',
                  style: muted,
                ),
                control: OptionPicker<PlayerBottomRow>(
                  value: p.bottomRow,
                  onChanged: p.setBottomRow,
                  options: [for (final v in PlayerBottomRow.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.lyrics_outlined,
                title: const Text('Lyrics page'),
                subtitle: Text('Where the player sits on the lyrics page', style: muted),
                control: OptionPicker<LyricsLayout>(
                  value: p.lyricsLayout,
                  onChanged: p.setLyricsLayout,
                  options: [for (final v in LyricsLayout.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.call_to_action_rounded,
                title: const Text('Mini player'),
                subtitle: Text('The bar above the tabs when a song plays', style: muted),
                control: OptionPicker<MiniPlayerStyle>(
                  value: p.miniPlayer,
                  onChanged: p.setMiniPlayer,
                  options: [for (final v in MiniPlayerStyle.values) (v, v.label)],
                ),
              ),
              SettingTile(
                icon: Icons.album_rounded,
                title: const Text('Album and playlist top'),
                subtitle: Text('A big cover behind the title, with round buttons', style: muted),
                control: OptionPicker<AlbumHeaderStyle>(
                  value: p.albumHeader,
                  onChanged: p.setAlbumHeader,
                  options: [for (final v in AlbumHeaderStyle.values) (v, v.label)],
                ),
              ),
            ],
          ),
          const _Header('Lyrics'),
          SettingsCard(
            children: [
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
          const _Header('Motion'),
          if (LayoutPrefs.lightweight)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Performance is set to Lightweight, so these stay off.', style: muted),
            ),
          SettingsCard(
            children: [
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
  const _Header(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w700),
    ),
  );
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
