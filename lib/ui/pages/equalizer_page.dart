import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/audio_engine.dart';
import '../../services/player_controller.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/page_scaffold.dart';
import '../../services/language.dart';
import '../widgets/app_dialog.dart';
import '../widgets/auto_eq_picker.dart';
import '../../services/layout_prefs.dart';
import 'sound_settings.dart' show SettingsCard, SettingsIcon;
import 'audio_lab_page.dart';

/// Ten-band equalizer with presets. Each band's frequency and width can be
/// changed too (tap its label), which makes it a parametric EQ.
class EqualizerPage extends StatelessWidget {
  const EqualizerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final pad = ShellScope.of(context).compact ? 16.0 : 24.0;
    return PageScaffold(
      title: tr.equalizer,
      slivers: [SliverToBoxAdapter(child: EqualizerPanel(pad: pad))],
    );
  }
}

/// The equalizer itself, shared by [EqualizerPage] and the expanded player's side panel, laid out as Material 3
/// settings: a tonal card with the switch and what plays, the presets, the bands on a card of their own (a 0 dB
/// line, the scale, each band's gain over it, Reset at its foot), and the tools as the settings pages' grouped list.
/// It listens to the audio engine on its own and does not scroll.
class EqualizerPanel extends StatelessWidget {
  const EqualizerPanel({super.key, this.pad = 24});

  final double pad;

  @override
  Widget build(BuildContext context) {
    final audio = PlayerScope.of(context).audio;
    return ListenableBuilder(
      listenable: audio,
      builder: (context, _) =>
          LayoutBuilder(builder: (context, box) => _panel(context, audio, wide: box.maxWidth >= 600)),
    );
  }

