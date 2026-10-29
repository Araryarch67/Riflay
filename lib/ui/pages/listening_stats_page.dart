import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/track.dart';
import '../../services/listening_stats.dart';
import '../../services/play_history.dart';
import '../../services/player_controller.dart';
import '../../services/wrap.dart';
import '../../services/wrap_notifications.dart';
import '../navigation.dart';
import '../shell_scope.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/track_row.dart';
import 'wrap_page.dart';

/// "Your listening": what was played most this month, this year or ever, worked out from the history kept on this
/// device.
class ListeningStatsPage extends StatefulWidget {
  const ListeningStatsPage({super.key, this.history, this.now});

  /// For tests; the app's history by default.
  final PlayHistory? history;
  final DateTime? now;

  @override
  State<ListeningStatsPage> createState() => _ListeningStatsPageState();
}

class _ListeningStatsPageState extends State<ListeningStatsPage> {
  StatsPeriod _period = StatsPeriod.thisYear;
  (int, StatsPeriod, ListeningStats)? _cache;
  DateTime? _firstSeen;

  PlayHistory get _history => widget.history ?? PlayHistory.instance;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final ms = prefs.getInt(WrapNotifier.firstSeenKey);
      if (mounted && ms != null) setState(() => _firstSeen = DateTime.fromMillisecondsSinceEpoch(ms));
    }, onError: (Object _) {});
  }

  ListeningStats _stats(DateTime now) {
    final cached = _cache;
    if (cached != null && cached.$1 == _history.revision && cached.$2 == _period) return cached.$3;
    final stats = ListeningStats.compute(_history, _period, now: now);
    _cache = (_history.revision, _period, stats);
    return stats;
  }

  @override
  Widget build(BuildContext context) {
    final c = PlayerScope.read(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_history, c.libraryRevision]),
      builder: (context, _) => _build(context, c),
    );
  }

  Widget _build(BuildContext context, PlayerController c) {
    final shell = ShellScope.of(context);
    final text = Theme.of(context).textTheme;
    final pad = shell.compact ? 16.0 : 24.0;
    final now = widget.now ?? DateTime.now();
    final stats = _stats(now);
    final library = {for (final t in c.library) t.id: t};
    Track trackFor(SongInfo s) => library[s.key] ?? s.toTrack();
    final years = _history.years.where((y) => y != now.year).toList();
    final periods = [
      StatsPeriod.thisMonth,
      StatsPeriod.thisYear,
      StatsPeriod.allTime,
      for (final y in years) StatsPeriod.ofYear(y),
    ];
    final wraps = MonthlyWrap.available(_history, firstSeen: _firstSeen, now: now);

    return PageScaffold(
      title: 'Your listening',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your listening', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  'Worked out from songs you played for 30 seconds or more. It stays on this device.',
                  style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in periods)
                      ChoiceChip(
                        label: Text(p.label),
                        selected: _period == p,
                        onSelected: (_) => setState(() => _period = p),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                if (stats.isEmpty)
                  _Empty(history: _history)
                else ...[
                  _Totals(stats: stats),
                  const SizedBox(height: 24),
                  Text('Listening time', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _BarChart(bars: stats.bars),
                  const SizedBox(height: 28),
                  _Section(
                    title: 'Top songs',
                    children: [
                      for (final (i, s) in stats.topSongs.indexed)
                        _Row(
                          rank: i + 1,
                          art: Artwork(track: trackFor(s.sample), size: 48),
                          title: s.title,
                          subtitle: s.subtitle,
                          trailing: _plays(s.plays),
                          onTap: () => c.playList(
                            [for (final t in stats.topSongs) trackFor(t.sample)],
                            i,
                            from: 'Your top songs',
                          ),
                        ),
                    ],
                  ),
                  _Section(
                    title: 'Top artists',
                    children: [
                      for (final (i, a) in stats.topArtists.take(6).indexed)
                        _Row(
                          rank: i + 1,
                          art: Artwork(track: trackFor(a.sample), size: 48, circle: true),
                          title: a.title,
                          subtitle: formatListened(a.listened),
                          trailing: _plays(a.plays),
                          onTap: () => _openArtist(context, c, a, trackFor(a.sample)),
                        ),
                    ],
                  ),
                  _Section(
                    title: 'Top albums',
                    children: [
                      for (final (i, a) in stats.topAlbums.take(6).indexed)
                        _Row(
                          rank: i + 1,
                          art: Artwork(track: trackFor(a.sample), size: 48),
                          title: a.title,
                          subtitle: a.subtitle,
                          trailing: _plays(a.plays),
                          onTap: () => _openAlbum(context, c, a, trackFor(a.sample)),
                        ),
                    ],
                  ),
                ],
                if (wraps.isNotEmpty)
                  _Section(
                    title: 'Your monthly Wraps',
                    children: [
                      for (final m in wraps.take(24))
                        _Row(
                          art: const _Glyph(Icons.auto_awesome_motion_outlined),
                          title: 'Your ${m.name} in music',
                          subtitle: m.label,
                          onTap: () => shell.open(
                            WrapPage(month: m, history: widget.history),
                            location: Locations.wrap,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _plays(int n) => n == 1 ? '1 play' : '$n plays';

  void _openArtist(BuildContext context, PlayerController c, RankedItem item, Track sample) {
    final open = openArtist(context, c, sample);
    if (open != null) {
      open();
    } else {
      c.playList([sample], 0, from: item.title);
    }
  }

  void _openAlbum(BuildContext context, PlayerController c, RankedItem item, Track sample) {
    final album =
        c.albums.where((a) => a.title == item.title && a.subtitle == item.subtitle).firstOrNull ??
        c.albums.where((a) => a.title == item.title).firstOrNull;
    if (album != null) {
      ShellScope.of(context).openCollection(album);
    } else {
      c.playList([sample], 0, from: item.title);
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.history});
  final PlayHistory history;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(
      history.enabled
          ? 'Nothing here yet. Songs you listen to for 30 seconds or more will show up.'
          : 'Your listening history is off. Turn it on in Settings, under Privacy.',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
    ),
  );
}

class _Totals extends StatelessWidget {
  const _Totals({required this.stats});
  final ListeningStats stats;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget cell(String value, String label) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        Text(label, style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
      ],
    );
    return Wrap(
      spacing: 40,
      runSpacing: 16,
      children: [
        cell(formatListened(stats.listened), 'listened'),
        cell('${stats.songs}', stats.songs == 1 ? 'song' : 'songs'),
        cell('${stats.plays}', stats.plays == 1 ? 'play' : 'plays'),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => children.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        );
}

class _Glyph extends StatelessWidget {
  const _Glyph(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 48,
    child: DecoratedBox(
      decoration: BoxDecoration(color: AppColors.hover, borderRadius: BorderRadius.circular(4)),
      child: Icon(icon, color: AppColors.textPrimary),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.art,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.rank,
    this.trailing,
  });

  final int? rank;
  final Widget art;
  final String title;
  final String subtitle;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      hoverColor: AppColors.tile,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            if (rank != null)
              SizedBox(
                width: 28,
                child: Text('$rank', style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
              ),
            art,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
            if (trailing != null) Text(trailing!, style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Listening time as plain bars: a month by day, a year by month, all time by year.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.bars});
  final List<StatsBar> bars;

  @override
  Widget build(BuildContext context) {
    final peak = bars.fold<int>(0, (m, b) => b.listened.inSeconds > m ? b.listened.inSeconds : m);
    return Semantics(
      label:
          'Listening time chart. ${bars.where((b) => b.listened > Duration.zero).map((b) => '${b.name}: ${formatListened(b.listened)}').join('. ')}',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 150,
          width: double.infinity,
          child: CustomPaint(
            painter: _BarPainter(
              bars: bars,
              bar: AppColors.accent,
              empty: AppColors.tile,
              label: AppColors.textSecondary,
              peak: peak,
              labelStyle: Theme.of(context).textTheme.labelSmall ?? const TextStyle(fontSize: 11),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.bars,
    required this.bar,
    required this.empty,
    required this.label,
    required this.peak,
    required this.labelStyle,
  });

  final List<StatsBar> bars;
  final Color bar;
  final Color empty;
  final Color label;
  final int peak;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    const labelHeight = 20.0;
    final chartHeight = size.height - labelHeight;
    final slot = size.width / bars.length;
    final barWidth = (slot * 0.62).clamp(2.0, 36.0);
    // Dense charts (a month by day) name every few bars only.
    final every = slot >= 28 ? 1 : (slot >= 14 ? 2 : 5);
    for (final (i, b) in bars.indexed) {
      final x = i * slot + (slot - barWidth) / 2;
      final h = peak == 0 ? 0.0 : chartHeight * (b.listened.inSeconds / peak);
      final minimum = b.listened > Duration.zero ? 3.0 : 2.0;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, chartHeight - (h < minimum ? minimum : h), barWidth, h < minimum ? minimum : h),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, Paint()..color = b.listened > Duration.zero ? bar : empty);
      if (i % every == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: b.label,
            style: labelStyle.copyWith(color: label),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(i * slot + (slot - tp.width) / 2, chartHeight + 6));
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.bars != bars || old.bar != bar || old.empty != empty || old.label != label || old.peak != peak;
}
