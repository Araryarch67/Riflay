import 'package:flutter/material.dart';

import '../../services/audio_engine.dart';
import '../../services/language.dart';
import '../../services/player_controller.dart';
import '../theme.dart';

/// "1.25× · +2": what Tempo & pitch are set to.
String tempoPitchLabel(AudioEngine a) => [
  if (a.effectiveTempo != 1) '${a.effectiveTempo.toStringAsFixed(2)}×',
  if (a.effectivePitch != 0) '${a.effectivePitch > 0 ? '+' : ''}${a.effectivePitch}',
].join(' · ');

/// Tempo & pitch: how fast songs play, and how many semitones higher or lower, apart from each other.
Future<void> showTempoPitch(BuildContext context) {
  final c = PlayerScope.read(context);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    backgroundColor: AppColors.elevated,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => PlayerScope(
      controller: c,
      child: const SafeArea(child: _TempoPitchSheet()),
    ),
  );
}

class _TempoPitchSheet extends StatelessWidget {
  const _TempoPitchSheet();

  @override
  Widget build(BuildContext context) {
    final a = PlayerScope.read(context).audio;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textSecondary);
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) {
        final on = a.tempoPitchActive;
        Widget row(String title, String value, Widget slider) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Text(value, style: text.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
              slider,
            ],
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(tr.tempoPitch, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: on && (a.tempo != 1 || a.pitch != 0) ? a.resetTempoPitch : null,
                    child: Text(tr.reset),
                  ),
                ],
              ),
            ),
            if (!on)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(tr.tempoPitchOff, style: muted),
              ),
            row(
              tr.tempo,
              a.tempo == 1 ? tr.asRecorded : '${a.tempo.toStringAsFixed(2)}×',
              Slider(
                value: a.tempo,
                min: 0.5,
                max: 2,
                divisions: 30,
                label: '${a.tempo.toStringAsFixed(2)}×',
                onChanged: on ? a.setTempo : null,
              ),
            ),
            row(
              tr.pitch,
              a.pitch == 0 ? tr.asRecorded : '${a.pitch > 0 ? '+' : ''}${tr.semitones(a.pitch)}',
              Slider(
                value: a.pitch.toDouble(),
                min: -12,
                max: 12,
                divisions: 24,
                label: '${a.pitch > 0 ? '+' : ''}${a.pitch}',
                onChanged: on ? (v) => a.setPitch(v.round()) : null,
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}
