import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/appearance.dart';
import '../../services/layout_prefs.dart';
import '../../services/metadata.dart';
import '../../services/player_controller.dart';
import '../../services/video_mode.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/faded_cover.dart';
import '../widgets/wavy_seek_track.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/track_row.dart';
import '../widgets/player_backdrop.dart';
import '../widgets/marquee_text.dart';
import '../widgets/signal_path.dart';
import '../widgets/stats_for_nerds.dart';
import '../widgets/soft_video.dart';
import '../widgets/video_mode.dart';
import '../ytmusic_edit.dart';
import 'more_sheet.dart';
import 'player_common.dart' show LinkText;
import 'player_parts.dart';

/// The name of Now Playing's route, so a page above it can tell whether it is underneath.
const nowPlayingRouteName = 'now-playing';

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
    final a = Appearance.instance;
    // "Black" is an explicit player background, even when the rest of the app
    // is light. Keep its foreground and transport readable in that mode.
    if (a.nowPlaying != NowPlayingBackground.black || !a.palette.light) return _surface(context, track, from);
    final palette = AppPalette.derive(Colors.black, accent: a.palette.accent);
    final theme = Theme.of(context);
    return AppColorsScope(
      colors: AppColorsView(palette, 1, a.highContrast),
      child: Theme(
        data: theme.copyWith(
          textTheme: theme.textTheme.apply(bodyColor: palette.textPrimary, displayColor: palette.textPrimary),
          sliderTheme: theme.sliderTheme.copyWith(
            thumbColor: palette.accent,
            inactiveTrackColor: palette.textPrimary.withValues(alpha: 0.3),
          ),
        ),
        child: Builder(builder: (context) => _surface(context, track, from)),
      ),
    );
  }

  Widget _surface(BuildContext context, Track? track, String? from) {
    final text = Theme.of(context).textTheme;
    final chosen = Appearance.instance.nowPlaying;
    // Music video lies over the blurred cover (Lightweight: the plain colour).
    final look = chosen.effective(lightweight: LayoutPrefs.lightweight);
    // Cover: Background is the whole page: sharp at the top, soft below, instead of any background.
    final coverPage = LayoutPrefs.instance.playerCover == PlayerCover.background && track != null;
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
              if (coverPage) Positioned.fill(child: FadedCover(track: track, darken: 0.65, blurStart: 0.42)),
              // Cover: Background: a song that has a music video plays it over the cover, soft under the title and the
              // controls (as the baked cover is), with a dark gradient to keep them readable. Songs without one keep
              // the baked cover. Not in Lightweight.
              if (coverPage && !LayoutPrefs.lightweight) ...[
                Positioned.fill(child: VideoBackground(track: track)),
                // Frosted under the title and the controls: the video is only a soft glow there, never in the way.
                Positioned.fill(child: SoftVideo(track: track, shrink: 28, from: 0.38)),
                Positioned.fill(
                  child: ListenableBuilder(
                    listenable: VideoMode.instance,
                    builder: (context, _) => VideoMode.instance.coversBackground(track)
                        ? IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.35),
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.55),
                                    Colors.black.withValues(alpha: 0.8),
                                  ],
                                  stops: const [0, 0.2, 0.5, 1],
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
              if (!coverPage && look.isAbstract) Positioned.fill(child: PlayerBackdrop(coverColor: accent)),
              // Not drawn under a playing music video, which covers it.
              if (!coverPage && look == NowPlayingBackground.blurredCover && track != null && !LayoutPrefs.lightweight)
                ListenableBuilder(
                  listenable: VideoMode.instance,
                  builder: (context, child) =>
                      VideoMode.instance.coversBackground(track) ? const SizedBox.shrink() : child!,
                  child: RepaintBoundary(child: BlurredCover(track: track)),
                ),
              if (!coverPage && chosen == NowPlayingBackground.video && look != NowPlayingBackground.color)
                Positioned.fill(child: VideoBackground(track: track)),
              AnimatedContainer(
                duration: LayoutPrefs.dur(const Duration(milliseconds: 500)),
                decoration: coverPage
                    ? const BoxDecoration()
                    : BoxDecoration(
                        color: look == NowPlayingBackground.black ? Colors.black : null,
                        gradient: switch (look) {
                          NowPlayingBackground.color => LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.sink(accent, 0.55),
                              AppColors.sink(accent, 0.85),
                              AppColors.solidBackground,
                            ],
                            stops: const [0, 0.6, 1],
                          ),
                          // Darkens the blurred cover towards the controls, so text stays readable.
                          NowPlayingBackground.blurredCover => LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              // A moving picture needs more dimming than a still blur to keep the text readable.
                              AppColors.solidBackground.withValues(
                                alpha: chosen == NowPlayingBackground.video ? 0.55 : 0.4,
                              ),
                              AppColors.solidBackground.withValues(
                                alpha: chosen == NowPlayingBackground.video ? 0.82 : 0.75,
                              ),
                              AppColors.solidBackground,
                            ],
                            stops: [0, 0.6, 1],
                          ),
                          _ => null,
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
                        final showStrip =
                            track != null &&
                            LayoutPrefs.instance.visualizerEnabled &&
                            !LayoutPrefs.instance.visualizerStyle.radial &&
                            LayoutPrefs.moves &&
                            !MediaQuery.disableAnimationsOf(context) &&
                            !showsVideo;
                        final stripHeight = showStrip && constraints.maxHeight >= 560 ? 88.0 : 0.0;
                        // A phone held sideways: the cover goes beside the controls.
                        final sideways = constraints.maxWidth > constraints.maxHeight && constraints.maxHeight < 480;
                        Widget topBarFor({required bool more}) => Row(
                          children: [
                            IconButton(
                              tooltip: 'Close',
                              color: AppColors.of(context).textPrimary,
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    'PLAYING FROM',
                                    style: text.labelSmall?.copyWith(
                                      letterSpacing: 1.2,
                                      color: AppColors.of(context).textSecondary,
                                    ),
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
                            if (more) const _MoreButton() else const SizedBox(width: 48),
                          ],
                        );
                        final topBar = topBarFor(more: true);
                        Widget cover(double size, {double radius = 8}) => NowPlayingCover(
                          child: Hero(
                            tag: 'now-playing-art',
                            child: DecoratedBox(
                              // The video is wider than the square: a square shadow would show around it.
                              decoration: const BoxDecoration(),
                              child: TrackVisual(
                                track: track,
                                cover: SizedBox.square(
                                  dimension: size,
                                  child: AudioVisualizer(
                                    child: Artwork(track: track, size: size, radius: radius),
                                  ),
                                ),
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
                                  LinkText(
                                    track?.artist ?? '',
                                    style: text.titleMedium?.copyWith(color: AppColors.of(context).textSecondary),
                                    onTap: track == null ? null : openArtist(context, PlayerScope.read(context), track),
                                  ),
                                  if (showBadge) ...[const SizedBox(height: 8), const QualityBadge(onDark: true)],
                                ],
                              ),
                            ),
                            if (track != null)
                              LikeButton(track: track, size: 28, color: AppColors.of(context).textPrimary),
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
                                      const SeekBar(phonePlayer: true),
                                      const TransportControls(large: true),
                                      const _SecondaryRow(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        if (!LayoutPrefs.instance.classicPlayerFace) {
                          return ComposedNowPlaying(
                            track: track,
                            from: from,
                            accent: accent,
                            cover: cover,
                            classicTopBar: topBarFor,
                            showBadge: showBadge,
                          );
                        }
                        final art = largeCover
                            ? math.min(
                                constraints.maxWidth - 24,
                                constraints.maxHeight - (showBadge ? 364 : 328) - playerVolumeRowHeight - stripHeight,
                              )
                            : math.min(
                                constraints.maxWidth - 48,
                                constraints.maxHeight - (showBadge ? 400 : 364) - playerVolumeRowHeight - stripHeight,
                              );
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
                              if (stripHeight > 0) ...[
                                const AudioVisualizer(linearOnly: true, height: 80),
                                const SizedBox(height: 8),
                              ],
                              info,
                              const SizedBox(height: 16),
                              const SeekBar(phonePlayer: true),
                              const SizedBox(height: 8),
                              const TransportControls(large: true),
                              const SizedBox(height: 4),
                              const _SecondaryRow(),
                              const PlayerVolumeRow(),
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
        color: c.sleep.active || c.cast.target != null
            ? AppColors.of(context).accent
            : AppColors.of(context).textPrimary,
        onPressed: () => showPlayerMore(context, closePlayer: true),
        icon: const Icon(Icons.more_horiz_rounded, size: 28),
      ),
    );
  }
}

