import 'package:flutter/painting.dart';

import 'play_history.dart';

/// How a streak's flame looks: its colours rise with the streak, so a long one shows.
enum StreakTier {
  /// Under 10 days.
  red(0, [Color(0xFFFFB199), Color(0xFFFF5A36), Color(0xFFC81E1E)]),

  /// 10 to 49 days.
  gold(10, [Color(0xFFFFF1A8), Color(0xFFFFB020), Color(0xFFE85D04)]),

  /// 50 to 99 days.
  blue(50, [Color(0xFFD6F4FF), Color(0xFF4FC3F7), Color(0xFF1E5BFF)]),

  /// 100 to 364 days.
  purple(100, [Color(0xFFF3D9FF), Color(0xFFB45CFF), Color(0xFF6A1BDB)]),

  /// A year or more: every colour of the ones before it.
  rainbow(365, [Color(0xFFFFE57A), Color(0xFFFF5AC8), Color(0xFF7C5CFF), Color(0xFF38D9FF)]);

  const StreakTier(this.from, this.colors);

  /// The first day of the streak this tier starts at.
  final int from;

  /// The flame's colours, from its tip to its base.
  final List<Color> colors;

  /// The tier of a streak of [days].
  static StreakTier of(int days) => values.lastWhere((t) => days >= t.from);

  /// The tier after this one, or null at the top.
  StreakTier? get next => index + 1 < values.length ? values[index + 1] : null;
}

/// The days in a row with at least one play kept in [PlayHistory] (a song heard for 30 seconds or more).
class ListeningStreak {
  const ListeningStreak({required this.current, required this.longest, required this.today});

  static const none = ListeningStreak(current: 0, longest: 0, today: false);

  /// Days in a row up to today, or up to yesterday while today has no play yet (the streak is still alive until
  /// the day ends).
  final int current;

  /// The longest run ever kept in the history.
  final int longest;

  /// Today has a play: the streak is safe for today.
  final bool today;

  StreakTier get tier => StreakTier.of(current);

  /// Days to go to the next tier's flame, or null at the top.
  int? get toNext => switch (tier.next) {
    final next? => next.from - current,
    null => null,
  };

  /// Off with `RIFLAY_NO_STREAK_CACHE`: worked out afresh on every build.
  static const _cache = !bool.fromEnvironment('RIFLAY_NO_STREAK_CACHE');

  static int? _revision;
  static PlayHistory? _of;
  static int? _dayKept;
  static ListeningStreak _kept = none;

  /// The streak in [history] as of [now]; worked out once per change of the history (and of the day).
  static ListeningStreak of(PlayHistory history, {DateTime? now}) {
    final today = _dayNumber(now ?? DateTime.now());
    if (_cache && identical(history, _of) && history.revision == _revision && today == _dayKept && now == null) {
      return _kept;
    }
    final result = compute([for (var i = 0; i < history.length; i++) history.atSec(i)], today: today);
    if (now == null) {
      _of = history;
      _revision = history.revision;
      _dayKept = today;
      _kept = result;
    }
    return result;
  }

  /// The streak from plays at [secs] (seconds since 1970, in any order), with [today] as a local day number.
  static ListeningStreak compute(Iterable<int> secs, {required int today}) {
    final days = {for (final s in secs) _dayNumber(DateTime.fromMillisecondsSinceEpoch(s * 1000))};
    if (days.isEmpty) return none;
    final sorted = days.toList()..sort();
    var longest = 1, run = 1;
    for (var i = 1; i < sorted.length; i++) {
      run = sorted[i] == sorted[i - 1] + 1 ? run + 1 : 1;
      if (run > longest) longest = run;
    }
    final played = days.contains(today);
    var current = 0;
    for (var d = played ? today : today - 1; days.contains(d); d--) {
      current++;
    }
    return ListeningStreak(current: current, longest: longest, today: played);
  }

  /// A local calendar day as a whole number, the same across a change of daylight saving time.
  static int _dayNumber(DateTime t) => DateTime.utc(t.year, t.month, t.day).millisecondsSinceEpoch ~/ 86400000;

  /// [day] (a [DateTime]'s local date) as the day number [compute] takes.
  static int dayNumberOf(DateTime day) => _dayNumber(day);
}
