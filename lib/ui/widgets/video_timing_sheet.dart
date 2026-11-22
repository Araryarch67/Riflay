import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/language.dart';
import '../../services/video_mode.dart';
import '../../services/video_timing.dart';
import '../theme.dart';
import 'frosted.dart';

/// Opens Earlier / Later controls alongside the Song / Video switch and in
/// full-screen video, where native surfaces can otherwise cover controls.
class VideoTimingButton extends StatelessWidget {
  const VideoTimingButton({super.key, required this.track, this.color});

  final Track? track;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final timing = VideoMode.instance.timingOf(track);
    if (timing == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: tr.adjustVideoTiming,
      color: color,
      icon: const Icon(Icons.timer_outlined),
      onPressed: () => showAppSheet<void>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: AppColors.elevated,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (context) => VideoTimingSheet(timing: timing, title: track!.title),
      ),
    );
  }
}

/// Half-second picture adjustments; resetting retains automatic alignment.
class VideoTimingSheet extends StatelessWidget {
  const VideoTimingSheet({super.key, required this.timing, required this.title});

  final VideoTiming timing;
  final String title;
  static const step = Duration(milliseconds: 500);

  Future<void> _set(BuildContext context, Duration shift) async {
    try {
      await timing.setShift(shift);
    } catch (e) {
      debugPrint('Video timing: could not save: $e');
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr.couldntSaveChanges)));
      }
    }
  }

  static String _describe(Duration shift) {
    if (shift == Duration.zero) return tr.onTime;
    final seconds = (shift.inMilliseconds.abs() / 1000).toStringAsFixed(1);
    return shift.isNegative ? tr.secondsEarlier(seconds) : tr.secondsLater(seconds);
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: ValueListenableBuilder<Duration>(
        valueListenable: timing,
        builder: (context, shift, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr.adjustVideoTiming,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              tr.adjustVideoTimingBody,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: () => _set(context, timing.value - step), child: Text(tr.earlier)),
                ),
                Expanded(
                  child: Text(_describe(shift), key: const ValueKey('video-timing'), textAlign: TextAlign.center),
                ),
                Expanded(
                  child: OutlinedButton(onPressed: () => _set(context, timing.value + step), child: Text(tr.later)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              child: TextButton(
                onPressed: shift == Duration.zero ? null : () => _set(context, Duration.zero),
                child: Text(tr.reset),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
