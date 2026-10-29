import 'listening_stats.dart';
import 'play_history.dart';

/// A calendar month in local time: what one Wrap covers.
class WrapMonth implements Comparable<WrapMonth> {
  const WrapMonth(this.year, this.month);

  /// The month [t] falls in.
  WrapMonth.of(DateTime t) : this(t.year, t.month);

  /// `2026-03`, as saved.
  static WrapMonth? parse(String? key) {
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(key ?? '');
    if (m == null) return null;
    final month = int.parse(m.group(2)!);
    return month < 1 || month > 12 ? null : WrapMonth(int.parse(m.group(1)!), month);
  }

  final int year;
  final int month;

  String get key => '$year-${month.toString().padLeft(2, '0')}';

  /// "March".
  String get name => ListeningStats.months[month - 1];

  /// "March 2026".
  String get label => '$name $year';

  /// Midnight of the 1st (local), inclusive.
  DateTime get start => DateTime(year, month);

  /// Midnight of the next month's 1st (local), exclusive.
  DateTime get end => DateTime(year, month + 1);

  WrapMonth get previous => WrapMonth.of(DateTime(year, month - 1));
  WrapMonth get next => WrapMonth.of(DateTime(year, month + 1));

  @override
  int compareTo(WrapMonth other) => (year * 12 + month).compareTo(other.year * 12 + other.month);

  @override
  bool operator ==(Object other) => other is WrapMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => key;
}

/// The numbers of one month's Wrap.
class WrapData {
  const WrapData({
    required this.month,
    required this.listened,
    required this.plays,
    required this.songs,
    required this.artists,
    required this.topSongs,
    required this.topArtists,
    required this.topAlbum,
    required this.busiestDay,
    required this.busiestDayListened,
    required this.mostReplayed,
    required this.mostReplayedCount,
    required this.mostReplayedDay,
    required this.newSongs,
  });

  final WrapMonth month;
  final Duration listened;
  final int plays;

  /// Different songs and artists heard.
  final int songs;
  final int artists;
  final List<RankedItem> topSongs;
  final List<RankedItem> topArtists;
  final RankedItem? topAlbum;

  /// The day (midnight, local) with the most listening, and how much.
  final DateTime busiestDay;
  final Duration busiestDayListened;

  /// The song played most times in one day (null when nothing was played twice in a day), how often, and the day.
  final SongInfo? mostReplayed;
  final int mostReplayedCount;
  final DateTime? mostReplayedDay;

  /// Songs whose first play ever was this month.
  final int newSongs;

  RankedItem get topSong => topSongs.first;
  RankedItem get topArtist => topArtists.first;
}

/// Riflay Wrap: a recap of a finished month, once enough has been listened to.
abstract final class MonthlyWrap {
  /// Days of use before the first Wrap, and plays a month needs to get one.
  static const minDays = 30;
  static const minPlays = 10;

  /// Whether the person has used Riflay long enough: [minDays] since the earliest of their first recorded play and
  /// the day the app first ran ([firstSeen]).
  static bool unlocked({DateTime? firstPlay, DateTime? firstSeen, required DateTime now}) {
    final since = [?firstPlay, ?firstSeen].fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    return since != null && now.difference(since) >= const Duration(days: minDays);
  }

  /// When the first play was, from the history (null when it is empty).
  static DateTime? firstPlayOf(PlayHistory h) {
    if (h.isEmpty) return null;
    var first = h.atSec(0);
    for (var i = 1; i < h.length; i++) {
      if (h.atSec(i) < first) first = h.atSec(i);
    }
    return DateTime.fromMillisecondsSinceEpoch(first * 1000);
  }

  /// Plays in [month].
  static int playsIn(PlayHistory h, WrapMonth month) {
    final from = month.start.millisecondsSinceEpoch ~/ 1000;
    final to = month.end.millisecondsSinceEpoch ~/ 1000;
    var n = 0;
    for (var i = 0; i < h.length; i++) {
      if (h.atSec(i) >= from && h.atSec(i) < to) n++;
    }
    return n;
  }

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  /// The Wrap of [month], or null when it had fewer than [minPlays] plays.
  static WrapData? compute(PlayHistory h, WrapMonth month) {
    final from = month.start.millisecondsSinceEpoch ~/ 1000;
    final to = month.end.millisecondsSinceEpoch ~/ 1000;
    final firstOf = List<int>.filled(h.songCount, 1 << 60);
    for (var i = 0; i < h.length; i++) {
      final s = h.songIndex(i);
      if (h.atSec(i) < firstOf[s]) firstOf[s] = h.atSec(i);
    }
    final plays = <(int, SongInfo, int)>[];
    final seenSongs = <int>{};
    for (var i = 0; i < h.length; i++) {
      final at = h.atSec(i);
      if (at >= from && at < to) {
        plays.add((at, h.songInfo(h.songIndex(i)), h.heardSec(i)));
        seenSongs.add(h.songIndex(i));
      }
    }
    return fromPlays(plays, month, newSongs: seenSongs.where((s) => firstOf[s] >= from && firstOf[s] < to).length);
  }