/// Height of the [PlayerVolumeRow] at the bottom of the portrait player.
const playerVolumeRowHeight = 40.0;

/// Volume at the very bottom of the portrait player: quieter icon, slider, louder icon. It is the
/// same level the desktop [VolumeSlider] sets (also the cast device's while casting).
class PlayerVolumeRow extends StatelessWidget {
  const PlayerVolumeRow({super.key, this.mute = false, this.shape});

  /// The left icon mutes (and unmutes) instead of turning the volume down a step.
  final bool mute;

  /// The slider's look; null follows Settings › Layout › Volume slider look.
  final VolumeSliderShape? shape;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    final colors = AppColors.of(context);
    final look = shape ?? LayoutPrefs.instance.volumeSlider;
    final thin = look == VolumeSliderShape.thin;
    final pill = look == VolumeSliderShape.pill;
    return PlayerSelect<({bool casting, double device, bool canSet, bool dop})>(
      select: (c) => (
        casting: c.casting,
        device: c.casting ? c.volume : 0,
        canSet: c.canSetVolume,
        // DoP must reach the DAC untouched: its volume is the one to use.
        dop: !c.casting && c.audio.dopPlaying != null,
      ),
      builder: (context, v, _) => ValueListenableBuilder<double>(
        valueListenable: c.volumeLevel,
        builder: (context, level, _) {
          final volume = v.dop ? 1.0 : (v.casting ? v.device : level);
          final setVolume = v.canSet && !v.dop ? c.setVolume : null;
          Widget nudge(String tooltip, IconData icon, double by) => IconButton(
            tooltip: tooltip,
            iconSize: 22,
            visualDensity: VisualDensity.compact,
            color: colors.textSecondary,
            onPressed: setVolume == null ? null : () => c.nudgeVolume(by),
            icon: Icon(icon),
          );
          return SizedBox(
            height: playerVolumeRowHeight,
            child: Row(
              children: [
                if (mute)
                  IconButton(
                    tooltip: volume == 0 ? 'Unmute' : 'Mute',
                    iconSize: 22,
                    visualDensity: VisualDensity.compact,
                    color: colors.textSecondary,
                    onPressed: setVolume == null ? null : c.toggleMute,
                    // The thin look keeps the crossed speaker at rest, like the mute button it is.
                    icon: Icon(thin || volume == 0 ? Icons.volume_off_rounded : Icons.volume_mute_rounded),
                  )
                else
                  nudge('Quieter', Icons.volume_down_rounded, -0.05),
                Expanded(
                  child: SliderTheme(
                    data: thin
                        ? thinSliderTheme(SliderTheme.of(context), colors.textPrimary)
                        : pill
                        ? pillSliderTheme(SliderTheme.of(context), colors.inverse, height: 12, thumb: 28)
                        : SliderTheme.of(context),
                    child: Slider(
                      value: volume.clamp(0, 1),
                      onChangeStart: setVolume == null ? null : (_) => c.volumeDragStarted(),
                      onChanged: setVolume,
                    ),
                  ),
                ),
                nudge('Louder', Icons.volume_up_rounded, 0.05),
              ],
            ),
          );
        },
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
          color: AppColors.of(context).textPrimary,
          onPressed: shell.openLyrics,
          icon: const Icon(Icons.lyrics_outlined),
        ),
        IconButton(
          tooltip: 'Queue',
          color: AppColors.of(context).textPrimary,
          onPressed: shell.openQueue,
          icon: const Icon(Icons.queue_music_rounded),
        ),
      ],
    );
  }
}

