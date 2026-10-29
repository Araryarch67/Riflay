import 'play_history.dart';
import '../models/track.dart';

enum StatsPeriodKind { month, year, all, pastYear }

/// What span of the history the stats page shows.
class StatsPeriod {
  const StatsPeriod._(this.kind, [this.year]);

  static const thisMonth = StatsPeriod._(StatsPeriodKind.month);
  static const thisYear = StatsPeriod._(StatsPeriodKind.year);
  static const allTime = StatsPeriod._(StatsPeriodKind.all);
  const StatsPeriod.ofYear(int year) : this._(StatsPeriodKind.pastYear, year);

  final StatsPeriodKind kind;
  final int? year;

  String get label => switch (kind) {
    StatsPeriodKind.month => 'This month',
    StatsPeriodKind.year => 'This year',
    StatsPeriodKind.all => 'All time',
    StatsPeriodKind.pastYear => '$year',
  };

  /// Start (inclusive) and end (exclusive) in local time; null for all time.
  (DateTime, DateTime)? range(DateTime now) => switch (kind) {
    StatsPeriodKind.month => (DateTime(now.year, now.month), DateTime(now.year, now.month + 1)),
    StatsPeriodKind.year => (DateTime(now.year), DateTime(now.year + 1)),
    StatsPeriodKind.pastYear => (DateTime(year!), DateTime(year! + 1)),
    StatsPeriodKind.all => null,
  };

  @override
  bool operator ==(Object other) => other is StatsPeriod && other.kind == kind && other.year == year;

  @override
  int get hashCode => Object.hash(kind, year);
}

/// A song, artist or album in a top list.
class RankedItem {
  const RankedItem({
    required this.title,
    required this.subtitle,
    required this.plays,
    required this.listened,
    required this.sample,
  });

  final String title;
  final String subtitle;
  final int plays;
  final Duration listened;

  /// A song to show the cover of (and to play when it is tapped): for an artist or album, its most played one.
  final SongInfo sample;
}

/// One bar of the chart.
class StatsBar {
  const StatsBar(this.label, this.name, this.listened);
  final String label;

  /// Spoken / long name ("March 2026").
  final String name;
  final Duration listened;
}

class ListeningStats {
  const ListeningStats({
    required this.listened,
    required this.plays,
    required this.songs,
    required this.topSongs,
    required this.topArtists,
    required this.topAlbums,
    required this.bars,
  });

  final Duration listened;
  final int plays;

  /// Different songs heard.
  final int songs;
  final List<RankedItem> topSongs;
  final List<RankedItem> topArtists;
  final List<RankedItem> topAlbums;
  final List<StatsBar> bars;

  bool get isEmpty => plays == 0;

  static const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// The artist a song counts for: a streamed song lists several ("A, B"); the first gets the play.
  static String artistOf(SongInfo s) => s.videoId != null ? s.artist.split(', ').first : s.artist;

  static ListeningStats compute(PlayHistory h, StatsPeriod period, {DateTime? now, int top = 10}) {
    now ??= DateTime.now();
    final range = period.range(now);
    final from = range == null ? null : range.$1.millisecondsSinceEpoch ~/ 1000;
    final to = range == null ? null : range.$2.millisecondsSinceEpoch ~/ 1000;
    return fromPlays(
      [
        for (var i = 0; i < h.length; i++)
          if ((from == null || h.atSec(i) >= from) && (to == null || h.atSec(i) < to))
            (h.atSec(i), h.songInfo(h.songIndex(i)), h.heardSec(i)),
      ],
      period,
      now: now,
      top: top,
    );
  }

