import 'package:flutter/material.dart';

import '../../services/language.dart';
import '../theme.dart';

/// "How it works", folded: a task's steps, numbered, for a task people would otherwise guess their way through
/// (importing a playlist, adding a folder, a backup). Closed until asked, so it costs one line.
class HowToSteps extends StatelessWidget {
  const HowToSteps({super.key, required this.steps, this.inset = true});

  final List<String> steps;

  /// False inside a dialog, whose content already has its own margin.
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return ExpansionTile(
      leading: const Icon(Icons.help_outline_rounded),
      title: Text(tr.howItWorks),
      tilePadding: inset ? null : EdgeInsets.zero,
      childrenPadding: EdgeInsets.fromLTRB(inset ? 16 : 0, 0, inset ? 16 : 0, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      shape: const Border(),
      collapsedShape: const Border(),
      children: [
        for (final (i, step) in steps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: colors.accent.withValues(alpha: 0.18), shape: BoxShape.circle),
                  child: Text('${i + 1}', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(step, style: text.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}
