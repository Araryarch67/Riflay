import 'package:flutter/material.dart';

import '../../services/karaoke.dart';
import '../../services/language.dart';
import '../../services/player_controller.dart';
import '../theme.dart';
import 'frosted.dart';

/// Karaoke, from the player: on or off, how loud the vocals stay, and how far the playing song's split is.
Future<void> showKaraoke(BuildContext context) {
  final c = PlayerScope.read(context);
  return showAppSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    backgroundColor: AppColors.elevated,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => SafeArea(child: KaraokePanel(karaoke: c.karaoke)),
  );
}

/// What a player's menu says under Karaoke while it is on: the split's progress, or nothing once it plays.
String? karaokeStatus(Karaoke k) {
  if (!k.enabled) return null;
  final percent = ((k.progress ?? 0) * 100).round();
  return switch (k.stage) {
    KaraokeStage.downloading => tr.karaokeDownloading(percent),
    KaraokeStage.reading => tr.karaokeReading,
    KaraokeStage.separating => tr.karaokeSeparating(percent),
    KaraokeStage.unsupported => tr.karaokeUnsupported,
    KaraokeStage.failed => tr.karaokeFailed,
    KaraokeStage.idle || KaraokeStage.ready => null,
  };
}

class KaraokePanel extends StatelessWidget {
  const KaraokePanel({super.key, required this.karaoke});

  final Karaoke karaoke;

  /// One stem's level: its name and percentage over a slider (off at 0).
  Widget _level(
    BuildContext context, {
    required String label,
    required double value,
    required ValueChanged<double>? onChanged,
    required ValueChanged<double>? onEnd,
  }) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Text(
                value == 0 ? tr.off : '${(value * 100).round()}%',
                style: text.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Slider(
            value: value,
            divisions: 20,
            label: '${(value * 100).round()}%',
            onChanged: onChanged,
            onChangeEnd: onEnd,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textSecondary);
    return ListenableBuilder(
      listenable: karaoke,
      builder: (context, _) {
        final k = karaoke;
        final busy =
            k.enabled &&
            const {KaraokeStage.downloading, KaraokeStage.reading, KaraokeStage.separating}.contains(k.stage);
        final status = karaokeStatus(k) ?? (k.enabled && k.stage == KaraokeStage.ready ? tr.karaokeReady : null);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              secondary: const Icon(Icons.mic_rounded),
              title: Text(tr.karaoke, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              subtitle: Text(
                !Karaoke.supported
                    ? tr.karaokeUnavailable
                    : k.modelDownloaded
                    ? tr.karaokeHint
                    : tr.karaokeDownloadNote((Karaoke.modelBytes / (1 << 20)).round()),
              ),
              value: k.enabled,
              onChanged: Karaoke.supported ? (on) => k.setEnabled(on) : null,
            ),
            if (status != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
                child: Text(status, style: muted),
              ),
            if (busy)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
                child: LinearProgressIndicator(value: k.progress),
              ),
            _level(
              context,
              label: tr.karaokeVocals,
              value: k.vocals,
              onChanged: k.enabled ? k.setVocals : null,
              onEnd: k.enabled ? (_) => k.commitLevels() : null,
            ),
            _level(
              context,
              label: tr.karaokeMusic,
              value: k.music,
              onChanged: k.enabled ? k.setMusic : null,
              onEnd: k.enabled ? (_) => k.commitLevels() : null,
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}