  /// Stats of [plays] ((when in seconds, song, seconds heard)), already limited to [period].
  static ListeningStats fromPlays(
    List<(int, SongInfo, int)> plays,
    StatsPeriod period, {
    required DateTime now,
    int top = 10,
  }) {
    final bySong = <String, _Tally>{};
    final byArtist = <String, _Tally>{};
    final byAlbum = <String, _Tally>{};
    var total = 0;
    for (final (_, s, heard) in plays) {
      total += heard;
      (bySong[s.key] ??= _Tally(s.title, s.artist, s)).add(heard, s);
      final artist = artistOf(s);
      if (artist != Track.unknownArtist) (byArtist[artist.toLowerCase()] ??= _Tally(artist, '', s)).add(heard, s);
      if (s.album != null) {
        (byAlbum['${s.album!.toLowerCase()}|${artist.toLowerCase()}'] ??= _Tally(s.album!, artist, s)).add(heard, s);
      }
    }
    return ListeningStats(
      listened: Duration(seconds: total),
      plays: plays.length,
      songs: bySong.length,
      topSongs: _rank(bySong.values, top, (t) => t.title, (t) => t.subtitle),
      topArtists: _rank(byArtist.values, top, (t) => t.title, (t) => ''),
      topAlbums: _rank(byAlbum.values, top, (t) => t.title, (t) => t.subtitle),
      bars: _bars(plays, period, now),
    );
  }

  static List<RankedItem> _rank(
    Iterable<_Tally> tallies,
    int top,
    String Function(_Tally) title,
    String Function(_Tally) subtitle,
  ) {
    final sorted = tallies.toList()
      ..sort((a, b) {
        final byPlays = b.plays.compareTo(a.plays);
        if (byPlays != 0) return byPlays;
        final byTime = b.seconds.compareTo(a.seconds);
        return byTime != 0 ? byTime : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    return [
      for (final t in sorted.take(top))
        RankedItem(
          title: title(t),
          subtitle: subtitle(t),
          plays: t.plays,
          listened: Duration(seconds: t.seconds),
          sample: t.best,
        ),
    ];
  }

  static List<StatsBar> _bars(List<(int, SongInfo, int)> plays, StatsPeriod period, DateTime now) {
    DateTime when((int, SongInfo, int) p) => DateTime.fromMillisecondsSinceEpoch(p.$1 * 1000);
    List<StatsBar> months12(int year) {
      final sums = List.filled(12, 0);
      for (final p in plays) {
        final d = when(p);
        if (d.year == year) sums[d.month - 1] += p.$3;
      }
      return [for (var m = 0; m < 12; m++) StatsBar(months[m][0], '${months[m]} $year', Duration(seconds: sums[m]))];
    }

    switch (period.kind) {
      case StatsPeriodKind.month:
        final days = DateTime(now.year, now.month + 1, 0).day;
        final sums = List.filled(days, 0);
        for (final p in plays) {
          final d = when(p);
          if (d.year == now.year && d.month == now.month) sums[d.day - 1] += p.$3;
        }
        return [
          for (var d = 0; d < days; d++)
            StatsBar('${d + 1}', '${months[now.month - 1]} ${d + 1}', Duration(seconds: sums[d])),
        ];
      case StatsPeriodKind.year:
        return months12(now.year);
      case StatsPeriodKind.pastYear:
        return months12(period.year!);
      case StatsPeriodKind.all:
        if (plays.isEmpty) return months12(now.year);
        final first = plays.map((p) => when(p).year).reduce((a, b) => a < b ? a : b);
        final last = plays.map((p) => when(p).year).reduce((a, b) => a > b ? a : b);
        if (first == last) return months12(first);
        final sums = List.filled(last - first + 1, 0);
        for (final p in plays) {
          sums[when(p).year - first] += p.$3;
        }
        return [
          for (var y = 0; y < sums.length; y++)
            StatsBar("'${((first + y) % 100).toString().padLeft(2, '0')}", '${first + y}', Duration(seconds: sums[y])),
        ];
    }
  }
}

class _Tally {
  _Tally(this.title, this.subtitle, this.best);
  final String title;
  final String subtitle;
  SongInfo best;
  int plays = 0;
  int seconds = 0;
  final _songPlays = <String, int>{};
  int _bestPlays = 0;

  void add(int heard, SongInfo s) {
    plays++;
    seconds += heard;
    final n = _songPlays[s.key] = (_songPlays[s.key] ?? 0) + 1;
    if (n > _bestPlays) {
      _bestPlays = n;
      best = s;
    }
  }
}

/// "12 h 40 min", "35 min", "1 min".
String formatListened(Duration d) {
  final minutes = d.inMinutes;
  if (minutes < 1) return d.inSeconds < 1 ? '0 min' : '1 min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return h == 0 ? '$m min' : (m == 0 ? '$h h' : '$h h $m min');
}
