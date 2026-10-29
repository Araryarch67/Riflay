import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/player_controller.dart';
import '../../services/sleep_timer.dart';
import '../theme.dart';

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
          tooltip: sleep.active ? 'Sleep timer: $label' : 'Sleep timer',
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

/// The words for the time left: "29:41", or "End of song".
abstract final class SleepTimerLabel {
  static String of(SleepTimer sleep, {bool short = false}) {
    if (!sleep.active) return '';
    if (sleep.mode == SleepMode.endOfSong) return short ? 'Song end' : 'End of song';
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
      backgroundColor: AppColors.elevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            child: Text('Sleep timer', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (sleep.active) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Text(
                sleep.mode == SleepMode.endOfSong
                    ? 'The music stops when this song ends'
                    : 'The music stops in ${SleepTimerLabel.of(sleep)}',
                style: text.bodyMedium,
              ),
            ),
            ListTile(leading: const Icon(Icons.add_rounded), title: const Text('Add 10 minutes'), onTap: sleep.extend),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text('Cancel timer'),
              onTap: () => closeAfter(sleep.cancel),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('The music fades out, then stops', style: muted),
            ),
            for (final m in SleepTimer.presets)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text('$m minutes'),
                onTap: () => closeAfter(() => sleep.start(Duration(minutes: m))),
              ),
            ListTile(
              leading: const Icon(Icons.music_note_rounded),
              title: const Text('End of this song'),
              onTap: () => closeAfter(sleep.startEndOfSong),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Custom time'),
              onTap: () async {
                final picked = await showDialog<Duration>(context: context, builder: (_) => const _CustomTime());
                if (picked == null || !context.mounted) return;
                closeAfter(() => sleep.start(picked));
              },
            ),
          ],
          const SizedBox(height: 12),
        ],
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
    return AlertDialog(
      backgroundColor: AppColors.elevated,
      title: const Text('Custom time'),
      content: Row(children: [field('Hours', _hours), const SizedBox(width: 16), field('Minutes', _minutes)]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _picked == null ? null : () => Navigator.of(context).pop(_picked),
          child: const Text('Start'),
        ),
      ],
    );
  }
}
