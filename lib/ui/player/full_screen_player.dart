import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/track.dart';
import '../../services/appearance.dart';
import '../../services/audio_engine.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../../services/video_mode.dart';
import '../pages/equalizer_page.dart';
import '../pages/lyrics_page.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/player_backdrop.dart';
import '../widgets/marquee_text.dart';
import '../widgets/stats_for_nerds.dart';
import '../widgets/track_row.dart';
import '../widgets/video_mode.dart';
import 'now_playing_page.dart' show BlurredCover;
import 'player_common.dart';
import 'player_parts.dart';

/// Desktop expanded player: the cover art (and lyrics beside it, if asked)
/// fills the space above the player bar, inside the window (under the title
/// bar) or with the window full screen (Esc, F11 or the bar's buttons leave).
final fullScreenPlayer = ValueNotifier<bool>(false);

/// Whether the window fills the screen too.
final windowFullScreen = ValueNotifier<bool>(false);

/// What sits beside the cover in the expanded player.
enum ExpandedPanel { none, lyrics, equalizer }

/// The panel beside the cover in the expanded player.
final expandedPlayerPanel = ValueNotifier<ExpandedPanel>(ExpandedPanel.none);

/// Shows [panel] beside the cover, or closes it when it is the one already open.
void toggleExpandedPanel(ExpandedPanel panel) =>
    expandedPlayerPanel.value = expandedPlayerPanel.value == panel ? ExpandedPanel.none : panel;

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
    // Full width: the cover takes all of its half, with square corners.
    final bleed = LayoutPrefs.instance.playerCover == PlayerCover.fullBleed;
    final share = bleed ? 1.0 : widthShare;
    // Room for the title lines and "Next" under the cover (and the Song / Video switch above it).
    final art = math.min(box.maxHeight - 150 - (hasVideo ? 44 : 0), box.maxWidth * share).clamp(120.0, 900.0);
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
                decoration: const BoxDecoration(),
                child: TrackVisual(
                  track: track,
                  cover: AudioVisualizer(
                    radialOnly: true,
                    child: TrackSwitcher(
                      trackId: track.id,
                      slide: false,
                      child: Artwork(key: ValueKey(track.id), track: track, radius: bleed ? 0 : 12),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: math.min(math.max(art, 420), box.maxWidth * share),
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
                      LinkText(
                        next == null ? track.artist : '${track.artist}   ·   Next: ${next.title}',
                        style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
                        onTap: openArtist(context, PlayerScope.read(context), track),
                      ),
                    ],
                  ),
                ),
                ...desktopTitleActions(context, track),
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
        duration: LayoutPrefs.dur(const Duration(milliseconds: 500)),
        color: AppColors.sink(accent, 0.75),
        child: Stack(
          children: [
            // Under a playing music video nothing else is drawn: the video covers it, and an animated
            // backdrop there cost a full-window pass every frame for nothing.
            Positioned.fill(
              child: _UnlessVideo(
                track: track,
                child: PlayerBackdrop(coverColor: accent),
              ),
            ),
            // Music video: the blurred cover first, the video over it once it plays, then a dimming for the text.
            // Lightweight keeps the plain colour.
            if (Appearance.instance.nowPlaying == NowPlayingBackground.video && !LayoutPrefs.lightweight) ...[
              if (track != null)
                Positioned.fill(
                  child: _UnlessVideo(
                    track: track,
                    child: RepaintBoundary(child: BlurredCover(track: track)),
                  ),
                ),
              Positioned.fill(child: VideoBackground(track: track)),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.solidBackground.withValues(alpha: 0.55),
                          AppColors.solidBackground.withValues(alpha: 0.82),
                          AppColors.solidBackground,
                        ],
                        stops: const [0, 0.6, 1],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            Padding(
              // Top: the title bar that slides in over the window; the picture behind still fills it.
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top,
                bottom: MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 20, 20, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: PlayerFromLabel(from: from, album: track?.album),
                        ),
                        // Queue, volume etc. are in the player bar right below.
                        // Always there, even with nothing playing: Lyrics is never hidden.
                        _PanelButtons(hasTrack: track != null),
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
                            listenable: Listenable.merge([
                              expandedPlayerPanel,
                              VideoMode.instance,
                              LayoutPrefs.instance,
                            ]),
                            builder: (context, _) => LayoutBuilder(
                              builder: (context, box) {
                                final panel = expandedPlayerPanel.value;
                                if (panel == ExpandedPanel.none) {
                                  return _cover(context, track, next, box, widthShare: 0.5);
                                }
                                final side = panel == ExpandedPanel.lyrics
                                    ? Padding(
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
                                      )
                                    // Scrolls when the bands and presets don't fit the height.
                                    : const SingleChildScrollView(
                                        padding: EdgeInsets.only(top: 8, bottom: 16),
                                        child: EqualizerPanel(pad: 20),
                                      );
                                // Too narrow for both: the panel alone.
                                if (box.maxWidth < 900) return side;
                                return Row(
                                  children: [
                                    Expanded(
                                      flex: 5,
                                      child: LayoutBuilder(
                                        builder: (context, half) => _cover(context, track, next, half, widthShare: 0.8),
                                      ),
                                    ),
                                    Expanded(flex: 6, child: side),
                                  ],
                                );
                              },
                            ),
                          ),
                  ),
                  if (track != null)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(32, 8, 32, 16),
                      child: AudioVisualizer(linearOnly: true),
                    ),
                ],
              ),
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
                      decoration: BoxDecoration(color: AppColors.menu, borderRadius: BorderRadius.circular(8)),
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

