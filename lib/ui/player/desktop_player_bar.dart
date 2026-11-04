import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../platform/features.dart';
import '../../services/audio_engine.dart';
import '../../services/layout_prefs.dart';
import '../../services/listen_together/listen_together.dart';
import '../../services/player_controller.dart';
import '../cast_picker.dart';
import '../pages/listen_together_page.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/menus.dart';
import '../widgets/sleep_timer_button.dart';
import '../widgets/stats_for_nerds.dart';
import '../widgets/track_row.dart';
import '../ytmusic_edit.dart';
import 'full_screen_player.dart';
import 'mini_window.dart';
import 'player_common.dart';
import 'player_parts.dart';

/// Desktop controls, full width or presented as a dock over the current page.
class DesktopPlayerBar extends StatelessWidget {
  const DesktopPlayerBar({super.key, required this.sidePanelOpen, required this.onToggleSidePanel});
  final bool sidePanelOpen;
  final VoidCallback? onToggleSidePanel;

  @visibleForTesting
  static int builds = 0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LayoutPrefs.instance,
    builder: (context, _) => PlayerSelect<({Track? track, int library})>(
      select: (c) => (track: c.currentTrack, library: c.libraryRevision.value),
      builder: (context, now, _) {
        builds++;
        final style = LayoutPrefs.instance.desktopBar;
        return LayoutBuilder(
          builder: (context, box) {
            final dockWidth = style == DesktopBarStyle.capsule ? 1040.0 : 1120.0;
            final availableWidth = style.floats ? math.min(box.maxWidth - 48, dockWidth) : box.maxWidth;
            final compact = style == DesktopBarStyle.compact || style == DesktopBarStyle.capsule;
            final minimal = style == DesktopBarStyle.minimal;
            final track = now.track;
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final barHeight = compact
                ? math.max(68.0, 36 * textScale + 30)
                : minimal
                ? math.max(64.0, 36 * textScale + 20)
                : math.max(80.0, 36 * textScale + 16);
            final info = _info(context, track, small: compact || minimal, withProgress: compact);
            final actions = _actions(context, track, width: availableWidth);
            // Controls: Classic is the original row; Pill and Plain are the player parts, sized for the bar.
            final Widget transport = switch (LayoutPrefs.instance.transport) {
              PlayerTransport.classic => const FittedBox(fit: BoxFit.scaleDown, child: TransportControls()),
              final other => FittedBox(
                fit: BoxFit.scaleDown,
                child: DesktopControlsRow(plain: other == PlayerTransport.plain),
              ),
            };
            final Widget content;
            if (compact) {
              content = SizedBox(
                height: barHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      SizedBox(width: 244, child: transport),
                      const SizedBox(width: 16),
                      Expanded(child: info),
                      const SizedBox(width: 20),
                      SizedBox(width: availableWidth > 860 ? 244 : 120, child: actions),
                    ],
                  ),
                ),
              );
            } else {
              content = SizedBox(
                height: barHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 20, 0),
                  child: Column(
                    children: [
                      if (minimal && track != null)
                        const SizedBox(height: 16, child: SeekBar(inline: true, desktopPlayer: true)),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(flex: 3, child: info),
                            Expanded(
                              flex: 4,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 720),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    transport,
                                    if (!minimal && track != null) const SeekBar(inline: true, desktopPlayer: true),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(flex: 3, child: actions),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (!style.floats) return content;
            final colors = AppColors.of(context);
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
              child: Align(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: dockWidth),
                  child: Material(
                    key: const ValueKey('desktop-player-dock'),
                    color: colors.elevated,
                    elevation: 14,
                    shadowColor: Colors.black.withValues(alpha: 0.5),
                    surfaceTintColor: Colors.transparent,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        style == DesktopBarStyle.capsule ? barHeight / 2 : LayoutPrefs.radius(18),
                      ),
                      side: BorderSide(color: colors.textSecondary.withValues(alpha: 0.2)),
                    ),
                    child: content,
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );

  Widget _info(BuildContext context, Track? track, {required bool small, bool withProgress = false}) {
    final c = PlayerScope.read(context);
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    return TrackSwitcher(
      trackId: track?.id,
      child: track == null
          ? const SizedBox.shrink()
          : Row(
              key: ValueKey(track.id),
              children: [
                Artwork(
                  track: track,
                  // Cover Full width: a plain square, not the flower.
                  flower: LayoutPrefs.instance.playerCover != PlayerCover.fullBleed,
                  radius: 0,
                  size: withProgress
                      ? 44
                      : small
                      ? 36
                      : 56,
                ),
                SizedBox(
                  width: withProgress
                      ? 12
                      : small
                      ? 10
                      : 14,
                ),
                Flexible(
                  fit: withProgress ? FlexFit.tight : FlexFit.loose,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinkText(
                        track.title,
                        style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        onTap: switch (c.albumOf(track)) {
                          final album? => () => shell.openCollection(album),
                          null => null,
                        },
                      ),
                      const SizedBox(height: 2),
                      LinkText(
                        track.artist,
                        style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                        onTap: openArtist(context, c, track),
                      ),
                      if (withProgress) ...[
                        const SizedBox(height: 2),
                        const SizedBox(height: 20, child: SeekBar(inline: true, compact: true, desktopPlayer: true)),
                      ],
                    ],
                  ),
                ),
                LikeButton(track: track),
              ],
            ),
    );
  }

