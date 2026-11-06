import 'listening_stats.dart';
import 'listening_streak.dart';
import 'play_history.dart';
import 'language.dart';

/// A calendar month in local time: what one Wrap covers. Or a whole year ([WrapMonth.year], month 0): the
/// yearly Wrap, with the same cards over January to December.
class WrapMonth implements Comparable<WrapMonth> {
  const WrapMonth(this.year, this.month);

  /// The whole of [year].
  const WrapMonth.year(this.year) : month = 0;

  bool get isYear => month == 0;

  /// The month [t] falls in.
  WrapMonth.of(DateTime t) : this(t.year, t.month);

  /// `2026-03`, as saved.
  static WrapMonth? parse(String? key) {
    if (RegExp(r'^\d{4}$').hasMatch(key ?? '')) return WrapMonth.year(int.parse(key!));
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(key ?? '');
    if (m == null) return null;
    final month = int.parse(m.group(2)!);
    return month < 1 || month > 12 ? null : WrapMonth(int.parse(m.group(1)!), month);
  }

  final int year;
  final int month;

  String get key => isYear ? '$year' : '$year-${month.toString().padLeft(2, '0')}';

  /// "March"; "2026" for a year.
  String get name => isYear ? '$year' : ListeningStats.months[month - 1];

  /// "March 2026"; "2026" for a year.
  String get label => isYear ? '$year' : tr.monthYear(name, '$year');

  /// Midnight of the 1st (local), inclusive.
  DateTime get start => DateTime(year, isYear ? 1 : month);

  /// Midnight of the next month's (or year's) 1st (local), exclusive.
  DateTime get end => isYear ? DateTime(year + 1) : DateTime(year, month + 1);

  WrapMonth get previous => WrapMonth.of(DateTime(year, month - 1));
  WrapMonth get next => WrapMonth.of(DateTime(year, month + 1));

  @override
  int compareTo(WrapMonth other) => (year * 13 + month).compareTo(other.year * 13 + other.month);

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
    this.until,
    this.daysListened = 0,
    this.longestStreak = 0,
    this.streakNow = 0,
  });

  final WrapMonth month;

  /// When the month is still running: the Wrap covers its start up to this moment. Null for a finished month.
  final DateTime? until;

  /// Whether the month is not over yet ("so far").
  bool get inProgress => until != null;

  /// "March 2026", or "March so far" while the month runs.
  String get title => inProgress ? tr.wrapSoFar(month.name) : month.label;
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

  /// Days of the month with at least one play, and the most of them in a row.
  final int daysListened;
  final int longestStreak;

  /// The running month: the listening streak still going (days in a row up to today, counting days before the
  /// month began). 0 for a finished month.
  final int streakNow;

  /// The streak to show off: the longer of [longestStreak] and [streakNow].
  int get bestStreak => streakNow > longestStreak ? streakNow : longestStreak;

  /// Days the Wrap covers: the whole month (or year), or up to today while it runs.
  int get days {
    final last = until ?? month.end.subtract(const Duration(days: 1));
    return DateTime(last.year, last.month, last.day).difference(month.start).inDays + 1;
  }

  /// This Wrap with [days] as [streakNow].
  WrapData withStreakNow(int days) => WrapData(
    month: month,
    listened: listened,
    plays: plays,
    songs: songs,
    artists: artists,
    topSongs: topSongs,
    topArtists: topArtists,
    topAlbum: topAlbum,
    busiestDay: busiestDay,
    busiestDayListened: busiestDayListened,
    mostReplayed: mostReplayed,
    mostReplayedCount: mostReplayedCount,
    mostReplayedDay: mostReplayedDay,
    newSongs: newSongs,
    until: until,
    daysListened: daysListened,
    longestStreak: longestStreak,
    streakNow: days,
  );

  RankedItem get topSong => topSongs.first;
  RankedItem get topArtist => topArtists.first;
}

/// Riflay Wrap: a recap of a month, once enough has been listened to. A finished month always has one to look
/// back on; the running month has one "so far" right away.
abstract final class MonthlyWrap {
  /// Plays a finished month needs to get a Wrap, and plays the running month needs to show one "so far" (low, so
  /// the cards are not empty).
  static const minPlays = 10;
  static const minPlaysSoFar = 3;

  /// Days of use before the monthly "ready" notice (not before viewing a Wrap): a brand-new user is not told about
  /// the month they had only just started.
  static const minDays = 30;

  /// Whether the person has used Riflay long enough for the notice: [minDays] since the earliest of their first
  /// recorded play and the day the app first ran ([firstSeen]).
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

  /// Whether [month] (or year) is still running at [now].
  static bool isRunning(WrapMonth month, DateTime now) =>
      month.isYear ? now.year == month.year : WrapMonth.of(now) == month;

  /// The years with a yearly Wrap as of [now], newest first: the running one from December (its Wrap up to now),
  /// and every finished year with at least [minPlaysYear] plays.
  static List<WrapMonth> yearsAvailable(PlayHistory h, {required DateTime now}) {
    final counts = <int, int>{};
    for (var i = 0; i < h.length; i++) {
      final y = DateTime.fromMillisecondsSinceEpoch(h.atSec(i) * 1000).year;
      counts[y] = (counts[y] ?? 0) + 1;
    }
    return [
      for (final MapEntry(key: y, value: n) in counts.entries)
        if (n >= minPlaysYear && (y < now.year || (y == now.year && now.month == 12))) WrapMonth.year(y),
    ]..sort((a, b) => b.compareTo(a));
  }

  /// Plays a year needs for its Wrap.
  static const minPlaysYear = 50;

  /// The Wrap of [month], or null when it had too few plays ([minPlays]; [minPlaysSoFar] for the running month).
  /// Pass [now] to get the running month's Wrap up to that moment.
  static WrapData? compute(PlayHistory h, WrapMonth month, {DateTime? now}) {
    final until = now != null && isRunning(month, now) ? now : null;
    final from = month.start.millisecondsSinceEpoch ~/ 1000;
    final to = until != null ? until.millisecondsSinceEpoch ~/ 1000 + 1 : month.end.millisecondsSinceEpoch ~/ 1000;
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
    final data = fromPlays(
      plays,
      month,
      newSongs: seenSongs.where((s) => firstOf[s] >= from && firstOf[s] < to).length,
      until: until,
    );
    if (data == null || until == null) return data;
    // The streak still going reaches back past the month's start: the whole history up to now counts.
    final upToNow = [
      for (var i = 0; i < h.length; i++)
        if (h.atSec(i) < to) h.atSec(i),
    ];
    final streak = ListeningStreak.compute(upToNow, today: ListeningStreak.dayNumberOf(until));
    return data.withStreakNow(streak.current);
  }

  /// [compute] over plays already limited to [month] ((when in seconds, song, seconds heard)).
  static WrapData? fromPlays(
    List<(int, SongInfo, int)> plays,
    WrapMonth month, {
    required int newSongs,
    DateTime? until,
  }) {
    if (plays.length < (until != null ? minPlaysSoFar : minPlays)) return null;
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
      until: until,
      daysListened: perDay.length,
      longestStreak: ListeningStreak.compute([
        for (final (at, _, _) in plays) at,
      ], today: ListeningStreak.dayNumberOf(month.start)).longest,
    );
  }

  /// The finished months with a Wrap to look back on as of [now]: enough plays ([minPlays]), newest first. The
  /// running month is not here; its Wrap "so far" comes from [compute] with [now].
  static List<WrapMonth> available(PlayHistory h, {required DateTime now}) {
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
