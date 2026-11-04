import 'package:flutter/material.dart';

import '../../services/appearance.dart';
import '../../services/layout_prefs.dart';
import '../../services/player_presets.dart';
import '../theme.dart';

/// Settings › Look & feel › Layout › Player › Presets: a whole look in one tap. A preset only
/// sets the individual player settings, so it is the same as setting them one by one.
class PlayerPresetsPage extends StatelessWidget {
  const PlayerPresetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPrefs.instance;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Player presets'), backgroundColor: AppColors.background),
      body: ListenableBuilder(
        listenable: Listenable.merge([p, Appearance.instance]),
        builder: (context, _) {
          final current = playerPresetName(p);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                current == null ? 'Your settings are a custom mix' : 'Your settings match $current',
                style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              for (final preset in PlayerPreset.all) ...[
                _PresetCard(preset: preset, current: preset.name == current),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.preset, required this.current});

  final PlayerPreset preset;
  final bool current;

  Future<void> _apply(BuildContext context) async {
    final n = preset.changesTo(LayoutPrefs.instance);
    if (n == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: Text('Apply ${preset.name}?'),
        content: Text(
          'This changes $n player ${n == 1 ? 'setting' : 'settings'}. You can still change each one after.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
        ],
      ),
    );
    if (ok == true) await preset.apply(LayoutPrefs.instance);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      color: colors.elevated,
      shape: RoundedRectangleBorder(
        borderRadius: LayoutPrefs.corner(12),
        side: BorderSide(color: current ? colors.accent : Colors.transparent, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _apply(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              PresetSchematic(preset: preset),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(preset.name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(preset.note, style: text.bodySmall?.copyWith(color: colors.textSecondary)),
                    const SizedBox(height: 8),
                    Text(
                      current ? 'In use' : 'Tap to apply',
                      style: text.labelMedium?.copyWith(color: current ? colors.accent : colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tiny drawing of a preset's Now Playing, made of plain boxes.
class PresetSchematic extends StatelessWidget {
  const PresetSchematic({super.key, required this.preset});

  final PlayerPreset preset;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final line = c.textPrimary.withValues(alpha: 0.5);
    final soft = c.textPrimary.withValues(alpha: 0.2);
    Widget bar(double w, double h, Color color, {double r = 2}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(r)),
    );
    Widget gap(double w) => SizedBox(width: w);
    final full = preset.cover == PlayerCover.fullBleed;
    final seekH = preset.progressShape == ProgressBarShape.pill ? 5.0 : 2.0;
    return Container(
      width: 84,
      height: 150,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: c.palette.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: soft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (preset.header == PlayerHeader.classic)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [bar(8, 3, line), bar(20, 3, soft), bar(8, 3, line)],
            )
          else
            Center(child: bar(preset.header == PlayerHeader.centered ? 28 : 34, 3, soft)),
          const SizedBox(height: 4),
          Container(
            height: full ? 54 : 44,
            margin: EdgeInsets.symmetric(horizontal: full ? 0 : 6),
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(full ? 0 : 5),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [bar(32, 4, line), const SizedBox(height: 3), bar(22, 3, soft)],
              ),
              const Spacer(),
              if (preset.titleActions == TitleActions.boxed) ...[
                bar(8, 8, c.textPrimary),
                gap(2),
                bar(8, 8, soft),
              ] else
                bar(8, 8, soft, r: 4),
            ],
          ),
          const SizedBox(height: 7),
          bar(double.infinity, seekH, soft, r: 3),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: switch (preset.transport) {
              PlayerTransport.pill => [
                bar(9, 9, soft, r: 5),
                gap(4),
                bar(26, 10, c.textPrimary, r: 5),
                gap(4),
                bar(9, 9, soft, r: 5),
              ],
              PlayerTransport.plain => [bar(8, 6, line), gap(6), bar(8, 10, c.textPrimary), gap(6), bar(8, 6, line)],
              PlayerTransport.classic => [
                bar(6, 6, soft),
                gap(5),
                bar(12, 12, c.textPrimary, r: 6),
                gap(5),
                bar(6, 6, soft),
              ],
            },
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: preset.bottomRow == PlayerBottomRow.classic
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.center,
            children: switch (preset.bottomRow) {
              PlayerBottomRow.chips => [
                for (var i = 0; i < 4; i++) ...[bar(8, 8, soft, r: 3), gap(3)],
                bar(8, 8, line, r: 4),
              ],
              PlayerBottomRow.minimal => [bar(6, 6, line), gap(6), bar(30, 8, soft, r: 4), gap(6), bar(6, 6, line)],
              PlayerBottomRow.classic => [bar(6, 6, line), bar(6, 6, line)],
            },
          ),
        ],
      ),
    );
  }
}
