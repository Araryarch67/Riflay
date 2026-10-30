import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/track.dart';
import '../../services/appearance.dart';
import '../../services/layout_prefs.dart';
import '../../services/metadata.dart';
import '../../services/player_controller.dart';
import '../debug_switches.dart';
import '../shortcuts.dart';
import '../theme.dart';

String formatDuration(Duration? d) {
  if (d == null) return '--:--';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String formatTotal(Iterable<Track> tracks) {
  final total = tracks.fold(Duration.zero, (sum, t) => sum + (t.duration ?? Duration.zero));
  if (total == Duration.zero) return '';
  final h = total.inHours, m = total.inMinutes.remainder(60);
  return h > 0 ? '$h hr $m min' : '$m min ${total.inSeconds.remainder(60)} sec';
}

/// Cover art from the file's tags, with a tinted placeholder while loading / if missing.
///
/// Anything up to about [Metadata.thumbnailSide] px is drawn from a small
/// thumbnail made once per cover, not from the full-size embedded picture.
class Artwork extends StatelessWidget implements ColorFreeSubtree {
  const Artwork({super.key, required this.track, this.size, this.radius = 4, this.circle = false, this.icon});

  final Track? track;

  /// Null means "fill the parent" (use inside AspectRatio / SizedBox).
  final double? size;
  final double radius;
  final bool circle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = track;
    Widget child;
    if (t == null) {
      child = _placeholder(null);
    } else {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final fixed = size;
      if (fixed != null) {
        child = _CoverImage(track: t, width: (fixed * dpr).round(), placeholder: _placeholder);
      } else {
        // Filling the parent: decoded at the size it's drawn, not a guess. A card
        // is smaller than 300 dp (less memory), the full player's cover larger (sharp).
        child = LayoutBuilder(
          // Keyed like the image, so the cover still fades in over the placeholder.
          key: ValueKey(t.albumKey ?? t.id),
          builder: (context, c) {
            final side = c.biggest.shortestSide.isFinite ? c.biggest.shortestSide : 300.0;
            // In 64 px steps, so a window being resized doesn't decode every cover again at each width.
            final px = ((side * dpr / 64).ceil() * 64).clamp(64, 4096);
            return _CoverImage(track: t, width: px, placeholder: _placeholder);
          },
        );
      }
    }
    final r = LayoutPrefs.radius(radius);
    return SizedBox(
      width: size,
      height: size,
      // ClipRRect / ClipOval have fast paths; a generic ClipPath per cover made scrolling heavy.
      child: circle
          ? ClipOval(child: child)
          : r == 0
          ? child
          : ClipRRect(borderRadius: BorderRadius.circular(r), child: child),
    );
  }

  // The only colour in a cover is the placeholder's, and it follows the theme by itself ([AppColors.of]): a palette
  // change leaves the covers (and their pictures) alone.
  Widget _placeholder(Track? t) =>
      _ArtPlaceholder(icon: icon ?? (circle ? Icons.person_outline_rounded : Icons.music_note_outlined));
}