  /// Bottom buttons: Classic is the plain icons; Chips boxes Lyrics and Queue and adds the sleep timer; Minimal is
  /// Lyrics and Queue as plain icons with the volume behind its button. Lyrics is on the bar in all of them.
  Widget _actions(BuildContext context, Track? track, {required double width}) {
    final shell = ShellScope.of(context);
    final prefs = LayoutPrefs.instance;
    final row = prefs.bottomRow;
    final slider = width > 860 && prefs.showVolumeRow && row != PlayerBottomRow.minimal;
    Widget part(IconData icon, String tooltip, VoidCallback? onPressed, {bool lit = false}) => PartButton(
      icon: icon,
      tooltip: tooltip,
      look: row == PlayerBottomRow.minimal ? PartLook.plain : PartLook.outlined,
      lit: lit,
      size: row == PlayerBottomRow.minimal ? 40 : 36,
      iconSize: row == PlayerBottomRow.minimal ? 24 : 20,
      onPressed: onPressed,
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Always on the bar, never folded into the menu: lyrics are one of the most used views.
          ListenableBuilder(
            listenable: Listenable.merge([fullScreenPlayer, expandedPlayerPanel]),
            builder: (context, _) {
              final on = fullScreenPlayer.value && expandedPlayerPanel.value == ExpandedPanel.lyrics;
              final VoidCallback? open = track == null
                  ? null
                  : fullScreenPlayer.value
                  ? () => toggleExpandedPanel(ExpandedPanel.lyrics)
                  : shell.openLyrics;
              return row == PlayerBottomRow.classic
                  ? IconButton(
                      tooltip: on ? 'Hide lyrics' : 'Lyrics',
                      onPressed: open,
                      icon: Icon(Icons.lyrics_outlined, size: 20, color: on ? AppColors.accent : null),
                    )
                  : part(Icons.lyrics_outlined, on ? 'Hide lyrics' : 'Lyrics', open, lit: on);
            },
          ),
          if (row == PlayerBottomRow.classic)
            IconButton(
              tooltip: 'Queue',
              onPressed: shell.openQueue,
              icon: const Icon(Icons.queue_music_rounded, size: 20),
            )
          else ...[
            const SizedBox(width: 6),
            part(Icons.queue_music_rounded, 'Queue', shell.openQueue),
          ],
          if (row == PlayerBottomRow.chips) ...[
            const SizedBox(width: 6),
            ListenableBuilder(
              listenable: PlayerScope.read(context).sleep,
              builder: (context, _) {
                final sleep = PlayerScope.read(context).sleep;
                return part(
                  sleep.active ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                  sleep.active ? 'Sleep timer: ${SleepTimerLabel.of(sleep)}' : 'Sleep timer',
                  () => showSleepTimer(context),
                  lit: sleep.active,
                );
              },
            ),
          ],
          if (slider) const VolumeSlider() else const _VolumeMenu(),
          _MoreMenu(track: track, sidePanelOpen: sidePanelOpen, onToggleSidePanel: onToggleSidePanel),
        ],
      ),
    );
  }
}

/// Volume remains available on narrow desktop windows without crowding the dock.
class _VolumeMenu extends StatelessWidget {
  const _VolumeMenu();

  @override
  Widget build(BuildContext context) => MenuAnchor(
    builder: (context, menu, _) => IconButton(
      tooltip: 'Volume',
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      icon: const Icon(Icons.volume_up_rounded, size: 20),
    ),
    menuChildren: const [Padding(padding: EdgeInsets.all(12), child: VolumeSlider())],
  );
}