/// Lyrics and Equalizer: a toggle pair for the panel beside the cover.
class _PanelButtons extends StatelessWidget {
  const _PanelButtons({required this.hasTrack});

  final bool hasTrack;

  @override
  Widget build(BuildContext context) {
    final audio = PlayerScope.read(context).audio;
    return ListenableBuilder(
      listenable: Listenable.merge([expandedPlayerPanel, audio]),
      builder: (context, _) {
        final panel = expandedPlayerPanel.value;
        final lyrics = panel == ExpandedPanel.lyrics, eq = panel == ExpandedPanel.equalizer;
        return _PanelSwitch(
          selected: lyrics ? 0 : (eq ? 1 : null),
          segments: [
            (
              icon: Icons.lyrics_outlined,
              tooltip: lyrics ? 'Hide lyrics' : 'Lyrics',
              onPressed: hasTrack || lyrics ? () => toggleExpandedPanel(ExpandedPanel.lyrics) : null,
            ),
            (
              icon: Icons.equalizer_rounded,
              tooltip: eq ? 'Hide equalizer' : 'Equalizer',
              // Like the equalizer's own switch: nothing to turn on in bit-perfect mode or without the engine.
              // An open panel can always be closed.
              onPressed: eq || (AudioEngine.supported && !audio.bitPerfect)
                  ? () => toggleExpandedPanel(ExpandedPanel.equalizer)
                  : null,
            ),
          ],
        );
      },
    );
  }
}

/// A capsule of on / off switches, at most one on: a pill slides behind the one that is on, and tapping it
/// again turns it off. Like a light switch rather than a row of buttons.
class _PanelSwitch extends StatelessWidget {
  const _PanelSwitch({required this.selected, required this.segments});

  /// The segment that is on, or null.
  final int? selected;
  final List<({IconData icon, String tooltip, VoidCallback? onPressed})> segments;

  static const _width = 44.0, _height = 34.0, _pad = 3.0;

  @override
  Widget build(BuildContext context) {
    final on = selected;
    final duration = LayoutPrefs.dur(const Duration(milliseconds: 220));
    return Container(
      padding: const EdgeInsets.all(_pad),
      decoration: ShapeDecoration(shape: const StadiumBorder(), color: AppColors.textPrimary.withValues(alpha: 0.1)),
      child: SizedBox(
        width: _width * segments.length,
        height: _height,
        child: Stack(
          children: [
            // The thumb: stays where it was when everything is off, and fades out.
            AnimatedPositioned(
              duration: duration,
              curve: Curves.easeOutCubic,
              left: _width * (on ?? 0),
              top: 0,
              bottom: 0,
              width: _width,
              child: AnimatedOpacity(
                duration: duration,
                opacity: on == null ? 0 : 1,
                child: DecoratedBox(
                  decoration: ShapeDecoration(shape: const StadiumBorder(), color: AppColors.textPrimary),
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < segments.length; i++)
                  Tooltip(
                    message: segments[i].tooltip,
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: segments[i].onPressed,
                      child: SizedBox(
                        width: _width,
                        height: _height,
                        child: Icon(
                          segments[i].icon,
                          size: 20,
                          color: i == on
                              ? AppColors.solidBackground
                              : segments[i].onPressed == null
                              ? AppColors.textMuted
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// [child], until the background music video of [track] plays over it.
class _UnlessVideo extends StatelessWidget {
  const _UnlessVideo({required this.track, required this.child});

  final Track? track;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: VideoMode.instance,
    builder: (context, child) => VideoMode.instance.coversBackground(track) ? const SizedBox.shrink() : child!,
    child: child,
  );
}
