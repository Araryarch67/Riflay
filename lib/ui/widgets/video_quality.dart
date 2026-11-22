import 'package:flutter/material.dart';

import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/video_mode.dart';
import '../theme.dart';
import 'menus.dart';

/// "1080p", "720p", "2160p 4K": a height as YouTube's quality menu names it.
String videoQualityLabel(int height) => switch (height) {
  >= 4320 => '${height}p 8K',
  >= 2160 => '${height}p 4K',
  >= 720 => '${height}p HD',
  _ => '${height}p',
};

/// The heights Settings offers before a video has said which it has.
const videoQualitySteps = [2160, 1440, 1080, 720, 480, 360, 240, 144];

/// YouTube's gear on the video: a menu of Auto and the heights the video playing offers, the picked one checked.
/// Picking one switches the video in place (the song plays on) and keeps it as the default
/// ([LayoutPrefs.videoQuality]). Empty while no streamed video shows (a Canvas, a downloaded video, still loading).
class VideoQualityButton extends StatelessWidget {
  const VideoQualityButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([VideoMode.instance, LayoutPrefs.instance]),
    builder: (context, _) {
      final mode = VideoMode.instance;
      final heights = mode.qualities;
      if (heights.isEmpty) return const SizedBox.shrink();
      final picked = LayoutPrefs.instance.videoQuality;
      final now = mode.streamHeight;
      final text = Theme.of(context).textTheme.bodyMedium;
      // A height picked for another video that this one lacks: it plays the nearest below, and that row is checked.
      final checked = picked == 0 ? 0 : (heights.contains(picked) ? picked : now);
      Widget row(int height, String label) {
        final on = height == checked;
        return MenuItemButton(
          key: ValueKey('video-quality-$height'),
          onPressed: () => mode.setQuality(height),
          style: MenuItemButton.styleFrom(
            minimumSize: const Size(180, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            foregroundColor: AppColors.textPrimary,
          ),
          leadingIcon: SizedBox(
            width: 20,
            child: on ? Icon(Icons.check_rounded, size: 18, color: AppColors.accent) : null,
          ),
          child: Text(
            label,
            style: text?.copyWith(
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
              color: on ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
        );
      }

      return MenuAnchor(
        alignmentOffset: const Offset(0, 4),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.menu),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(menuShape),
          elevation: const WidgetStatePropertyAll(12),
          shadowColor: const WidgetStatePropertyAll(Colors.black),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
          maximumSize: const WidgetStatePropertyAll(Size(320, 480)),
        ),
        menuChildren: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Text(
              tr.videoQuality,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          row(0, now > 0 ? tr.videoQualityAutoNow('${now}p') : tr.videoQualityAuto),
          for (final h in heights) row(h, videoQualityLabel(h)),
        ],
        builder: (context, controller, _) => IconButton(
          key: const ValueKey('video-quality-button'),
          tooltip: tr.videoQuality,
          color: color,
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Icons.settings_outlined),
        ),
      );
    },
  );
}
