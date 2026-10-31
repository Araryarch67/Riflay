import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../platform/features.dart';
import '../../services/audio_engine.dart';
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

/// Full-width bottom player bar for tablets and desktops.
///
/// The song, the transport and the seek bar sit in the open, with Lyrics,
/// Queue and the volume; sleep timer, Play on a device, Listen together,
/// Download and the views (side panel, mini, expanded, full screen) are in the ⋯.
class DesktopPlayerBar extends StatelessWidget {
  const DesktopPlayerBar({super.key, required this.sidePanelOpen, required this.onToggleSidePanel});

  final bool sidePanelOpen;

  /// Null when the window is too narrow for the side panel.
  final VoidCallback? onToggleSidePanel;

  /// How often the bar's song area was built since start (tests).
  @visibleForTesting
  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    // The song (and, for its album link, the library): not each play / pause or buffering.
    return PlayerSelect<({Track? track, int library})>(
      select: (c) => (track: c.currentTrack, library: c.libraryRevision.value),
      builder: (context, now, _) {
        final track = now.track;
        DesktopPlayerBar.builds++;
        return SizedBox(
          height: 80,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 20, 0),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TrackSwitcher(
                    trackId: track?.id,
                    child: track == null
                        ? const SizedBox.shrink()
                        : Row(
                            key: ValueKey(track.id),
                            children: [
                              Artwork(track: track, size: 56),
                              const SizedBox(width: 14),
                              Flexible(
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
                                  ],
                                ),
                              ),
                              LikeButton(track: track),
                            ],
                          ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // FittedBox: on the narrowest wide layouts the controls scale down instead of overflowing.
                        const FittedBox(fit: BoxFit.scaleDown, child: TransportControls()),
                        if (track != null) const SeekBar(inline: true),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  // Scales down on the narrowest wide layouts instead of overflowing.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // In the expanded player, lyrics open beside the cover instead.
                        ListenableBuilder(
                          listenable: Listenable.merge([fullScreenPlayer, expandedPlayerLyrics]),
                          builder: (context, _) {
                            final beside = fullScreenPlayer.value;
                            return IconButton(
                              tooltip: 'Lyrics',
                              color: beside && expandedPlayerLyrics.value ? AppColors.accent : null,
                              onPressed: track == null
                                  ? null
                                  : beside
                                  ? () => expandedPlayerLyrics.value = !expandedPlayerLyrics.value
                                  : shell.openLyrics,
                              icon: const Icon(Icons.lyrics_outlined, size: 20),
                            );
                          },
                        ),
                        IconButton(
                          tooltip: 'Queue',
                          onPressed: shell.openQueue,
                          icon: const Icon(Icons.queue_music_rounded, size: 20),
                        ),
                        // The bar spans the whole window, so its own width decides (not the content area's).
                        if (MediaQuery.sizeOf(context).width > 860) const VolumeSlider(),
                        _MoreMenu(track: track, sidePanelOpen: sidePanelOpen, onToggleSidePanel: onToggleSidePanel),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The player bar's ⋯: the sleep timer, Play on a device, Listen together and
/// Download, then the views (the now-playing side panel, the mini player, the
/// expanded player and full screen), then Stats for nerds and Signal path.
/// Lit while a sleep timer, a device or a view is on.
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
      listenable: Listenable.merge([fullScreenPlayer, windowFullScreen, c.sleep, c.cast, session, c.youtube]),
      builder: (context, _) {
        final expanded = fullScreenPlayer.value, full = windowFullScreen.value;
        final sleeping = c.sleep.active, device = c.cast.target, together = listenStatusLabel(session);
        PopupMenuItem<VoidCallback> item(IconData icon, String label, VoidCallback onTap, {bool on = false}) =>
            PopupMenuItem(
              value: onTap,
              child: MenuRow(
                leading: Icon(icon, color: on ? AppColors.accent : null),
                title: Text(label),
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