class _ArtPlaceholder extends StatelessWidget {
  const _ArtPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return LayoutBuilder(
      builder: (context, c) => ColoredBox(
        color: colors.hover,
        child: Center(
          child: Icon(
            icon,
            size: c.biggest.shortestSide.isFinite ? c.biggest.shortestSide * 0.38 : 24,
            color: colors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// One cover, [width] px wide on screen. Asks for its picture and, when it
/// goes away before the file was read, takes the request back.
class _CoverImage extends StatefulWidget {
  const _CoverImage({required this.track, required this.width, required this.placeholder});

  final Track track;
  final int width;
  final Widget Function(Track?) placeholder;

  @override
  State<_CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<_CoverImage> {
  ArtworkRequest? _request;
  Future<Uint8List?>? _future;

  bool get _small => widget.width <= Metadata.thumbnailSide * 5 ~/ 4;

  Uint8List? _ready() => _small ? Metadata.cachedThumbnail(widget.track) : Metadata.cachedArtwork(widget.track);

  bool get _isReady => _small ? Metadata.hasCachedThumbnail(widget.track) : Metadata.hasCachedArtwork(widget.track);

  void _ask() {
    _request?.cancel();
    _request = null;
    _future = null;
    if (_isReady) return;
    final request = _request = ArtworkRequest();
    _future = _small
        ? Metadata.thumbnail(widget.track, request: request)
        : Metadata.artwork(widget.track, request: request);
  }

  @override
  void initState() {
    super.initState();
    _ask();
  }

  @override
  void didUpdateWidget(_CoverImage old) {
    super.didUpdateWidget(old);
    final key = widget.track.albumKey ?? widget.track.id;
    if (key != (old.track.albumKey ?? old.track.id) || (old.width <= Metadata.thumbnailSide * 5 ~/ 4) != _small) {
      _ask();
    }
  }

  @override
  void dispose() {
    _request?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    if (_isReady) return _image(_ready(), t);
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) =>
          AnimatedSwitcher(duration: LayoutPrefs.dur(const Duration(milliseconds: 250)), child: _image(snap.data, t)),
    );
  }

  Widget _image(Uint8List? bytes, Track t) {
    if (bytes == null) return widget.placeholder(t);
    return Image(
      key: ValueKey(t.albumKey ?? t.id),
      image: ResizeImage(MemoryImage(bytes), width: widget.width, allowUpscaling: false),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => widget.placeholder(t),
    );
  }
}

/// Rebuilds with the cover-art colour of [track] (falls back to a hashed hue).
class AccentBuilder extends StatelessWidget {
  const AccentBuilder({super.key, required this.track, required this.builder});

  final Track? track;
  final Widget Function(BuildContext context, Color accent) builder;

  /// Stands in for the cover's colour when cover colours are off.
  static const neutral = Color(0xFF3A3A3A);

  @override
  Widget build(BuildContext context) {
    final t = track;
    if (t == null) return builder(context, AppColors.elevated);
    final look = Appearance.instance;
    if (!look.coverColors && look.theme != ThemeChoice.dynamic) return builder(context, neutral);
    final cached = Metadata.cachedAccent(t);
    if (cached != null) return builder(context, cached);
    return FutureBuilder<Color>(
      future: Metadata.accent(t),
      builder: (context, snap) => builder(context, snap.data ?? Metadata.fallbackAccent),
    );
  }
}

/// Animated "now playing" bars.
class EqualizerIcon extends StatefulWidget {
  const EqualizerIcon({super.key, required this.playing, this.size = 16, this.color});

  final bool playing;
  final double size;

  /// The accent colour when null.
  final Color? color;

  @override
  State<EqualizerIcon> createState() => _EqualizerIconState();
}

class _EqualizerIconState extends State<EqualizerIcon> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _anim.repeat();
  }

  @override
  void didUpdateWidget(EqualizerIcon old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_anim.isAnimating) _anim.repeat();
    if (!widget.playing) _anim.stop();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const phases = [0.0, 0.35, 0.7, 0.15];
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final p in phases)
              Container(
                width: widget.size / 6,
                height: widget.size * (widget.playing ? 0.25 + 0.75 * (((_anim.value + p) % 1) - 0.5).abs() * 2 : 0.3),
                decoration: BoxDecoration(
                  color: widget.color ?? AppColors.accent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Seek slider with elapsed / total labels; drags locally and seeks on release.
/// Playback position at display rate (just_audio interpolates between engine updates).
class SeekBar extends StatefulWidget {
  const SeekBar({super.key, this.inline = false});

  /// Labels either side of the bar (desktop) instead of underneath (mobile).
  final bool inline;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue;
  bool _hovering = false;
  Stream<Duration>? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Every frame instead of every ~200 ms: the bar glides rather than ticks.
    _position ??= PlayerScope.read(context).smoothPosition();
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.read(context);
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: AppColors.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]);
    return StreamBuilder<Duration>(
      stream: _position,
      builder: (context, snapshot) {
        final duration = player.duration ?? Duration.zero;
        final position = snapshot.data ?? Duration.zero;
        final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
        final value = (_dragValue ?? position.inMilliseconds.toDouble()).clamp(0.0, max);
        final active = _hovering || _dragValue != null;
        final slider = MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: LayoutPrefs.instance.progressBar.height,
              activeTrackColor: active && widget.inline ? AppColors.accent : AppColors.textPrimary,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: active || !widget.inline
                    ? (LayoutPrefs.instance.progressBar == ProgressBarStyle.thick ? 8 : 6)
                    : 0,
                elevation: 0,
              ),
              padding: EdgeInsets.zero,
            ),
            child: SizedBox(
              height: 24,
              child: Slider(
                value: value,
                max: max,
                onChanged: duration == Duration.zero ? null : (v) => setState(() => _dragValue = v),
                onChangeEnd: (v) {
                  player.seek(Duration(milliseconds: v.round()));
                  setState(() => _dragValue = null);
                },
              ),
            ),
          ),
        );
        final elapsed = Text(formatDuration(Duration(milliseconds: value.round())), style: style);
        final total = Text(formatDuration(player.duration), style: style);
        if (widget.inline) {
          return Row(
            children: [
              SizedBox(
                width: 44,
                child: Align(alignment: Alignment.centerRight, child: elapsed),
              ),
              const SizedBox(width: 8),
              Expanded(child: slider),
              const SizedBox(width: 8),
              SizedBox(width: 44, child: total),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            slider,
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [elapsed, total]),
          ],
        );
      },
    );
  }
}