/// The blurred-cover background, worked out once per cover: a small decode is
/// blurred into a still image and stretched over the page. Blurring the cover
/// live cost every frame several full-window passes (the renderer keeps no
/// cache of a filtered layer), for a picture that only changes with the song.
/// Also behind the expanded player on desktop, under the Music video background.
class BlurredCover extends StatefulWidget {
  const BlurredCover({super.key, required this.track});

  final Track track;

  @override
  State<BlurredCover> createState() => _BlurredCoverState();
}

class _BlurredCoverState extends State<BlurredCover> {
  // The last one made, so reopening Now Playing on the same song draws it at once.
  static String? _lastKey;
  static ui.Image? _last;

  // Matches the old live blur: sigma 48 on a cover filling ~1600 px, at this size.
  static const _side = 64;
  static const _sigma = 2.0;

  ui.Image? _image;
  String? _key;

  String _keyOf(Track t) => t.albumKey ?? t.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BlurredCover old) {
    super.didUpdateWidget(old);
    if (_keyOf(widget.track) != _key) _load();
  }

  Future<void> _load() async {
    final key = _key = _keyOf(widget.track);
    if (key == _lastKey && _last != null) {
      _show(_last!.clone());
      return;
    }
    final bytes = Metadata.cachedThumbnail(widget.track) ?? await Metadata.thumbnail(widget.track);
    if (bytes == null || !mounted || key != _key) return;
    ui.Image? small;
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: _side, targetHeight: _side);
      small = (await codec.getNextFrame()).image;
      codec.dispose();
      final recorder = ui.PictureRecorder();
      final size = _side.toDouble();
      Canvas(recorder).drawImageRect(
        small,
        Rect.fromLTWH(0, 0, small.width.toDouble(), small.height.toDouble()),
        Rect.fromLTWH(0, 0, size, size),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..imageFilter = ui.ImageFilter.blur(sigmaX: _sigma, sigmaY: _sigma, tileMode: TileMode.clamp),
      );
      final picture = recorder.endRecording();
      final blurred = await picture.toImage(_side, _side);
      picture.dispose();
      if (!mounted || key != _key) {
        blurred.dispose();
        return;
      }
      _last?.dispose();
      _lastKey = key;
      _last = blurred;
      _show(blurred.clone());
    } catch (e) {
      debugPrint('Blurring the cover failed: $e');
    } finally {
      small?.dispose();
    }
  }

  // Each view holds its own handle, so a newer cover replacing [_last] never pulls one out from under it.
  void _show(ui.Image image) {
    _image?.dispose();
    setState(() => _image = image);
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const SizedBox.expand();
    // Stretched smoothly, the small blurred picture keeps the soft look of the live blur.
    return RawImage(
      image: image,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
