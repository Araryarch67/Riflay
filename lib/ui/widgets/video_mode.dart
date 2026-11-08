import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/track.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../../services/video_mode.dart';
import '../theme.dart';
import '../player/player_glass.dart';
import '../player/video_full_view.dart';
import 'controls.dart';
import 'live_preview.dart';
import 'native_video_surface.dart';
import 'skeleton.dart';
import '../../services/language.dart';

/// YouTube Music's Song / Video switch, above the cover of the Now Playing
/// views. Only there when the song has a music video this device can show.
class VideoModeSwitch extends StatelessWidget {
  const VideoModeSwitch({super.key, required this.track, this.onDark = false, this.expandable = false});

  final Track? track;

  /// A full-screen button beside it while Video is picked: where the video's own window lies over the cover
  /// (Windows, Linux), a button drawn on the video wouldn't show.
  final bool expandable;

  /// Drawn over the phone player's dark background.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.of(context);
    final mode = VideoMode.instance..follow(c);
    mode.lookUp(track);
    return ListenableBuilder(
      listenable: mode,
      builder: (context, _) {
        final notice = mode.notice;
        final text = Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: onDark ? Colors.white70 : AppColors.textSecondary);
        if (mode.videoOf(track) == null) {
          return notice == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(notice, textAlign: TextAlign.center, style: text),
                );
        }
        final fg = onDark ? Colors.white : AppColors.textPrimary;
        Widget segment(String label, bool video) {
          final picked = mode.on == video;
          return Semantics(
            button: true,
            selected: picked,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => mode.setOn(video),
              child: AnimatedContainer(
                duration: LayoutPrefs.dur(const Duration(milliseconds: 180)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                decoration: BoxDecoration(
                  color: picked ? fg : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: picked ? (onDark ? Colors.black : AppColors.onInverse) : fg,
                  ),
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayerGlassSurface(
                radius: 22,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: LayoutPrefs.instance.playerGlassControls
                        ? Colors.transparent
                        : onDark
                        ? Colors.white.withValues(alpha: 0.14)
                        : AppColors.tile,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [segment(tr.sectionSong, false), segment(tr.kindVideo, true)],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (expandable && mode.on)
                IconButton(
                  tooltip: tr.watchVideo,
                  color: fg,
                  onPressed: () => openVideoFullView(context),
                  icon: const Icon(Icons.fullscreen_rounded),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The cover, or the music video in its place while Video is picked.
class TrackVisual extends StatelessWidget {
  const TrackVisual({
    super.key,
    required this.track,
    required this.cover,
    this.fill = false,
    this.fade,
    this.expandable = true,
  });

  final Track? track;

  /// A double tap on the video, or its full-screen button, opens it full screen ([VideoFullView]).
  final bool expandable;

  /// The video covers the whole box, cropped (the side panel's picture), rather than fitting inside it.
  final bool fill;

  /// With [fill]: the colour the picture's foot fades into (see [NativeVideoSurface.fade]).
  final Color? fade;

  /// The cover art, shown in Song mode, while the video loads, and where the
  /// video has no picture for this part of the song.
  final Widget cover;

  @override
  Widget build(BuildContext context) {
    // A preview in Settings never starts a video player.
    if (LivePreview.of(context)) return cover;
    // Asks for the song's video itself: on a computer the side panel's cover is the only Now Playing view on
    // screen, with no Song / Video switch or video background to ask for it, so the cover never turned.
    final mode = VideoMode.instance..follow(PlayerScope.read(context));
    mode.lookUp(track);
    return ListenableBuilder(
      listenable: mode,
      builder: (context, _) => mode.on && mode.videoOf(track) != null
          ? _VideoView(cover: cover, fill: fill, fade: fade, expandable: expandable)
          : cover,
    );
  }
}

class _VideoView extends StatefulWidget {
  const _VideoView({required this.cover, this.fill = false, this.fade, this.expandable = true});

  final Widget cover;
  final bool fill;
  final Color? fade;
  final bool expandable;

  @override
  State<_VideoView> createState() => _VideoViewState();
}

/// Kept routes still have mounted video widgets while Lyrics or Queue covers them. Only visible routes may
/// retain a decoder lease; the service keeps the player briefly so returning doesn't force an immediate reload.
mixin _VisibleVideoView<T extends StatefulWidget> on State<T> {
  bool _registered = false;
  bool get fullVideoView => false;

  void _register(bool visible) {
    if (visible == _registered) return;
    _registered = visible;
    visible ? VideoMode.instance.addView(full: fullVideoView) : VideoMode.instance.removeView(full: fullVideoView);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _register(
      TickerMode.valuesOf(context).enabled && ModalRoute.isCurrentOf(context) != false && !LivePreview.of(context),
    );
  }

  @override
  void deactivate() {
    _register(false);
    super.deactivate();
  }

  @override
  void dispose() {
    _register(false);
    super.dispose();
  }
}

class _VideoViewState extends State<_VideoView> with _VisibleVideoView<_VideoView> {
  /// A double tap opens the video full screen. The native video's window passes the touch through to this.
  Widget _doubleTap(Widget child) =>
      widget.expandable ? GestureDetector(onDoubleTap: () => openVideoFullView(context), child: child) : child;

  /// [child] with the full-screen button in its corner. Beside the double tap, not under it: a double-tap listener
  /// above the button would hold each of its taps back for the second one.
  Widget _withButton(Widget child) => widget.expandable
      ? Stack(
          fit: StackFit.passthrough,
          children: [
            _doubleTap(child),
            const Positioned(right: 8, bottom: 8, child: VideoExpandButton()),
          ],
        )
      : child;

  @override
  Widget build(BuildContext context) {
    final mode = VideoMode.instance;
    // Windows/Linux: a native surface covers this box; the cover shows while it is hidden. Nothing drawn here shows
    // over it: the full-screen button sits beside the Song / Video switch there.
    if (mode.nativeReady) {
      if (widget.fill) return _doubleTap(NativeVideoSurface(cover: true, fade: widget.fade, child: widget.cover));
      return Center(
        child: AspectRatio(
          aspectRatio: mode.nativeAspect,
          // The cover under it as it is: a FittedBox around a cover not laid out yet scaled by infinity.
          child: _doubleTap(NativeVideoSurface(child: ClipRect(child: widget.cover))),
        ),
      );
    }
    final video = mode.controller;
    if (video == null) {
      return _withButton(
        Stack(
          fit: StackFit.passthrough,
          children: [
            widget.cover,
            if (mode.loading)
              const Positioned.fill(child: Center(child: SkeletonBox(width: 28, height: 28, radius: 14))),
          ],
        ),
      );
    }
    return ValueListenableBuilder(
      valueListenable: video.rect,
      builder: (context, rect, _) {
        // No size yet: the texture has nothing to show, and a black box would stand where the cover was.
        if (rect == null || rect.width <= 1 || rect.height <= 0) return widget.cover;
        final ratio = rect.width / rect.height;
        return Center(
          child: AspectRatio(
            aspectRatio: ratio,
            child: _withButton(
              ClipRRect(
                borderRadius: LayoutPrefs.corner(8),
                child: Video(
                  controller: video,
                  controls: NoVideoControls,
                  fill: Colors.black,
                  // Video mode turns itself off in the background; nothing to resume.
                  pauseUponEnteringBackgroundMode: false,
                  resumeUponEnteringForegroundMode: false,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The round full-screen button in the corner of the video on the cover ([VideoFullView]).
class VideoExpandButton extends StatelessWidget {
  const VideoExpandButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tr.watchVideo,
    onPressed: () => openVideoFullView(context),
    icon: const Icon(Icons.fullscreen_rounded),
    iconSize: 22,
    style: IconButton.styleFrom(
      backgroundColor: Colors.black.withValues(alpha: 0.45),
      foregroundColor: Colors.white,
      fixedSize: const Size.square(36),
      minimumSize: const Size.square(36),
      padding: EdgeInsets.zero,
      shape: const CircleBorder(),
    ),
  );
}

/// Where Cover: Background leaves the page open over the music video behind it: a double tap there, or the button
/// in its corner, opens the video full screen. Empty while the video isn't the page's background.
class VideoBackgroundExpand extends StatelessWidget {
  const VideoBackgroundExpand({super.key, required this.track});

  final Track? track;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: VideoMode.instance,
    builder: (context, _) {
      if (!VideoMode.instance.coversBackground(track)) return const SizedBox.expand();
      return Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: () => openVideoFullView(context),
            child: const SizedBox.expand(),
          ),
          const Positioned(right: 8, bottom: 8, child: VideoExpandButton()),
        ],
      );
    },
  );
}

/// The music video, whole (letterboxed in black), for the full-screen player: the same player and picture as the
/// cover's, held on screen as a full view ([VideoMode.addView]), so a background video goes on without reloading.
/// The cover stands in while the video loads, or for a song that has none.
class VideoPicture extends StatefulWidget {
  const VideoPicture({super.key, required this.track});

  final Track? track;

  @override
  State<VideoPicture> createState() => _VideoPictureState();
}

class _VideoPictureState extends State<VideoPicture> with _VisibleVideoView<VideoPicture> {
  @override
  bool get fullVideoView => true;

  @override
  Widget build(BuildContext context) {
    final mode = VideoMode.instance..follow(PlayerScope.read(context));
    mode.lookUp(widget.track);
    return ListenableBuilder(
      listenable: mode,
      builder: (context, _) {
        final cover = LayoutBuilder(
          builder: (context, box) {
            final side = box.biggest.shortestSide * 0.8;
            return Center(
              child: Artwork(track: widget.track, size: side, radius: 8),
            );
          },
        );
        if (!mode.on || mode.videoOf(widget.track) == null) return cover;
        if (mode.nativeReady) {
          return Center(
            child: AspectRatio(
              aspectRatio: mode.nativeAspect,
              child: const NativeVideoSurface(child: ColoredBox(color: Colors.black)),
            ),
          );
        }
        final video = mode.controller;
        if (video == null) {
          return Stack(
            fit: StackFit.expand,
            children: [
              cover,
              if (mode.loading) const Center(child: SkeletonBox(width: 28, height: 28, radius: 14)),
            ],
          );
        }
        return Video(
          controller: video,
          controls: NoVideoControls,
          fit: BoxFit.contain,
          fill: Colors.black,
          pauseUponEnteringBackgroundMode: false,
          resumeUponEnteringForegroundMode: false,
        );
      },
    );
  }
}

/// The Music video Now Playing background: the song's video behind the page, cover-fit and muted. Nothing
/// until its first picture is ready, and nothing when the song has no video, Video is picked (the cover area
/// shows it then), it failed, or the performance mode is Lightweight: the page's blurred cover shows instead.
///
/// No blur here (a live blur costs several full-window passes a frame): the page's gradient above dims it.
/// The video is only fetched and decoded while this is on screen; a page covered by another one, or an app in
/// the background, lets it go.
class VideoBackground extends StatefulWidget {
  const VideoBackground({super.key, required this.track});

  final Track? track;

  @override
  State<VideoBackground> createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<VideoBackground> {
  /// 3% past each edge: more than the shortfall seen on phones, too little to notice on a picture cropped to cover.
  static const _overscan = 1.06;

  bool _registered = false;

  /// Whether this is on screen and may use the video: not covered by another page, not Lightweight.
  void _register(bool active) {
    if (active == _registered) return;
    _registered = active;
    active ? VideoMode.instance.addBackground() : VideoMode.instance.removeBackground();
  }

  @override
  void dispose() {
    _register(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = VideoMode.instance..follow(PlayerScope.read(context));
    final visible =
        TickerMode.valuesOf(context).enabled && ModalRoute.isCurrentOf(context) != false && !LivePreview.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([mode, LayoutPrefs.instance]),
      builder: (context, _) {
        final allowed = visible && !LayoutPrefs.lightweight;
        if (allowed) mode.lookUp(widget.track);
        // Only a song that has a video asks for the player (and keeps it for a moment after): one without asks nothing.
        final active = allowed && mode.videoOf(widget.track) != null;
        // Registering notifies VideoMode: after this frame, not during it.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _register(active);
        });
        final video = active ? mode.backgroundController(widget.track) : null;
        if (video == null) return const SizedBox.shrink();
        return IgnorePointer(
          child: RepaintBoundary(
            // A little larger than the page and clipped: on Android the video's picture falls a few pixels short
            // of its box (a dark strip down the right, a band along the top), which a background must not show.
            child: ClipRect(
              child: Transform.scale(
                scale: _overscan,
                child: Video(
                  controller: video,
                  controls: NoVideoControls,
                  fit: BoxFit.cover,
                  fill: Colors.black,
                  // VideoMode stops it itself when the app goes to the background.
                  pauseUponEnteringBackgroundMode: false,
                  resumeUponEnteringForegroundMode: false,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
