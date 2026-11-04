import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../../services/video_mode.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../ytmusic_edit.dart' show LikeButton;
import '../widgets/controls.dart';
import '../widgets/faded_cover.dart';
import '../widgets/about_artist.dart';
import '../widgets/audio_visualizer.dart';
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
          : ListenableBuilder(
              listenable: Listenable.merge([LayoutPrefs.instance, VideoMode.instance]),
              builder: (context, _) {
                // The cover as the panel's top (Cover: Background), or the music video there when Video is picked:
                // the song on its foot, then About the artist and what is next. Otherwise the classic card.
                final hero =
                    LayoutPrefs.instance.playerCover == PlayerCover.background ||
                    VideoMode.instance.showsAsBackground(track);
                if (hero) return _HeroPanel(track: track, from: from, next: next, onClose: onClose);
                return SmoothScroll(
                  builder: (context, scroll) => ListView(
                    controller: scroll,
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
                    children: [
                      // No header row: the player bar's Now playing view button shows and hides the panel, and
                      // the song's menu sits by its title.
                      _PanelCover(track: track),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              track.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
                            ),
                          ),
                          TrackMenuButton(track: track, nowPlaying: true),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // A click away from the artist's page (and the album's, for a file here).
                      ArtistLinks(
                        track: track,
                        style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
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
                      // In every look, as in the cover-as-page one.
                      if (track.artists.isNotEmpty) ...[
                        AboutArtist(
                          name: track.artists.first,
                          channelId: track.isRemote ? track.artistId : null,
                          onOpen: openArtist(context, c, track),
                        ),
                        const SizedBox(height: 16),
                      ],
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
                );
              },
            ),
    );
  }
}

/// The big cover: the flower or the rounded square in the list's margins, or with Cover set to Background, edge to
/// edge with no frame, fading into the panel below.
class _PanelCover extends StatelessWidget {
  const _PanelCover({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LayoutPrefs.instance,
    builder: (context, _) {
      final bleed = LayoutPrefs.instance.playerCover == PlayerCover.background;
      final cover = NowPlayingCover(
        child: bleed
            ? FadedCover(track: track, fade: AppColors.panel, blurStart: 0.5)
            : TrackVisual(
                track: track,
                cover: AudioVisualizer(
                  radialOnly: true,
                  child: TrackSwitcher(
                    trackId: track.id,
                    slide: false,
                    child: Artwork(key: ValueKey(track.id), track: track, radius: 8),
                  ),
                ),
              ),
      );
      if (!bleed) return AspectRatio(aspectRatio: 1, child: cover);
      // Out past the list's 16 px margins on both sides.
      return LayoutBuilder(
        builder: (context, box) {
          final side = box.maxWidth + 32;
          return SizedBox(
            height: side,
            child: OverflowBox(minWidth: side, maxWidth: side, minHeight: side, maxHeight: side, child: cover),
          );
        },
      );
    },
  );
}

/// The side panel with the cover (or the music video) across its top, like the music apps' "Now playing" view: the
/// title and artist on its foot with the heart and the song's menu; then what is next and About the artist. The
/// player bar's Now playing view button shows and hides it, so it has no Close of its own.
class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.track, required this.from, required this.next, required this.onClose});

  final Track track;
  final String? from;
  final Track? next;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    final next = this.next;
    return SmoothScroll(
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.only(bottom: 16 + MediaQuery.paddingOf(context).bottom),
        children: [
          AspectRatio(
            aspectRatio: 0.82,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The cover, sharp up top and soft into the panel; the video over it once it plays.
                FadedCover(track: track, fade: AppColors.panel, blurStart: 0.7),
                VideoBackground(track: track),
                // Readable words over any picture: darker at the foot, where the title sits.
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.45),
                          Colors.transparent,
                          Colors.transparent,
                          AppColors.panel.withValues(alpha: 0.85),
                          AppColors.panel,
                        ],
                        stops: const [0, 0.22, 0.5, 0.88, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 8,
                  bottom: 12,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            ArtistLinks(
                              track: track,
                              style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      LikeButton(track: track, size: 24),
                      TrackMenuButton(track: track, nowPlaying: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (LayoutPrefs.instance.showQualityBadge) ...[const QualityBadge(), const SizedBox(height: 16)],
                // What is next stays on the panel, before anything else below the picture.
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
                            child: Text('Next in queue', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                          TextButton(
                            onPressed: shell.openQueue,
                            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                            child: const Text('Open queue'),
                          ),
                        ],
                      ),
                      if (next != null)
                        TrackRow(track: next, onTap: () => c.playQueueItem(next))
                      else
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                          child: Text(
                            'Nothing after this song',
                            style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (track.artists.isNotEmpty) ...[
                  AboutArtist(
                    name: track.artists.first,
                    channelId: track.isRemote ? track.artistId : null,
                    onOpen: openArtist(context, c, track),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