/// Additional playback controls, views, devices and audio details in one place.
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.track, required this.sidePanelOpen, required this.onToggleSidePanel});

  final Track? track;
  final bool sidePanelOpen;

  /// Null when the window is too narrow for the side panel.
  final VoidCallback? onToggleSidePanel;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final hasTrack = track != null;
    final session = ListenTogether.of(c);
    return ListenableBuilder(
      listenable: Listenable.merge([
        fullScreenPlayer,
        expandedPlayerPanel,
        windowFullScreen,
        c.sleep,
        c.cast,
        session,
        c.youtube,
      ]),
      builder: (context, _) {
        final expanded = fullScreenPlayer.value, full = windowFullScreen.value;
        final sleeping = c.sleep.active, device = c.cast.target, together = listenStatusLabel(session);
        PopupMenuItem<VoidCallback> item(IconData icon, String label, VoidCallback? onTap, {bool on = false}) =>
            PopupMenuItem(
              value: onTap,
              enabled: onTap != null,
              child: Row(
                children: [
                  Expanded(
                    child: MenuRow(
                      leading: Icon(icon, color: on ? AppColors.accent : null),
                      title: Text(label),
                    ),
                  ),
                  if (on) Icon(Icons.check_rounded, size: 18, color: AppColors.accent),
                ],
              ),
            );
        final downloadable = track != null && track!.isRemote && c.downloadedCopy(track!) == null;
        final downloading = downloadable && (c.youtube.jobFor(track!.videoId!)?.isActive ?? false);
        return PopupMenuButton<VoidCallback>(
          // Over the whole window, so a click anywhere closes it.
          useRootNavigator: true,
          tooltip: 'More options',
          icon: Icon(
            Icons.more_horiz_rounded,
            size: 22,
            color: expanded || full || sleeping || device != null || together != null ? AppColors.accent : null,
          ),
          onSelected: (open) => open(),
          itemBuilder: (_) => [
            item(
              Icons.lyrics_outlined,
              'Lyrics',
              hasTrack
                  ? (expanded ? () => toggleExpandedPanel(ExpandedPanel.lyrics) : ShellScope.of(context).openLyrics)
                  : null,
              on: expanded && expandedPlayerPanel.value == ExpandedPanel.lyrics,
            ),
            const PopupMenuDivider(),
            item(
              sleeping ? Icons.bedtime_rounded : Icons.bedtime_outlined,
              sleeping ? 'Sleep timer: ${SleepTimerLabel.of(c.sleep)}' : 'Sleep timer',
              () => showSleepTimer(context),
              on: sleeping,
            ),
            if (Features.casting)
              item(
                device == null ? Icons.cast_rounded : Icons.cast_connected_rounded,
                device == null ? 'Play on a device' : 'Playing on ${device.name}',
                () => showCastPicker(context),
                on: device != null,
              ),
            if (Features.listenTogether)
              item(
                Icons.group_outlined,
                together ?? 'Listen together',
                () => openListenTogether(context),
                on: together != null,
              ),
            if (downloadable && Features.downloads)
              item(
                downloading ? Icons.downloading_rounded : Icons.download_rounded,
                downloading ? 'Downloading…' : 'Download',
                () => TrackMenuButton.download(context, c, [track!]),
              ),
            const PopupMenuDivider(),
            if (onToggleSidePanel case final toggle?)
              item(
                Icons.view_sidebar_outlined,
                sidePanelOpen ? 'Hide now playing view' : 'Now playing view',
                toggle,
                on: sidePanelOpen,
              ),
            if (Features.miniPlayer)
              item(Icons.picture_in_picture_alt_rounded, 'Mini player', () => setMiniPlayer(true)),
            if (hasTrack || expanded)
              item(
                expanded ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded,
                expanded ? 'Close expanded player' : 'Expanded player',
                () => showExpandedPlayer(!expanded),
                on: expanded,
              ),
            if (hasTrack || full)
              item(
                full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                full ? 'Exit full screen' : 'Full screen',
                () => setFullScreenPlayer(!full),
                on: full,
              ),
            if (hasTrack && AudioEngine.supported) ...[
              const PopupMenuDivider(),
              for (final e in NowPlayingCover.menuItems())
                PopupMenuItem(onTap: () => NowPlayingCover.handle(context, e.value), child: e.child),
            ],
          ],
        );
      },
    );
  }
}
