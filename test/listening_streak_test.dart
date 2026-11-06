import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/listening_streak.dart';

void main() {
  int sec(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
  final today = DateTime(2026, 11, 6, 14);
  final day = ListeningStreak.dayNumberOf(today);
  List<int> daysBack(Iterable<int> back) => [for (final b in back) sec(today.subtract(Duration(days: b)))];

  test('counts the days in a row up to today, several plays a day counting once', () {
    final s = ListeningStreak.compute([
      ...daysBack([0, 0, 1, 2]),
      sec(today.subtract(const Duration(hours: 3))),
    ], today: day);
    expect(s.current, 3);
    expect(s.today, isTrue);
  });

  test('a streak lives on through today until it ends, and breaks on a day missed', () {
    expect(ListeningStreak.compute(daysBack([1, 2, 3]), today: day).current, 3, reason: 'nothing today yet');
    expect(ListeningStreak.compute(daysBack([1, 2, 3]), today: day).today, isFalse);
    expect(ListeningStreak.compute(daysBack([2, 3, 4]), today: day).current, 0, reason: 'yesterday was missed');
  });

  test('keeps the longest run, and nothing played is no streak', () {
    final s = ListeningStreak.compute(daysBack([0, 1, 10, 11, 12, 13, 14, 30]), today: day);
    expect(s.current, 2);
    expect(s.longest, 5);
    expect(ListeningStreak.compute(const [], today: day), same(ListeningStreak.none));
  });

  test('the flame turns red, gold, blue, purple, then every colour', () {
    expect(StreakTier.of(1), StreakTier.red);
    expect(StreakTier.of(9), StreakTier.red);
    expect(StreakTier.of(10), StreakTier.gold);
    expect(StreakTier.of(50), StreakTier.blue);
    expect(StreakTier.of(99), StreakTier.blue);
    expect(StreakTier.of(100), StreakTier.purple);
    expect(StreakTier.of(365), StreakTier.rainbow);
    expect(const ListeningStreak(current: 47, longest: 47, today: true).toNext, 3);
    expect(const ListeningStreak(current: 400, longest: 400, today: true).toNext, isNull);
  });
}
