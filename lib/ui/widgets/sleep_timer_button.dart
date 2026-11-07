import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/language.dart';
import '../../services/player_controller.dart';
import '../../services/sleep_timer.dart';
import '../theme.dart';
import 'app_dialog.dart';

/// The moon in the player: opens the sleep timer, and while it runs shows how long is left.
class SleepTimerButton extends StatelessWidget {
  const SleepTimerButton({super.key, this.size, this.color, this.labelBelow = false});

  final double? size;
  final Color? color;

  /// The time left goes under the moon instead of beside it, for rows with no room to spare (a phone's top bar).
  final bool labelBelow;

  @override
  Widget build(BuildContext context) {
    final sleep = PlayerScope.read(context).sleep;
    return ListenableBuilder(
      listenable: sleep,
      builder: (context, _) {
        final label = SleepTimerLabel.of(sleep, short: labelBelow);
        final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.accent,
          fontWeight: FontWeight.w600,
          fontSize: labelBelow ? 9 : null,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        final button = IconButton(
          tooltip: sleep.active ? tr.sleepTimerWith(label) : tr.sleepTimer,
          color: sleep.active ? AppColors.accent : color,
          padding: sleep.active && labelBelow ? const EdgeInsets.fromLTRB(8, 4, 8, 14) : null,
          onPressed: () => showSleepTimer(context),
          icon: Icon(sleep.active ? Icons.bedtime_rounded : Icons.bedtime_outlined, size: size),
        );
        if (!sleep.active || label.isEmpty) return button;
        if (labelBelow) {
          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              button,
              Positioned(
                bottom: 4,
                child: IgnorePointer(child: Text(label, style: style)),
              ),
            ],
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button,
            // Pulled in towards the moon; the next button keeps its own space.
            Transform.translate(
              offset: const Offset(-6, 0),
              child: Text(label, style: style),
            ),
          ],
        );
      },
    );
  }
}

/// The words for the time left: "29:41", "End of song" or "3 songs".
abstract final class SleepTimerLabel {
  static String of(SleepTimer sleep, {bool short = false}) {
    if (!sleep.active) return '';
    if (sleep.songsLeft > 1) return short ? tr.songsCount(sleep.songsLeft) : tr.songsLeft(sleep.songsLeft);
    if (sleep.mode == SleepMode.endOfSong) return short ? tr.songEndShort : tr.endOfSong;
    final left = sleep.remaining;
    return left == null ? '' : SleepTimer.clock(left);
  }
}

/// Bottom sheet on phones, dialog on a computer.
Future<void> showSleepTimer(BuildContext context) {
  final controller = PlayerScope.read(context);
  final body = PlayerScope(controller: controller, child: const SleepTimerPanel());
  if (MediaQuery.sizeOf(context).width < 700) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.elevated,
      builder: (_) => SafeArea(child: SingleChildScrollView(child: body)),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(child: body),
      ),
    ),
  );
}

/// What the sleep timer offers: the lengths to pick from, or, while it runs, the time left with "+10 minutes" and Cancel.
class SleepTimerPanel extends StatelessWidget {
  const SleepTimerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final sleep = PlayerScope.read(context).sleep;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textSecondary);
    void closeAfter(VoidCallback act) {
      act();
      Navigator.of(context).pop();
    }

    return ListenableBuilder(
      listenable: sleep,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Text(tr.sleepTimer, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (sleep.active) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Text(switch (sleep.songsLeft) {
                0 => tr.stopsIn(SleepTimerLabel.of(sleep)),
                1 => tr.stopsWhenSongEnds,
                2 => tr.stopsAfterOneMore,
                final n => tr.stopsAfterMore(n - 1),
              }, style: text.bodyMedium),
            ),
            ListTile(leading: const Icon(Icons.add_rounded), title: Text(tr.add10Minutes), onTap: sleep.extend),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: Text(tr.cancelTimer),
              onTap: () => closeAfter(sleep.cancel),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(tr.sleepTimerFades, style: muted),
            ),
            _Group(
              icon: Icons.timer_outlined,
              title: tr.afterAWhile,
              children: [
                for (final m in SleepTimer.presets)
                  _Choice(tr.minutesCount(m), onTap: () => closeAfter(() => sleep.start(Duration(minutes: m)))),
                _Choice(
                  tr.customTime,
                  icon: Icons.edit_outlined,
                  onTap: () async {
                    final picked = await showDialog<Duration>(context: context, builder: (_) => const _CustomTime());
                    if (picked == null || !context.mounted) return;
                    closeAfter(() => sleep.start(picked));
                  },
                ),
              ],
            ),
            _Group(
              icon: Icons.queue_music_rounded,
              title: tr.afterSongs,
              children: [
                _Choice(tr.endOfThisSong, onTap: () => closeAfter(sleep.startEndOfSong)),
                for (final n in SleepTimer.songPresets)
                  _Choice(tr.songsCount(n), onTap: () => closeAfter(() => sleep.startEndOfSong(n))),
              ],
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// A heading with its choices under it, wrapping onto as many lines as the sheet needs.
class _Group extends StatelessWidget {
  const _Group({required this.icon, required this.title, required this.children});

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final label = Theme.of(context).textTheme.labelLarge
        ?.copyWith(color: colors.textSecondary, fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text(title, style: label),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    );
  }
}

/// One choice: a soft pill, with an icon when it opens something more.
class _Choice extends StatelessWidget {
  const _Choice(this.label, {required this.onTap, this.icon});

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.hover,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: colors.textPrimary), const SizedBox(width: 6)],
              Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for hours and minutes.
class _CustomTime extends StatefulWidget {
  const _CustomTime();

  @override
  State<_CustomTime> createState() => _CustomTimeState();
}

class _CustomTimeState extends State<_CustomTime> {
  final _hours = TextEditingController(text: '0');
  final _minutes = TextEditingController(text: '20');

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Duration? get _picked {
    final h = int.tryParse(_hours.text.trim()) ?? 0;
    final m = int.tryParse(_minutes.text.trim()) ?? 0;
    final d = Duration(hours: h, minutes: m);
    return d > Duration.zero && d <= const Duration(hours: 24) ? d : null;
  }

  @override
  Widget build(BuildContext context) {
    Widget field(String label, TextEditingController c) => Expanded(
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _picked == null ? null : Navigator.of(context).pop(_picked),
      ),
    );
    return AppDialog(
      title: Text(tr.customTime),
      content: Row(children: [field(tr.hours, _hours), const SizedBox(width: 16), field(tr.minutes, _minutes)]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr.cancel)),
        FilledButton(
          onPressed: _picked == null ? null : () => Navigator.of(context).pop(_picked),
          child: Text(tr.start),
        ),
      ],
    );
  }
}
