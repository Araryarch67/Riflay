import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/appearance.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../../services/video_mode.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/marquee_text.dart';
import '../widgets/signal_path.dart';
import '../widgets/stats_for_nerds.dart';
import '../widgets/video_mode.dart';
import '../ytmusic_edit.dart';
import 'more_sheet.dart';

/// Full-screen player on phones. Swipe down or tap the chevron to close.
///
/// On its face: the cover (or the video), title and artist, like, the
/// progress line and shuffle / previous / play / next / repeat, with Lyrics,
/// Queue and ⋯ More. The sleep timer, Play on a device, Listen together,
/// Song / Video, Download, Add to playlist, the equalizer, Signal path and
/// Stats for nerds are in the ⋯ sheet ([showPlayerMore]).
class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({super.key});

  @override
  Widget build(BuildContext context) {
    // The song and where it plays from; play state lives in the controls.
    return PlayerSelect<({Track? track, String? from})>(
      select: (c) => (track: c.currentTrack, from: c.playingFrom),
      builder: (context, now, _) => _page(context, now.track, now.from),
    );
  }

  Widget _page(BuildContext context, Track? track, String? from) {
    final text = Theme.of(context).textTheme;
    final look = Appearance.instance.nowPlaying;
    return AccentBuilder(
      track: track,
      builder: (context, accent) => GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 400) Navigator.of(context).pop();
        },
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (look == NowPlayingBackground.blurredCover && track != null)
                // A small decode is plenty under this much blur. Its own layer: the
                // colour steps and the controls above never blur it again.
                RepaintBoundary(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48, tileMode: TileMode.clamp),
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: Artwork(track: track, size: 160, radius: 0),
                    ),
                  ),
                ),
              AnimatedContainer(
                duration: LayoutPrefs.dur(const Duration(milliseconds: 500)),
                decoration: BoxDecoration(
                  color: look == NowPlayingBackground.black ? Colors.black : null,
                  gradient: switch (look) {
                    NowPlayingBackground.color => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [accent, Color.lerp(accent, Colors.black, 0.75)!, Colors.black],
                      stops: const [0, 0.6, 1],
                    ),
                    // Darkens the blurred cover towards the controls, so text stays readable.
                    NowPlayingBackground.blurredCover => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x40000000), Color(0xA6000000), Colors.black],
                      stops: [0, 0.6, 1],
                    ),
                    NowPlayingBackground.black => null,
                  },
                ),
                child: SafeArea(
                  child: ListenableBuilder(
                    listenable: VideoMode.instance,
                    builder: (context, _) => LayoutBuilder(
                      builder: (context, constraints) {
                        final showsVideo = VideoMode.instance.videoOf(track) != null && VideoMode.instance.on;
                        // Leave room for the controls; never let the cover push them off-screen.
                        // On very short windows the cover (then the quality badge) makes way.
                        final showBadge = constraints.maxHeight >= 480 && LayoutPrefs.instance.showQualityBadge;
                        final largeCover = LayoutPrefs.instance.phoneCover == PhoneCoverSize.large;
                        // A phone held sideways: the cover goes beside the controls.
                        final sideways = constraints.maxWidth > constraints.maxHeight && constraints.maxHeight < 480;
                        final topBar = Row(
                          children: [
                            IconButton(
                              tooltip: 'Close',
                              color: Colors.white,
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    'PLAYING FROM',
                                    style: text.labelSmall?.copyWith(letterSpacing: 1.2, color: Colors.white70),
                                  ),
                                  Text(
                                    from ?? 'Your library',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                            const _MoreButton(),
                          ],
                        );
                        Widget cover(double size) => NowPlayingCover(
                          child: Hero(
                            tag: 'now-playing-art',
                            child: DecoratedBox(
                              // The video is wider than the square: a square shadow would show around it.
                              decoration: BoxDecoration(
                                boxShadow: showsVideo
                                    ? null
                                    : const [BoxShadow(color: Colors.black45, blurRadius: 32, offset: Offset(0, 12))],
                              ),
                              child: TrackVisual(
                                track: track,
                                cover: Artwork(track: track, size: size, radius: 8),
                              ),
                            ),
                          ),
                        );
                        final info = Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  MarqueeText(
                                    track?.title ?? 'Nothing playing',
                                    style: text.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  MarqueeText(
                                    track?.artist ?? '',
                                    style: text.titleMedium?.copyWith(color: Colors.white70),
                                  ),
                                  if (showBadge) ...[const SizedBox(height: 8), const QualityBadge(onDark: true)],
                                ],
                              ),
                            ),
                            if (track != null) LikeButton(track: track, size: 28, color: Colors.white),
                          ],
                        );
                        if (sideways) {
                          final art = math.min(constraints.maxHeight - 32, constraints.maxWidth * 0.4);
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              children: [
                                if (art >= 96) ...[cover(art), const SizedBox(width: 32)],
                                Expanded(
                                  child: Column(
                                    children: [
                                      topBar,
                                      const Spacer(),
                                      info,
                                      const SizedBox(height: 8),
                                      const SeekBar(),
                                      const TransportControls(large: true),
                                      const _SecondaryRow(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        final art = largeCover
                            ? math.min(constraints.maxWidth - 24, constraints.maxHeight - (showBadge ? 364 : 328))
                            : math.min(constraints.maxWidth - 48, constraints.maxHeight - (showBadge ? 400 : 364));
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: [
                              topBar,
                              const Spacer(),
                              // The large cover runs 12 px into the page's margin on each side.
                              if (art >= 96)
                                largeCover
                                    ? SizedBox(
                                        height: art,
                                        child: OverflowBox(maxWidth: art, child: cover(art)),
                                      )
                                    : cover(art),
                              const Spacer(),
                              info,
                              const SizedBox(height: 16),
                              const SeekBar(),
                              const SizedBox(height: 8),
                              const TransportControls(large: true),
                              const SizedBox(height: 4),
                              const _SecondaryRow(),
                              const SizedBox(height: 8),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ⋯ More: lit while a sleep timer, a device or a Listen together session is on.
class _MoreButton extends StatelessWidget {
  const _MoreButton();

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    return ListenableBuilder(
      listenable: Listenable.merge([c.sleep, c.cast]),
      builder: (context, _) => IconButton(
        tooltip: 'More',
        color: c.sleep.active || c.cast.target != null ? AppColors.accent : Colors.white,
        onPressed: () => showPlayerMore(context, closePlayer: true),
        icon: const Icon(Icons.more_horiz_rounded, size: 28),
      ),
    );
  }
}

/// Lyrics on the left, Queue on the right, under the transport controls.
class _SecondaryRow extends StatelessWidget {
  const _SecondaryRow();

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          tooltip: 'Lyrics',
          color: Colors.white,
          onPressed: shell.openLyrics,
          icon: const Icon(Icons.lyrics_outlined),
        ),
        IconButton(
          tooltip: 'Queue',
          color: Colors.white,
          onPressed: shell.openQueue,
          icon: const Icon(Icons.queue_music_rounded),
        ),
      ],
    );
  }
}
