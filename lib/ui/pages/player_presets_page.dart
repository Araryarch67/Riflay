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
            // Clears the phone's floating player and tab bar, so the last preset scrolls out from under them.
            padding: EdgeInsets.fromLTRB(16, 16, 16, 32 + MediaQuery.paddingOf(context).bottom),
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
    final line = c.textPrimary.withValues(alpha: 0.6);
    final soft = c.textPrimary.withValues(alpha: 0.2);
    final art = c.accent.withValues(alpha: 0.6);
    Widget bar(double w, double h, Color color, {double r = 2}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(r)),
    );
    Widget gap(double w) => SizedBox(width: w);
    final background = preset.cover == PlayerCover.background;
    // The cover: a rounded square, a flower (a rounder blob) or no frame, fading into the page.
    final cover = background
        ? SizedBox(
            height: 62,
            // Out past the drawing's padding, edge to edge.
            child: OverflowBox(
              minWidth: 96,
              maxWidth: 96,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [art, art.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          )
        : Container(
            height: 52,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: art,
              borderRadius: BorderRadius.circular(preset.cover == PlayerCover.flower ? 22 : 6),
            ),
          );
    final seek = switch (preset.progressShape) {
      ProgressBarShape.pill => Row(
        children: [
          bar(22, 6, c.textPrimary, r: 3),
          gap(2),
          bar(2, 12, c.textPrimary, r: 1),
          gap(2),
          Expanded(child: bar(double.infinity, 6, soft, r: 3)),
        ],
      ),
      ProgressBarShape.thin => bar(double.infinity, 2, soft, r: 1),
      _ => bar(double.infinity, 2, soft, r: 1),
    };
    return Container(
      width: 96,
      height: 176,
      padding: const EdgeInsets.all(6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.palette.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: soft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (preset.header == PlayerHeader.classic)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [bar(8, 3, line), bar(22, 3, soft), bar(8, 3, line)],
            )
          else
            Center(child: bar(preset.header == PlayerHeader.centered ? 30 : 38, 3, soft)),
          const SizedBox(height: 4),
          cover,
          const SizedBox(height: 6),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [bar(34, 4, line), const SizedBox(height: 3), bar(22, 3, soft)],
              ),
              const Spacer(),
              if (preset.titleActions == TitleActions.boxed) ...[
                // A joined pair: outer corners rounder than the inner ones.
                Container(
                  width: 11,
                  height: 12,
                  decoration: BoxDecoration(
                    color: c.textPrimary,
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(6), right: Radius.circular(2)),
                  ),
                ),
                gap(1),
                Container(
                  width: 11,
                  height: 12,
                  decoration: BoxDecoration(
                    color: c.textPrimary,
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(2), right: Radius.circular(6)),
                  ),
                ),
              ] else
                bar(9, 9, line, r: 4.5),
            ],
          ),
          const SizedBox(height: 8),
          seek,
          const SizedBox(height: 3),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [bar(8, 2, soft), bar(8, 2, soft)]),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: switch (preset.transport) {
              PlayerTransport.pill => [
                bar(14, 14, soft, r: 7),
                gap(3),
                bar(34, 14, c.textPrimary, r: 7),
                gap(3),
                bar(14, 14, soft, r: 7),
              ],
              PlayerTransport.plain => [
                bar(10, 8, line),
                gap(10),
                bar(8, 13, c.textPrimary),
                gap(10),
                bar(10, 8, line),
              ],
              PlayerTransport.classic => [
                bar(7, 7, soft),
                gap(5),
                bar(15, 15, c.textPrimary, r: 8),
                gap(5),
                bar(7, 7, soft),
              ],
            },
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: preset.bottomRow == PlayerBottomRow.classic
                ? MainAxisAlignment.spaceBetween
                : preset.bottomRow == PlayerBottomRow.chips
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.center,
            children: switch (preset.bottomRow) {
              PlayerBottomRow.chips => [
                // One outlined group, and a round white More.
                Container(
                  width: 54,
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: line, width: 1),
                  ),
                ),
                bar(12, 12, c.textPrimary, r: 6),
              ],
              PlayerBottomRow.minimal => [bar(7, 7, line), gap(8), bar(26, 10, soft, r: 5), gap(8), bar(7, 7, line)],
              PlayerBottomRow.classic => [bar(7, 7, line), bar(7, 7, line)],
            },
          ),
        ],
      ),
    );
  }
}