  Widget _panel(BuildContext context, AudioEngine audio, {required bool wide}) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final on = audio.eqEnabled && !audio.bitPerfect;
    final muted = text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final now = !audio.eqEnabled
        ? tr.off
        : audio.eqPreset == 'Custom'
        ? (audio.eqProfile ?? tr.custom)
        : eqPresetLabel(audio.eqPreset);
    final chips = [
      for (final name in eqPresets.keys)
        ChoiceChip(
          label: Text(eqPresetLabel(name)),
          selected: audio.eqEnabled && audio.eqPreset == name,
          onSelected: audio.bitPerfect ? null : (_) => audio.applyPreset(name),
        ),
      if (audio.eqPreset == 'Custom')
        ChoiceChip(label: Text(audio.eqProfile ?? tr.custom), selected: audio.eqEnabled, onSelected: (_) {}),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The switch, and what plays now.
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: _Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SettingsIcon(Icons.equalizer_rounded),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr.equalizer, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          Text(
                            now,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(color: on ? scheme.primary : scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Switch(value: audio.eqEnabled, onChanged: audio.bitPerfect ? null : audio.setEqEnabled),
                  ],
                ),
                const SizedBox(height: 12),
                Text(audio.bitPerfect ? tr.eqBitPerfectNote : tr.eqHint, style: muted),
                // A/B: the EQ against the song as it is, at matched loudness.
                if (audio.eqEnabled && !audio.bitPerfect) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(value: false, label: Text(tr.eqCompareA)),
                          ButtonSegment(value: true, label: Text(tr.eqCompareB)),
                        ],
                        selected: {audio.abBypass},
                        onSelectionChanged: (v) => audio.setAbBypass(v.first),
                      ),
                      if (audio.abBypass && audio.abTrim < 0)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Text(tr.eqCompareNote(audio.abTrim.abs().toStringAsFixed(1)), style: muted),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        _Subheader(tr.eqPresets, pad: pad),
        // One row a phone scrolls sideways; a wide panel has room for them all.
        if (wide)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Wrap(spacing: 8, runSpacing: 8, children: chips),
          )
        else
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: pad),
              itemCount: chips.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => chips[i],
            ),
          ),
        _Subheader(tr.eqBands, pad: pad),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: _Surface(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: on && !audio.abBypass ? 1 : 0.45,
                  child: SizedBox(
                    height: wide ? 300 : 260,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The scale, beside the bands: their tracks run from +12 at the top to -12 at the foot.
                        Padding(
                          padding: const EdgeInsets.only(top: 22, bottom: 34),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (final db in const ['+12', '0', '-12'])
                                Text(db, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Stack(
                            children: [
                              // The 0 dB line, through the middle of the tracks.
                              Positioned.fill(
                                top: 22,
                                bottom: 34,
                                child: Center(child: Container(height: 1, color: scheme.outlineVariant)),
                              ),
                              Row(
                                children: [
                                  for (var i = 0; i < audio.bands.length; i++)
                                    Expanded(
                                      child: _BandSlider(index: i, band: audio.bands[i], audio: audio),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        audio.preamp < 0 ? tr.eqHeadroom(audio.preamp.toStringAsFixed(1)) : tr.eqTapBandHint,
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: audio.bitPerfect ? null : () => audio.applyPreset('Flat'),
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: Text(tr.reset),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _Subheader(tr.eqTools, pad: pad),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          // Its own Material in each row (SettingsCard's): the expanded player's side panel paints a background.
          child: SettingsCard(
            children: [
              ListTile(
                leading: const SettingsIcon(Icons.headphones_rounded),
                title: Text(tr.autoEq),
                subtitle: Text(audio.eqProfile ?? tr.autoEqPick, style: muted),
                trailing: const Icon(Icons.chevron_right_rounded),
                enabled: !audio.bitPerfect,
                onTap: () => showAutoEqPicker(context),
              ),
              ListTile(
                leading: const SettingsIcon(Icons.science_outlined),
                title: Text(tr.audioLab),
                subtitle: Text(tr.audioLabTile, style: muted),
                trailing: const Icon(Icons.chevron_right_rounded),
                enabled: !audio.bitPerfect,
                onTap: () => openAudioLab(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// A section's name over its content, as Material 3 lists name theirs: small, in the primary colour.
class _Subheader extends StatelessWidget {
  const _Subheader(this.label, {required this.pad});

  final String label;
  final double pad;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(pad + 4, 24, pad, 8),
    child: Text(
      label,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
    ),
  );
}

/// A tonal card, as the settings pages' groups are drawn (their colour and Settings › Layout › Corners).
class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.elevated,
    borderRadius: LayoutPrefs.corner(24),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

String _freq(double f) => f >= 1000 ? '${(f / 1000).toStringAsFixed(f % 1000 == 0 ? 0 : 1)}k' : f.toStringAsFixed(0);

class _BandSlider extends StatelessWidget {
  const _BandSlider({required this.index, required this.band, required this.audio});

  final int index;
  final EqBand band;
  final AudioEngine audio;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final enabled = audio.eqEnabled && !audio.bitPerfect && !audio.abBypass;
    return Column(
      children: [
        Text(
          '${band.gain > 0 ? '+' : ''}${band.gain.toStringAsFixed(band.gain % 1 == 0 ? 0 : 1)}',
          style: text.labelSmall?.copyWith(
            color: band.gain == 0
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : Theme.of(context).colorScheme.primary,
            fontWeight: band.gain == 0 ? null : FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: band.gain.clamp(-12, 12),
              min: -12,
              max: 12,
              divisions: 48,
              onChanged: enabled ? (v) => audio.setBand(index, band.copyWith(gain: v)) : null,
            ),
          ),
        ),
        Tooltip(
          message: tr.changeFrequency,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: enabled ? () => _editBand(context) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              child: Text(_freq(band.frequency), style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editBand(BuildContext context) async {
    var f = band.frequency;
    var q = band.q;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          title: Text(tr.bandNumber('${index + 1}')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.frequencyHz(_freq(f))),
              // Log scale: equal slider travel per octave.
              Slider(value: _log(f), min: _log(20), max: _log(20000), onChanged: (v) => setState(() => f = _exp(v))),
              Text(
                tr.eqBandWidth(
                  q < 1
                      ? tr.eqWidthWide
                      : q > 3
                      ? tr.eqWidthNarrow
                      : tr.eqWidthMedium,
                  q.toStringAsFixed(2),
                ),
              ),
              Slider(value: q, min: 0.3, max: 8, onChanged: (v) => setState(() => q = v)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                f = defaultEqFrequencies[index];
                q = 1.41;
                Navigator.pop(context, true);
              },
              child: Text(tr.defaultLabel),
            ),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr.done)),
          ],
        ),
      ),
    );
    if (ok == true) await audio.setBand(index, band.copyWith(frequency: f.roundToDouble(), q: q));
  }

  static double _log(double f) => math.log(f);
  static double _exp(double v) => math.exp(v);
}
