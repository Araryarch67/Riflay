import 'package:flutter/material.dart';

import '../../services/language.dart';
import '../widgets/tempo_pitch.dart';
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
import 'player_parts.dart' show shareTrack;

/// The player's "More" sheet: everything the phone's player keeps off its
/// face, in labelled groups. Used by the full-screen player's ⋯ and by a
/// long-press on the mini player.
///
/// With [openPlayer] (the mini player's long-press) the sheet also lists Queue, Lyrics and
/// Close player, and Detail stats opens the full player they show on.
///
/// [context] is the player's own: the actions run against it after the sheet
/// has closed, so they find the shell around the player.
Future<void> showPlayerMore(BuildContext context, {bool closePlayer = false, VoidCallback? openPlayer}) {
  final c = PlayerScope.read(context);
  final track = c.currentTrack;
  if (track == null) return Future.value();
  VideoMode.instance.follow(c);
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
    final video = VideoMode.instance;
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
                  Artwork(track: track, size: 48, radius: 4, flower: true),
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
                  // The song's own menu, minus what this sheet lists below: one
                  // action, one entry. Detail stats and Signal path are in Sound.
                  TrackMenuButton(
                    track: track,
                    hide: const {TrackMenuEntry.addToPlaylist, TrackMenuEntry.download, TrackMenuEntry.share},
                  ),
                ],
              ),
            ),
            if (openPlayer != null)
              group(tr.sectionPlayer, [
                tile(Icons.queue_music_rounded, tr.queue, then((_) => shell.openQueue())),
                tile(Icons.lyrics_outlined, tr.lyrics, then((_) => shell.openLyrics())),
                tile(Icons.close_rounded, tr.closePlayer, then((_) => c.closePlayer())),
              ]),
            group(tr.sectionSong, [
              tile(Icons.share_outlined, tr.share, then((host) => shareTrack(host, track))),
              tile(Icons.playlist_add_rounded, tr.addToPlaylist, then((host) => addToPlaylist(host, [track]))),
              if (track.isRemote && Features.saveToDevice)
                tile(
                  Icons.download_rounded,
                  tr.saveToDevice,
                  then((host) => TrackMenuButton.saveToDevice(host, track)),
                ),
              if (track.isRemote && Features.downloads)
                ListenableBuilder(
                  listenable: c.youtube,
                  builder: (context, _) {
                    final job = c.youtube.jobFor(track.videoId!);
                    final done = c.downloadedCopy(track) != null || job?.status == DownloadStatus.done;
                    final busy = job != null && job.isActive;
                    return tile(
                      done ? Icons.download_done_rounded : Icons.download_rounded,
                      done ? tr.downloaded : (busy ? tr.stopDownload : tr.download),
                      done
                          ? () {}
                          : busy
                          ? () => c.youtube.cancel(job)
                          : then((host) => TrackMenuButton.download(host, c, [track])),
                      on: done,
                      subtitle: done ? tr.playsOffline : (busy ? tr.downloading : null),
                    );
                  },
                ),
              // "Download with MV": only for a song with a music video, while it isn't downloaded or downloading.
              if (track.isRemote && Features.downloads && Features.videoMode)
                ListenableBuilder(
                  listenable: Listenable.merge([c.youtube, video]),
                  builder: (context, _) {
                    video.lookUp(track);
                    final job = c.youtube.jobFor(track.videoId!);
                    if (!TrackMenuButton.offersMvDownload(c, track) ||
                        (job != null && (job.isActive || job.status == DownloadStatus.done))) {
                      return const SizedBox.shrink();
                    }
                    return tile(
                      Icons.video_library_outlined,
                      tr.downloadWithMv,
                      then((host) => TrackMenuButton.download(host, c, [track], withVideo: true)),
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
            group(tr.sectionListen, [
              ListenableBuilder(
                listenable: sleep,
                builder: (context, _) => tile(
                  sleep.active ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                  tr.sleepTimer,
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
                      tr.playOnDevice,
                      then(showCastPicker),
                      on: target != null,
                      subtitle: target == null ? null : tr.playingOn(target.name),
                    );
                  },
                ),
              if (Features.listenTogether)
                tile(
                  Icons.group_outlined,
                  tr.listenTogether,
                  then((host) => openListenTogether(host, closePlayer: closePlayer)),
                ),
            ]),
            if (AudioEngine.supported)
              group(tr.sectionSound, [
                tile(Icons.equalizer_rounded, tr.equalizer, page(() => shell.open(const EqualizerPage()))),
                tile(Icons.graphic_eq_rounded, tr.signalPath, then(showSignalPath)),
                ListenableBuilder(
                  listenable: c.audio,
                  builder: (context, _) {
                    final a = c.audio;
                    final changed = a.effectiveTempo != 1 || a.effectivePitch != 0;
                    return tile(
                      Icons.speed_rounded,
                      tr.tempoPitch,
                      then(showTempoPitch),
                      on: changed,
                      subtitle: changed ? tempoPitchLabel(a) : null,
                    );
                  },
                ),
                tile(Icons.query_stats_rounded, tr.detailStats, then(showDetailStats)),
              ]),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
