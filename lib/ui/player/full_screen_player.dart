import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/track.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../../services/video_mode.dart';
import '../pages/lyrics_page.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/marquee_text.dart';
import '../widgets/stats_for_nerds.dart';
import '../widgets/track_row.dart';
import '../widgets/video_mode.dart';
import '../ytmusic_edit.dart';
import 'player_common.dart';

/// Desktop expanded player: the cover art (and lyrics beside it, if asked)
/// fills the space above the player bar, inside the window (under the title
/// bar) or with the window full screen (Esc, F11 or the bar's buttons leave).
final fullScreenPlayer = ValueNotifier<bool>(false);

/// Whether the window fills the screen too.
final windowFullScreen = ValueNotifier<bool>(false);

/// Lyrics beside the cover in the expanded player.
final expandedPlayerLyrics = ValueNotifier<bool>(false);

/// Expanded player with the window full screen, or neither.
Future<void> setFullScreenPlayer(bool on) => showExpandedPlayer(on, fullScreen: on);

/// Opens or closes the expanded player; [fullScreen] makes the window fill the screen as well.
Future<void> showExpandedPlayer(bool on, {bool fullScreen = false}) async {
  fullScreenPlayer.value = on;
  final full = on && fullScreen;
  if (windowFullScreen.value == full) return;
  windowFullScreen.value = full;
  try {
    await windowManager.setFullScreen(full);
  } catch (e) {
    debugPrint('Full screen: $e'); // the view still works inside the window
  }
}

class FullScreenPlayer extends StatefulWidget {
  const FullScreenPlayer({super.key});

  @override
  State<FullScreenPlayer> createState() => _FullScreenPlayerState();
}

class _FullScreenPlayerState extends State<FullScreenPlayer> {
  bool _hint = true;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _hintTimer = Timer(const Duration(seconds: 3), () => setState(() => _hint = false));
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  /// The cover with the title and what's next under it, sized to [box].
  Widget _cover(BuildContext context, Track track, Track? next, BoxConstraints box, {required double widthShare}) {
    final text = Theme.of(context).textTheme;

    final hasVideo = VideoMode.instance.videoOf(track) != null;
    final showsVideo = hasVideo && VideoMode.instance.on;
    // Room for the title lines and "Next" under the cover (and the Song / Video switch above it).
    final art = math.min(box.maxHeight - 150 - (hasVideo ? 44 : 0), box.maxWidth * widthShare).clamp(120.0, 900.0);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VideoModeSwitch(track: track),
          SizedBox.square(
            dimension: art,
            child: NowPlayingCover(
              child: DecoratedBox(
                // The video is wider than the square: a square shadow would show around it.
                decoration: BoxDecoration(
                  borderRadius: LayoutPrefs.corner(12),
                  boxShadow: showsVideo
                      ? null
                      : const [BoxShadow(color: Color(0x73000000), blurRadius: 40, offset: Offset(0, 16))],
                ),
                child: TrackVisual(
                  track: track,
                  cover: TrackSwitcher(
                    trackId: track.id,
                    slide: false,
                    child: Artwork(key: ValueKey(track.id), track: track, radius: 12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: math.min(math.max(art, 420), box.maxWidth * widthShare),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarqueeText(
                        track.title,
                        style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 4),
                      MarqueeText(
                        next == null ? track.artist : '${track.artist}   ·   Next: ${next.title}',
                        style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                LikeButton(track: track, size: 26),
                TrackMenuButton(track: track, nowPlaying: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The song, what is next and where it plays from: not each play / pause or buffering.
    return PlayerSelect<({Track? track, Track? next, String? from})>(
      select: (c) => (track: c.currentTrack, next: c.nextTrack, from: c.playingFrom),
      builder: (context, now, _) => _screen(context, now.track, now.next, now.from),
    );
  }

  Widget _screen(BuildContext context, Track? track, Track? next, String? from) {
    final text = Theme.of(context).textTheme;
    return AccentBuilder(
      track: track,
      builder: (context, accent) => AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        color: Color.lerp(accent, Colors.black, 0.2),
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 20, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          from ?? track?.album ?? 'Now playing',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      // Queue, volume etc. are in the player bar right below.
                      if (track != null)
                        ValueListenableBuilder(
                          valueListenable: expandedPlayerLyrics,
                          builder: (context, on, _) => LyricsToggleButton(
                            on: on,
                            icon: Icons.lyrics_outlined,
                            tooltip: on ? 'Hide lyrics' : 'Lyrics',
                            onPressed: () => expandedPlayerLyrics.value = !on,
                          ),
                        ),
                      const SizedBox(width: 4),
                      ValueListenableBuilder(
                        valueListenable: windowFullScreen,
                        builder: (context, full, _) => IconButton(
                          tooltip: full ? 'Exit full screen' : 'Close expanded player',
                          onPressed: () => showExpandedPlayer(false),
                          icon: Icon(full ? Icons.fullscreen_exit_rounded : Icons.close_fullscreen_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: track == null
                      ? Center(child: Text('Nothing is playing', style: text.titleMedium))
                      : ListenableBuilder(
                          // The Song / Video switch and the room it takes.
                          listenable: Listenable.merge([expandedPlayerLyrics, VideoMode.instance]),
                          builder: (context, _) => ValueListenableBuilder(
                            valueListenable: expandedPlayerLyrics,
                            builder: (context, lyrics, _) => LayoutBuilder(
                              builder: (context, box) {
                                if (!lyrics) return _cover(context, track, next, box, widthShare: 0.5);
                                final lyricsView = Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Padding(
                                          padding: const EdgeInsets.only(right: 20),
                                          child: LyricsExtrasButtons(key: ValueKey(track.id), track: track),
                                        ),
                                      ),
                                      Expanded(child: LyricsView(track: track)),
                                    ],
                                  ),
                                );
                                // Too narrow for both: the lyrics alone.
                                if (box.maxWidth < 900) return lyricsView;
                                return Row(
                                  children: [
                                    Expanded(
                                      flex: 5,
                                      child: LayoutBuilder(
                                        builder: (context, half) => _cover(context, track, next, half, widthShare: 0.8),
                                      ),
                                    ),
                                    Expanded(flex: 6, child: lyricsView),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                ),
              ],
            ),
            // Tells first-timers how to get out, then fades away.
            Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _hint && windowFullScreen.value ? 1 : 0,
                    duration: const Duration(milliseconds: 400),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(color: const Color(0xE6202020), borderRadius: BorderRadius.circular(8)),
                      child: Text('Press Esc to exit full screen', style: text.bodyMedium),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