/// The big round play/pause button (white on the player, accent on headers).
class PlayButton extends StatelessWidget implements ColorFreeSelf {
  const PlayButton({
    super.key,
    required this.playing,
    required this.onPressed,
    this.size = 48,
    this.color,
    this.iconColor,
    this.loading = false,
  });

  final bool playing;
  final bool loading;
  final VoidCallback? onPressed;
  final double size;

  /// The theme's strongest contrast when null (white on dark themes).
  final Color? color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = this.color == null || this.iconColor == null ? AppColors.of(context) : null;
    final color = this.color ?? colors!.inverse;
    final iconColor = this.iconColor ?? colors!.onInverse;
    return Tooltip(
      message: tipWith(playing ? 'Pause' : 'Play', AppAction.playPause),
      child: _Pressable(
        onPressed: onPressed,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: onPressed == null ? color.withValues(alpha: 0.4) : color,
            shape: LayoutPrefs.instance.playButton == PlayButtonShape.circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: LayoutPrefs.instance.playButton == PlayButtonShape.circle
                ? null
                : BorderRadius.circular(size * 0.3),
          ),
          child: loading
              ? Padding(
                  padding: EdgeInsets.all(size * 0.3),
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: iconColor),
                )
              : AnimatedSwitcher(
                  duration: LayoutPrefs.dur(const Duration(milliseconds: 180)),
                  transitionBuilder: (child, anim) => LayoutPrefs.moves
                      ? ScaleTransition(
                          scale: Tween(
                            begin: 0.6,
                            end: 1.0,
                          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
                          child: FadeTransition(opacity: anim, child: child),
                        )
                      : FadeTransition(opacity: anim, child: child),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    key: ValueKey(playing),
                    color: iconColor,
                    size: size * 0.6,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Grows slightly on hover and shrinks on press, like streaming-app buttons.
class _Pressable extends StatefulWidget implements ColorFreeSelf {
  const _Pressable({required this.child, required this.onPressed});

  final Widget child;
  final VoidCallback? onPressed;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => enabled && LayoutPrefs.moves ? setState(() => _scale = 1.06) : null,
      onExit: (_) => setState(() => _scale = 1),
      child: GestureDetector(
        onTapDown: (_) => enabled && LayoutPrefs.moves ? setState(() => _scale = 0.94) : null,
        onTapCancel: () => setState(() => _scale = 1),
        onTapUp: (_) => setState(() => _scale = 1),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _scale,
          duration: LayoutPrefs.dur(const Duration(milliseconds: 120)),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Shuffle / previous / play-pause / next / repeat.
class TransportControls extends StatelessWidget {
  const TransportControls({super.key, this.large = false});

  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    // Only what the buttons show: a song change, a library batch or a position
    // tick no longer rebuilds them.
    return PlayerSelect<_TransportState>(
      select: (c) => (
        shuffle: c.shuffle,
        loop: c.loopMode,
        hasQueue: c.hasQueue,
        hasNext: c.hasNext,
        canPlay: c.canPlay,
        playing: c.showsPlaying,
        loading: large && c.isBuffering && c.showsPlaying,
      ),
      builder: (context, t, _) => _transport(c, t),
    );
  }

  Widget _transport(PlayerController c, _TransportState t) {
    final skipSize = large ? 40.0 : 26.0;
    final modeSize = large ? 26.0 : 20.0;
    final row = Row(
      mainAxisSize: large ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: large ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
      children: [
        ModeButton(
          tooltip: t.shuffle ? 'Disable shuffle' : 'Enable shuffle',
          active: t.shuffle,
          size: modeSize,
          icon: Icons.shuffle_rounded,
          onPressed: t.hasQueue ? c.toggleShuffle : null,
        ),
        if (!large) const SizedBox(width: 8),
        IconButton(
          tooltip: tipWith('Previous', AppAction.previous),
          iconSize: skipSize,
          color: AppColors.textPrimary,
          onPressed: t.hasQueue ? c.previous : null,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        if (!large) const SizedBox(width: 8),
        PlayButton(
          size: large ? 68 : 34,
          playing: t.playing,
          loading: t.loading,
          onPressed: t.canPlay ? c.togglePlay : null,
        ),
        if (!large) const SizedBox(width: 8),
        IconButton(
          tooltip: tipWith('Next', AppAction.next),
          iconSize: skipSize,
          color: AppColors.textPrimary,
          onPressed: t.hasNext ? c.next : null,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        if (!large) const SizedBox(width: 8),
        ModeButton(
          tooltip: switch (t.loop) {
            LoopMode.off => 'Enable repeat',
            LoopMode.all => 'Enable repeat one',
            LoopMode.one => 'Disable repeat',
          },
          active: t.loop != LoopMode.off,
          size: modeSize,
          icon: t.loop == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
          onPressed: t.hasQueue ? c.cycleLoopMode : null,
        ),
      ],
    );
    if (!large) return row;
    // The big controls need ~270px; on tinier windows they shrink instead of overflowing.
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 280
          ? row
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(width: 280, child: row),
            ),
    );
  }
}

typedef _TransportState = ({
  bool shuffle,
  LoopMode loop,
  bool hasQueue,
  bool hasNext,
  bool canPlay,
  bool playing,
  bool loading,
});

/// Toggle icon with the little active dot underneath.
/// A toggle (shuffle, repeat): accent-coloured with a dot underneath while on.
class ModeButton extends StatelessWidget {
  const ModeButton({
    super.key,
    required this.tooltip,
    required this.active,
    required this.icon,
    required this.size,
    required this.onPressed,
  });

  final String tooltip;
  final bool active;
  final IconData icon;
  final double size;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        IconButton(
          tooltip: tooltip,
          iconSize: size,
          color: active ? AppColors.accent : AppColors.textSecondary,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
        if (active)
          Positioned(
            bottom: 4,
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
            ),
          ),
      ],
    );
  }
}

class VolumeSlider extends StatelessWidget {
  const VolumeSlider({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    // While casting, the device's volume (the controller notifies on change);
    // otherwise the level notifier alone drives it.
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
          final dop = v.dop;
          final volume = dop ? 1.0 : (v.casting ? v.device : level);
          final setVolume = v.canSet && !dop ? c.setVolume : null;
          final row = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: volume == 0 ? 'Unmute' : 'Mute',
                iconSize: 20,
                onPressed: setVolume == null ? null : c.toggleMute,
                icon: Icon(
                  volume == 0
                      ? Icons.volume_off_rounded
                      : volume < 0.5
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
                ),
              ),
              SizedBox(
                width: 104,
                child: SliderTheme(
                  // Horizontal padding keeps the thumb (and its hover halo) off the window edge at 100%.
                  data: SliderTheme.of(context).copyWith(padding: const EdgeInsets.symmetric(horizontal: 8)),
                  child: Listener(
                    onPointerSignal: (e) {
                      if (e is PointerScrollEvent && setVolume != null) {
                        c.nudgeVolume(e.scrollDelta.dy < 0 ? 0.05 : -0.05);
                      }
                    },
                    child: Slider(
                      value: volume.clamp(0, 1),
                      onChangeStart: setVolume == null ? null : (_) => c.volumeDragStarted(),
                      onChanged: setVolume,
                    ),
                  ),
                ),
              ),
            ],
          );
          return dop ? Tooltip(message: 'DSD goes to your DAC as it is: use the DAC\'s volume', child: row) : row;
        },
      ),
    );
  }
}

