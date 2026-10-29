import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/signal_path.dart';
import '../widgets/smooth_scroll.dart';
import '../widgets/stats_for_nerds.dart';
import '../widgets/track_row.dart';
import '../widgets/video_mode.dart';
import 'player_common.dart';

/// Right-hand panel on large screens: big cover, title, and what's next.
class NowPlayingSidePanel extends StatelessWidget {
  const NowPlayingSidePanel({super.key, required this.onClose});

  final VoidCallback onClose;

  /// How often the panel's list was built since start (tests).
  @visibleForTesting
  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    // The song, where it plays from, what is next and the library: a play / pause
    // or a buffering change leaves this whole list alone.
    return PlayerSelect<({Track? track, String? from, Track? next, int library})>(
      select: (c) => (track: c.currentTrack, from: c.playingFrom, next: c.nextTrack, library: c.libraryRevision.value),
      builder: (context, now, _) => _panel(context, c, shell, text, now.track, now.from, now.next),
    );
  }

  Widget _panel(
    BuildContext context,
    PlayerController c,
    ShellScope shell,
    TextTheme text,
    Track? track,
    String? from,
    Track? next,
  ) {
    NowPlayingSidePanel.builds++;
    return ColoredBox(
      color: AppColors.panel,
      child: track == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Play something and it will show up here.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            )
          : SmoothScroll(
              builder: (context, scroll) => ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          from ?? 'Now playing',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TrackMenuButton(track: track, nowPlaying: true),
                      IconButton(tooltip: 'Close', onPressed: onClose, icon: const Icon(Icons.close_rounded, size: 20)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Center(child: VideoModeSwitch(track: track)),
                  AspectRatio(
                    aspectRatio: 1,
                    child: NowPlayingCover(
                      child: TrackVisual(
                        track: track,
                        cover: TrackSwitcher(
                          trackId: track.id,
                          slide: false,
                          child: Artwork(key: ValueKey(track.id), track: track, radius: 8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 4),
                  // A click away from the artist's page (and the album's, for a file here).
                  LinkText(
                    track.artist,
                    style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
                    onTap: openArtist(context, c, track),
                  ),
                  if (track.album != null) ...[
                    const SizedBox(height: 2),
                    LinkText(
                      track.album!,
                      style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                      onTap: switch (c.albumOf(track)) {
                        final album? => () => shell.openCollection(album),
                        null => null,
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (LayoutPrefs.instance.showQualityBadge) const QualityBadge(),
                  const SizedBox(height: 16),
                  if (next != null)
                    Container(
                      decoration: BoxDecoration(color: AppColors.elevated, borderRadius: LayoutPrefs.corner(8)),
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Next in queue',
                                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              TextButton(
                                onPressed: shell.openQueue,
                                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                                child: const Text('Open queue'),
                              ),
                            ],
                          ),
                          TrackRow(track: next, onTap: () => c.playQueueItem(next)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
