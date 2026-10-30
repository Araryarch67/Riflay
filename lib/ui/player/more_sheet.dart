import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../platform/features.dart';
import '../../services/audio_engine.dart';
import '../../services/player_controller.dart';
import '../../services/video_mode.dart';
import '../../services/youtube_importer.dart';
import '../cast_picker.dart';
import '../pages/equalizer_page.dart';
import '../pages/listen_together_page.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/signal_path.dart';
import '../widgets/sleep_timer_button.dart';
import '../widgets/stats_for_nerds.dart';
import '../widgets/track_row.dart';
import '../widgets/video_mode.dart';
import '../ytmusic_edit.dart';

/// The player's "More" sheet: everything the phone's player keeps off its
/// face, in labelled groups. Used by the full-screen player's ⋯ and by a
/// long-press on the mini player.
///
/// With [openPlayer] (the mini player's long-press) the sheet also lists Queue, Lyrics and
/// Close player, and Stats for nerds opens the full player they show on.
///
/// [context] is the player's own: the actions run against it after the sheet
/// has closed, so they find the shell around the player.
Future<void> showPlayerMore(BuildContext context, {bool closePlayer = false, VoidCallback? openPlayer}) {
  final c = PlayerScope.read(context);
  final track = c.currentTrack;
  if (track == null) return Future.value();
  final shell = ShellScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.elevated,
    builder: (sheet) =>
        shell.wrap(PlayerMoreSheet(player: context, track: track, closePlayer: closePlayer, openPlayer: openPlayer)),
  );
}

class PlayerMoreSheet extends StatelessWidget {
  const PlayerMoreSheet({
    super.key,
    required this.player,
    required this.track,
    this.closePlayer = false,
    this.openPlayer,
  });

  /// The context of the player the sheet belongs to.
  final BuildContext player;
  final Track track;

  /// The full-screen player closes first for what opens a page of its own.
  final bool closePlayer;

  /// Set by the mini player.
  final VoidCallback? openPlayer;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final text = Theme.of(context).textTheme;
    final shell = ShellScope.of(context);

    /// Closes the sheet, then does [act] against the player's context.
    VoidCallback then(void Function(BuildContext) act) => () {
      Navigator.of(context).pop();
      if (player.mounted) act(player);
    };

    /// Same, for what opens a page: from the full-screen player it steps aside first.
    VoidCallback page(VoidCallback open) => then((_) {
      if (closePlayer) Navigator.of(player).maybePop();
      open();
    });

    Widget group(String title, List<Widget> tiles) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            title.toUpperCase(),
            style: text.labelSmall?.copyWith(letterSpacing: 1.2, color: AppColors.textSecondary),
          ),
        ),
        ...tiles,
      ],
    );

    Widget tile(IconData icon, String label, VoidCallback onTap, {String? subtitle, bool on = false}) => ListTile(
      leading: Icon(icon, color: on ? AppColors.accent : null),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: onTap,
    );

    final sleep = c.sleep;
    final video = VideoMode.instance..follow(c);
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 4, 4),
              child: Row(
                children: [
                  Artwork(track: track, size: 48, radius: 4),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  // Go to artist / album, start radio, edit, remove… the song's own menu.
                  TrackMenuButton(track: track, nowPlaying: true),
                ],
              ),
            ),
            if (openPlayer != null)
              group('Player', [
                tile(Icons.queue_music_rounded, 'Queue', then((_) => shell.openQueue())),
                tile(Icons.lyrics_outlined, 'Lyrics', then((_) => shell.openLyrics())),
                tile(Icons.close_rounded, 'Close player', then((_) => c.closePlayer())),
              ]),
            group('Song', [
              tile(Icons.playlist_add_rounded, 'Add to playlist', then((host) => addToPlaylist(host, [track]))),
              if (track.isRemote && Features.downloads)
                ListenableBuilder(
                  listenable: c.youtube,
                  builder: (context, _) {
                    final job = c.youtube.jobFor(track.videoId!);
                    final done = c.downloadedCopy(track) != null || job?.status == DownloadStatus.done;
                    final busy = job != null && job.isActive;
                    return tile(
                      done ? Icons.download_done_rounded : Icons.download_rounded,
                      done ? 'Downloaded' : (busy ? 'Stop download' : 'Download'),
                      done
                          ? () {}
                          : busy
                          ? () => c.youtube.cancel(job)
                          : then((host) => TrackMenuButton.download(host, c, [track])),
                      on: done,
                      subtitle: done ? 'Plays offline' : (busy ? 'Downloading…' : null),
                    );
                  },
                ),
              // The cover and the music video of the song, when it has one.
              ListenableBuilder(
                listenable: video,
                builder: (context, _) {
                  video.lookUp(track);
                  if (video.videoOf(track) == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: VideoModeSwitch(track: track),
                    ),
                  );
                },
              ),
            ]),
            group('Listen', [
              ListenableBuilder(
                listenable: sleep,
                builder: (context, _) => tile(
                  sleep.active ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                  'Sleep timer',
                  then(showSleepTimer),
                  on: sleep.active,
                  subtitle: sleep.active ? SleepTimerLabel.of(sleep) : null,
                ),
              ),
              if (Features.casting)
                ListenableBuilder(
                  listenable: c.cast,
                  builder: (context, _) {
                    final target = c.cast.target;
                    return tile(
                      target == null ? Icons.cast_rounded : Icons.cast_connected_rounded,
                      'Play on a device',
                      then(showCastPicker),
                      on: target != null,
                      subtitle: target == null ? null : 'Playing on ${target.name}',
                    );
                  },
                ),
              if (Features.listenTogether)
                tile(
                  Icons.group_outlined,
                  'Listen together',
                  then((host) => openListenTogether(host, closePlayer: closePlayer)),
                ),
            ]),
            if (AudioEngine.supported)
              group('Sound', [
                tile(Icons.equalizer_rounded, 'Equalizer', page(() => shell.open(const EqualizerPage()))),
                tile(Icons.graphic_eq_rounded, 'Signal path', then(showSignalPath)),
                ValueListenableBuilder(
                  valueListenable: statsForNerds,
                  builder: (context, on, _) => tile(
                    Icons.query_stats_rounded,
                    on ? 'Hide stats for nerds' : 'Stats for nerds',
                    then((_) {
                      statsForNerds.value = !on;
                      if (!on) openPlayer?.call();
                    }),
                    on: on,
                  ),
                ),
              ]),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