/// Square (or round, for artists) card used in horizontal shelves and grids.
class MediaCard extends StatefulWidget implements ColorFreeSelf {
  const MediaCard({
    super.key,
    required this.track,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onPlay,
    this.circle = false,
    this.online = false,
  });

  final Track? track;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final bool circle;

  /// Streams from YouTube Music (needs internet): a small cloud before the subtitle.
  final bool online;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool _hover = false;

  // A page that is rebuilt (a colour step, a song change) hands its cards new, equal widgets: the card keeps
  // what it built until something it shows changes. Callbacks are read from [widget] when used.
  Widget? _built;
  Object? _layout;
  TextTheme? _textTheme;

  @override
  void didUpdateWidget(MediaCard old) {
    super.didUpdateWidget(old);
    if (old.track?.id != widget.track?.id ||
        old.track?.albumKey != widget.track?.albumKey ||
        old.title != widget.title ||
        old.subtitle != widget.subtitle ||
        old.circle != widget.circle ||
        old.online != widget.online ||
        (old.onPlay == null) != (widget.onPlay == null)) {
      _built = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l = LayoutPrefs.instance;
    final layout = (l.corners, l.density, LayoutPrefs.effectiveMotion);
    if (DebugSwitches.noCardCache) return _content(text);
    if (_built == null || _layout != layout || !identical(_textTheme, text)) {
      _layout = layout;
      _textTheme = text;
      _built = _content(text);
    }
    return _built!;
  }

  Widget _content(TextTheme text) {
    return MouseRegion(
      onEnter: (_) => setState(() {
        _hover = true;
        _built = null;
      }),
      onExit: (_) => setState(() {
        _hover = false;
        _built = null;
      }),
      child: _HoverFill(
        hover: _hover,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => widget.onTap(),
            borderRadius: LayoutPrefs.corner(8),
            hoverColor: Colors.transparent,
            child: Padding(
              padding: EdgeInsets.all(LayoutPrefs.dense(10, 6)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: widget.circle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
                              borderRadius: widget.circle ? null : LayoutPrefs.corner(6),
                              boxShadow: const [
                                BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 4)),
                              ],
                            ),
                            child: Artwork(track: widget.track, radius: 6, circle: widget.circle),
                          ),
                        ),
                        if (widget.onPlay != null)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: AnimatedSlide(
                              duration: LayoutPrefs.dur(const Duration(milliseconds: 180)),
                              offset: _hover || !LayoutPrefs.moves ? Offset.zero : const Offset(0, 0.25),
                              child: AnimatedOpacity(
                                duration: LayoutPrefs.dur(const Duration(milliseconds: 180)),
                                opacity: _hover ? 1 : 0,
                                child: _AccentPlayButton(
                                  onPressed: widget.onPlay == null ? null : () => widget.onPlay!(),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: LayoutPrefs.dense(10, 6)),
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: widget.circle ? TextAlign.center : TextAlign.start,
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: widget.circle ? MainAxisAlignment.center : MainAxisAlignment.start,
                    children: [
                      if (widget.online) ...[const SourceMark(online: true, size: 13), const SizedBox(width: 4)],
                      Flexible(
                        child: _SecondaryText(
                          widget.subtitle,
                          textAlign: widget.circle ? TextAlign.center : TextAlign.start,
                          style: text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// The three places a card shows a theme colour are small widgets of their own, reading it by context: a palette
// change rebuilds these and leaves the card (and its cover) as it is.

/// The card's background, which fills in on hover.
class _HoverFill extends StatelessWidget {
  const _HoverFill({required this.hover, required this.child});

  final bool hover;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fill = AppColors.of(context).hover;
    return AnimatedContainer(
      duration: LayoutPrefs.dur(const Duration(milliseconds: 160)),
      decoration: BoxDecoration(color: hover ? fill : fill.withValues(alpha: 0), borderRadius: LayoutPrefs.corner(8)),
      child: child,
    );
  }
}

/// The card's play button, in the accent colour.
class _AccentPlayButton extends StatelessWidget {
  const _AccentPlayButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return PlayButton(playing: false, size: 44, color: colors.accent, iconColor: colors.onAccent, onPressed: onPressed);
  }
}

/// A line of secondary-coloured text.
class _SecondaryText extends StatelessWidget {
  const _SecondaryText(this.text, {required this.textAlign, required this.style});

  final String text;
  final TextAlign textAlign;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: textAlign,
    style: style?.copyWith(color: AppColors.of(context).textSecondary),
  );
}

/// 2x2 grid of distinct album covers, for collections that span many albums.
class CoverMosaic extends StatelessWidget {
  const CoverMosaic({super.key, required this.tracks, this.size, this.radius = 4});

  final List<Track> tracks;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final covers = tracks.where((t) => seen.add(t.albumKey ?? t.id)).take(4).toList();
    if (covers.length < 4) {
      return Artwork(track: covers.firstOrNull, size: size, radius: radius);
    }
    final cell = size == null ? null : size! / 2;
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: LayoutPrefs.corner(radius),
        child: GridView.count(
          crossAxisCount: 2,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [for (final t in covers) Artwork(track: t, size: cell, radius: 0)],
        ),
      ),
    );
  }
}

String formatBytes(num bytes) {
  if (bytes < 1024) return '${bytes.round()} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String formatEta(Duration d) =>
    d.inMinutes >= 1 ? '${d.inMinutes}m ${d.inSeconds.remainder(60)}s left' : '${d.inSeconds}s left';

/// Where a song plays from: a cloud for YouTube Music (online), a check for
/// songs on this device (offline).
class SourceMark extends StatelessWidget {
  const SourceMark({super.key, required this.online, this.size = 14});

  final bool online;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: online ? 'YouTube Music: needs internet' : 'On this device: plays offline',
    child: Icon(
      online ? Icons.cloud_outlined : Icons.offline_pin_rounded,
      size: size,
      color: online ? AppColors.textSecondary : AppColors.accent,
    ),
  );
}

/// A panel that turns to frosted glass when that's on in Settings › Look & feel ›
/// Appearance: what scrolls behind shows through, blurred.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.color, required this.child, this.borderRadius = BorderRadius.zero});

  final Color color;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final look = Appearance.instance;
    if (!look.glass) {
      return Material(color: color, borderRadius: borderRadius, clipBehavior: Clip.antiAlias, child: child);
    }
    // Its own layer: what happens inside (a progress line ticking) does not
    // re-blur what is behind, and a colour step repaints only this panel.
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: look.blur, sigmaY: look.blur),
          child: Material(
            color: color.withValues(alpha: color.a * 0.55),
            child: child,
          ),
        ),
      ),
    );
  }
}
