import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/download_notifications.dart';
import 'package:riflay/services/listening_streak.dart';
import 'package:riflay/services/play_history.dart';
import 'package:riflay/services/streak_reminder.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSink implements StreakNoteSink {
  FakeSink({this.canSchedule = true});
  @override
  final bool canSchedule;
  final shown = <int>[];
  final scheduled = <(int, DateTime)>[];
  int cancelled = 0;

  @override
  Future<void> show(int days) async => shown.add(days);
  @override
  Future<void> schedule(int days, DateTime at) async => scheduled.add((days, at));
  @override
  Future<void> cancelScheduled() async => cancelled++;
}

Track song(String name) =>
    Track(id: 'file:///m/$name.mp3', uri: Uri.parse('file:///m/$name.mp3'), title: name, artist: 'A');

void main() {
  const seven = 19 * 60;
  final evening = DateTime(2026, 11, 23, 19);
  const alive = ListeningStreak(current: 4, longest: 9, today: false);
  const kept = ListeningStreak(current: 5, longest: 9, today: true);

  group('shouldNotify', () {
    bool check({bool enabled = true, ListeningStreak streak = alive, DateTime? now, int minute = seven, int? last}) =>
        StreakReminder.shouldNotify(
          enabled: enabled,
          streak: streak,
          now: now ?? evening,
          minute: minute,
          lastNotifiedDay: last,
        );

    test('at the chosen time, with a streak alive and nothing played today', () {
      expect(check(), isTrue);
      expect(check(now: evening.add(const Duration(hours: 4))), isTrue, reason: 'late, e.g. after a sleep');
    });

    test('not before the time, not when off, not once today is kept, not twice a day', () {
      expect(check(now: evening.subtract(const Duration(minutes: 1))), isFalse);
      expect(check(enabled: false), isFalse);
      expect(check(streak: kept), isFalse);
      expect(check(last: ListeningStreak.dayNumberOf(evening)), isFalse);
      expect(check(last: ListeningStreak.dayNumberOf(evening) - 1), isTrue, reason: "yesterday's doesn't count");
    });

    test('nothing at stake is no reminder', () {
      expect(check(streak: ListeningStreak.none), isFalse);
    });
  });

  group('next', () {
    StreakReminderPlan? plan(ListeningStreak streak, DateTime now, {bool enabled = true}) =>
        StreakReminder.next(enabled: enabled, streak: streak, now: now, minute: seven);

    test("today's time while today isn't kept yet, with the days at stake", () {
      expect(plan(alive, DateTime(2026, 11, 23, 9)), (at: evening, days: 4));
    });

    test("tomorrow's once today is kept, guarding today's count", () {
      expect(plan(kept, DateTime(2026, 11, 23, 9)), (at: DateTime(2026, 11, 24, 19), days: 5));
      expect(plan(kept, DateTime(2026, 11, 30, 23)), (at: DateTime(2026, 12, 1, 19), days: 5), reason: 'month end');
    });

    test('none past the time with the streak ending tonight, with no streak, or when off', () {
      expect(plan(alive, DateTime(2026, 11, 23, 20)), isNull);
      expect(plan(ListeningStreak.none, DateTime(2026, 11, 23, 9)), isNull);
      expect(plan(kept, DateTime(2026, 11, 23, 9), enabled: false), isNull);
    });
  });

  group('StreakReminder', () {
    late DateTime now;
    late PlayHistory history;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      now = DateTime(2026, 11, 23, 10);
      history = PlayHistory();
      for (var d = 1; d <= 3; d++) {
        history.record(song('s$d'), const Duration(seconds: 60), at: DateTime(2026, 11, 23 - d, 12));
      }
    });

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

    test('off by default: nothing is set and the history is not followed', () async {
      final sink = FakeSink();
      final r = StreakReminder(sink, clock: () => now);
      await r.start(history);
      expect(r.enabled, isFalse);
      history.record(song('today'), const Duration(seconds: 60), at: now);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sink.scheduled, isEmpty, reason: 'the history is not followed');
      r.stop();
    });

    test('scheduled where the system can: today, then tomorrow once a song is played, cancelled when off', () async {
      final sink = FakeSink();
      final r = StreakReminder(sink, clock: () => now);
      await r.start(history);
      await r.setEnabled(true);
      expect(sink.scheduled, [(3, DateTime(2026, 11, 23, 19))]);

      now = DateTime(2026, 11, 23, 11);
      history.record(song('today'), const Duration(seconds: 60), at: now);
      await settle();
      expect(sink.scheduled.last, (4, DateTime(2026, 11, 24, 19)));

      final count = sink.scheduled.length;
      history.record(song('again'), const Duration(seconds: 60), at: now);
      await settle();
      expect(sink.scheduled.length, count, reason: 'a second play today changes nothing');

      await r.setMinute(18 * 60 + 30);
      expect(sink.scheduled.last, (4, DateTime(2026, 11, 24, 18, 30)));

      await r.setEnabled(false);
      expect(sink.cancelled, 1);
      final before = sink.scheduled.length;
      now = DateTime(2026, 11, 24, 9);
      history.record(song('next day'), const Duration(seconds: 60), at: now);
      await settle();
      expect(sink.scheduled.length, before);
      r.stop();
    });

    test('no streak, nothing scheduled', () async {
      final sink = FakeSink();
      final r = StreakReminder(sink, clock: () => now);
      await r.start(PlayHistory());
      await r.setEnabled(true);
      expect(sink.scheduled, isEmpty);
      r.stop();
    });

    test('computers: a timer to the time, one notification, and none once today is kept', () async {
      SharedPreferences.setMockInitialValues({StreakReminder.enabledKey: true});
      final sink = FakeSink(canSchedule: false);
      now = DateTime(2026, 11, 23, 18, 59, 59, 970);
      final r = StreakReminder(sink, clock: () => now);
      await r.start(history);
      expect(r.hasTimer, isTrue);
      expect(sink.shown, isEmpty);

      now = DateTime(2026, 11, 23, 19);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(sink.shown, [3]);
      expect(r.hasTimer, isFalse, reason: 'the streak ends tonight: nothing more to remind of');

      now = DateTime(2026, 11, 23, 20);
      history.record(song('late'), const Duration(seconds: 60), at: now);
      await settle();
      expect(r.hasTimer, isTrue, reason: "tomorrow's");
      expect(sink.shown, [3]);
      r.stop();
    });

    test('computers: a day kept before the time gets no notification', () async {
      SharedPreferences.setMockInitialValues({StreakReminder.enabledKey: true});
      final sink = FakeSink(canSchedule: false);
      now = DateTime(2026, 11, 23, 18, 59, 59, 970);
      final r = StreakReminder(sink, clock: () => now);
      await r.start(history);
      history.record(song('today'), const Duration(seconds: 60), at: now);
      now = DateTime(2026, 11, 23, 19);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(sink.shown, isEmpty);
      r.stop();
    });
  });

  test('tapping the reminder brings the app up', () {
    var shown = 0;
    DownloadNotifications.bringAppToFront = () async => shown++;
    DownloadNotifications.handleTap(payload: streakNotePayload);
    expect(shown, 1);
    DownloadNotifications.resetTapsForTest();
  });
}
