import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/track.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../../services/video_mode.dart';
import '../theme.dart';
import 'skeleton.dart';

/// YouTube Music's Song / Video switch, above the cover of the Now Playing
/// views. Only there when the song has a music video this device can show.
class VideoModeSwitch extends StatelessWidget {
  const VideoModeSwitch({super.key, required this.track, this.onDark = false});

  final Track? track;

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
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: onDark ? Colors.white.withValues(alpha: 0.14) : AppColors.tile,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [segment('Song', false), segment('Video', true)]),
              ),
              const SizedBox(width: 8),
            ],
          ),
        );
      },
    );
  }
}

/// The cover, or the music video in its place while Video is picked.
class TrackVisual extends StatelessWidget {
  const TrackVisual({super.key, required this.track, required this.cover});

  final Track? track;

  /// The cover art, shown in Song mode, while the video loads, and where the
  /// video has no picture for this part of the song.
  final Widget cover;

  @override
  Widget build(BuildContext context) {
    // Asks for the song's video itself: on a computer the side panel's cover is the only Now Playing view on
    // screen, with no Song / Video switch or video background to ask for it, so the cover never turned.
    final mode = VideoMode.instance..follow(PlayerScope.read(context));
    mode.lookUp(track);
    return ListenableBuilder(
      listenable: mode,
      builder: (context, _) => mode.on && mode.videoOf(track) != null ? _VideoView(cover: cover) : cover,
    );
  }
}

class _VideoView extends StatefulWidget {
  const _VideoView({required this.cover});

  final Widget cover;

  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> {
  @override
  void initState() {
    super.initState();
    VideoMode.instance.addView();
  }

  @override
  void dispose() {
    VideoMode.instance.removeView();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = VideoMode.instance;
    final video = mode.controller;
    if (video == null) {
      return Stack(
        fit: StackFit.passthrough,
        children: [
          widget.cover,
          if (mode.loading) const Positioned.fill(child: Center(child: SkeletonBox(width: 28, height: 28, radius: 14))),
        ],
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
            child: ClipRRect(
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
    final visible = TickerMode.valuesOf(context).enabled;
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