  /// [compute] over plays already limited to [month] ((when in seconds, song, seconds heard)).
  static WrapData? fromPlays(List<(int, SongInfo, int)> plays, WrapMonth month, {required int newSongs}) {
    if (plays.length < minPlays) return null;
    final stats = ListeningStats.fromPlays(plays, StatsPeriod.ofYear(month.year), now: month.start, top: 5);
    final artists = {
      for (final p in plays)
        if (ListeningStats.artistOf(p.$2) != 'Unknown artist') ListeningStats.artistOf(p.$2).toLowerCase(),
    };

    final perDay = <DateTime, int>{};
    final perDaySong = <(DateTime, String), (int, int, SongInfo)>{};
    for (final (at, s, heard) in plays) {
      final day = _day(DateTime.fromMillisecondsSinceEpoch(at * 1000));
      perDay[day] = (perDay[day] ?? 0) + heard;
      final old = perDaySong[(day, s.key)];
      perDaySong[(day, s.key)] = ((old?.$1 ?? 0) + 1, (old?.$2 ?? 0) + heard, s);
    }
    final days = perDay.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    final again = perDaySong.entries.toList()
      ..sort((a, b) {
        final c = b.value.$1.compareTo(a.value.$1);
        if (c != 0) return c;
        final byTime = b.value.$2.compareTo(a.value.$2);
        return byTime != 0 ? byTime : a.key.$1.compareTo(b.key.$1);
      });
    final replay = again.first.value.$1 >= 2 ? again.first : null;

    return WrapData(
      month: month,
      listened: stats.listened,
      plays: stats.plays,
      songs: stats.songs,
      artists: artists.length,
      topSongs: stats.topSongs,
      topArtists: stats.topArtists,
      topAlbum: stats.topAlbums.firstOrNull,
      busiestDay: days.first.key,
      busiestDayListened: Duration(seconds: days.first.value),
      mostReplayed: replay?.value.$3,
      mostReplayedCount: replay?.value.$1 ?? 0,
      mostReplayedDay: replay?.key.$1,
      newSongs: newSongs,
    );
  }

  /// The months with a Wrap ready as of [now]: finished months with enough plays, newest first, and none at all
  /// before the first [minDays] of use.
  static List<WrapMonth> available(PlayHistory h, {DateTime? firstSeen, required DateTime now}) {
    if (!unlocked(firstPlay: firstPlayOf(h), firstSeen: firstSeen, now: now)) return const [];
    final counts = <WrapMonth, int>{};
    for (var i = 0; i < h.length; i++) {
      final m = WrapMonth.of(DateTime.fromMillisecondsSinceEpoch(h.atSec(i) * 1000));
      counts[m] = (counts[m] ?? 0) + 1;
    }
    final current = WrapMonth.of(now);
    return [
      for (final e in counts.entries)
        if (e.value >= minPlays && e.key.compareTo(current) < 0) e.key,
    ]..sort((a, b) => b.compareTo(a));
  }

  /// The next 1st of a month, 10:00 local, that is still ahead of [now].
  static DateTime nextRelease(DateTime now) {
    final thisMonth = DateTime(now.year, now.month, 1, 10);
    return now.isBefore(thisMonth) ? thisMonth : DateTime(now.year, now.month + 1, 1, 10);
  }

  /// Which month to announce now, or null. [lastNotified] is the latest month already announced: a month is never
  /// announced twice, nor one older than that.
  static WrapMonth? dueNotice({
    required bool enabled,
    required List<WrapMonth> available,
    required WrapMonth? lastNotified,
    required DateTime now,
  }) {
    if (!enabled) return null;
    final previous = WrapMonth.of(now).previous;
    if (!available.contains(previous)) return null;
    if (lastNotified != null && lastNotified.compareTo(previous) >= 0) return null;
    return previous;
  }
}
