import 'package:flutter/material.dart';

import '../../services/language.dart';
import '../../services/layout_prefs.dart';
import '../../services/listening_streak.dart';
import '../../services/play_history.dart';
import '../theme.dart';

/// The flame of [tier]: the fire icon filled with the tier's colours and lit from behind. [dim] greys it (a tier
/// not reached yet, or no streak at all).
class StreakFlame extends StatefulWidget {
  const StreakFlame({super.key, required this.tier, this.size = 22, this.dim = false, this.flicker = false});

  final StreakTier tier;
  final double size;
  final bool dim;

  /// Breathes a little, as a flame does (only with full motion).
  final bool flicker;

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<StreakFlame> with SingleTickerProviderStateMixin {
  late final _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(StreakFlame old) {
    super.didUpdateWidget(old);
    _update();
  }

  void _update() {
    final moving = widget.flicker && !widget.dim && LayoutPrefs.moves;
    if (moving && !_breath.isAnimating) {
      _breath.repeat(reverse: true);
    } else if (!moving && _breath.isAnimating) {
      _breath.stop();
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.dim ? [AppColors.textMuted, AppColors.textMuted] : widget.tier.colors;
    final flame = ShaderMask(
      blendMode: BlendMode.srcIn,
      // The tip is the lightest colour, the base the deepest.
      shaderCallback: (r) =>
          LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors).createShader(r),
      child: Icon(Icons.local_fire_department_rounded, size: widget.size, color: Colors.white),
    );
    final lit = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: widget.dim
            ? const []
            : [BoxShadow(color: colors[colors.length ~/ 2].withValues(alpha: 0.45), blurRadius: widget.size * 0.7)],
      ),
      child: flame,
    );
    if (!widget.flicker || widget.dim) return lit;
    return ScaleTransition(
      scale: Tween(begin: 0.94, end: 1.06).animate(CurvedAnimation(parent: _breath, curve: Curves.easeInOut)),
      alignment: Alignment.bottomCenter,
      child: lit,
    );
  }
}

/// The streak on Home: the flame and the number of days; a tap tells more. Nothing while the history is off or
/// empty.
class StreakBadge extends StatelessWidget {
  const StreakBadge({super.key, this.history});

  /// The history it counts; the app's own by default (tests pass theirs).
  final PlayHistory? history;

  @override
  Widget build(BuildContext context) {
    final h = history ?? PlayHistory.instance;
    return ListenableBuilder(
      listenable: h,
      builder: (context, _) {
        if (!h.enabled || h.isEmpty) return const SizedBox.shrink();
        final s = ListeningStreak.of(h);
        return Tooltip(
          message: tr.streakTooltip(s.current),
          child: InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: () => showStreak(context, history: h),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StreakFlame(tier: s.tier, size: 24, dim: s.current == 0, flicker: s.today),
                  const SizedBox(width: 4),
                  Text(
                    '${s.current}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: s.current == 0 ? AppColors.textMuted : AppColors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The streak explained: how long, whether today counts yet, the longest, and the flames still to come.
Future<void> showStreak(BuildContext context, {PlayHistory? history}) {
  final h = history ?? PlayHistory.instance;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.elevated,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (context) =>
        ListenableBuilder(listenable: h, builder: (context, _) => _StreakSheet(ListeningStreak.of(h))),
  );
}

String _flameName(StreakTier t) => switch (t) {
  StreakTier.red => tr.flameRed,
  StreakTier.gold => tr.flameGold,
  StreakTier.blue => tr.flameBlue,
  StreakTier.purple => tr.flamePurple,
  StreakTier.rainbow => tr.flameRainbow,
};

class _StreakSheet extends StatelessWidget {
  const _StreakSheet(this.s);

  final ListeningStreak s;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textSecondary);
    final next = s.tier.next;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          children: [
            Text(tr.streakTitle, style: text.titleMedium?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            StreakFlame(tier: s.tier, size: 96, dim: s.current == 0, flicker: s.today),
            const SizedBox(height: 12),
            Text(
              tr.streakDays(s.current),
              textAlign: TextAlign.center,
              style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.6),
            ),
            const SizedBox(height: 6),
            Text(
              s.current == 0
                  ? tr.streakStart
                  : s.today
                  ? tr.streakSafe
                  : tr.streakKeepGoing,
              textAlign: TextAlign.center,
              style: muted,
            ),
            if (s.longest > 0) ...[const SizedBox(height: 4), Text(tr.streakLongest(s.longest), style: muted)],
            const SizedBox(height: 24),
            // Every flame there is, the ones reached in colour, with the days each starts at.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final t in StreakTier.values)
                  Column(
                    children: [
                      StreakFlame(tier: t, size: 34, dim: s.current < t.from || s.current == 0),
                      const SizedBox(height: 4),
                      Text(
                        '${t.from == 0 ? 1 : t.from}+',
                        style: text.labelMedium?.copyWith(
                          fontWeight: t == s.tier && s.current > 0 ? FontWeight.w900 : FontWeight.w600,
                          color: s.current >= t.from && s.current > 0 ? AppColors.textPrimary : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              next == null ? tr.streakTop : tr.streakToNext(s.toNext!, _flameName(next)),
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (next != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ((s.current - s.tier.from) / (next.from - s.tier.from)).clamp(0, 1).toDouble(),
                  minHeight: 6,
                  backgroundColor: AppColors.hover,
                  color: next.colors[1],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              tr.streakRule,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
