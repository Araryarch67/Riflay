import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/track.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_controller.dart';
import '../../services/video_mode.dart';
import '../pages/listen_together_page.dart' show BetaBadge;
import '../theme.dart';

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
              const BetaBadge(),
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
    final mode = VideoMode.instance;
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
          if (mode.loading)
            const Positioned.fill(
              child: Center(
                child: SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                ),
              ),
            ),
        ],
      );
    }
    return ValueListenableBuilder(
      valueListenable: video.rect,
      builder: (context, rect, _) {
        final ratio = rect == null || rect.height <= 0 ? 16 / 9 : rect.width / rect.height;
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
