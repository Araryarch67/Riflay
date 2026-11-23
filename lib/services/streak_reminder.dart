import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../platform/host.dart';
import 'download_notifications.dart';
import 'language.dart';
import 'listening_streak.dart';
import 'play_history.dart';

/// Where the reminder goes (a system notification; a fake in tests).
abstract class StreakNoteSink {
  /// Whether a notification can be set for a later time on this platform, so it comes with the app closed.
  bool get canSchedule;

  Future<void> show(int days);

  /// Sets the reminder for [days] at [at] (local time), replacing the one set before.
  Future<void> schedule(int days, DateTime at);

  Future<void> cancelScheduled();
}

/// The next reminder: at [at], for a streak of [days] that ends that midnight unless a song is played.
typedef StreakReminderPlan = ({DateTime at, int days});

/// One notification a day at a chosen time, only while that day's streak hasn't been kept yet.
///
/// Phones and macOS set it ahead of time with the system (it comes with the app closed and after a restart) and set
/// it again whenever a play keeps the day; Windows and Linux have no such thing, so a single timer runs to the next
/// reminder while the app or its tray icon is up.
class StreakReminder {
  StreakReminder(this.sink, {this.clock});

  final StreakNoteSink sink;

  /// Tests set the time; null is the real clock (and the streak's shared cache).
  final DateTime Function()? clock;

  static const enabledKey = 'streakReminder.on';
  static const minuteKey = 'streakReminder.minute';
  static const notifiedKey = 'streakReminder.notifiedDay';
  static const scheduledKey = 'streakReminder.scheduled';

  /// 19:00.
  static const defaultMinute = 19 * 60;

  static final instance = StreakReminder(SystemStreakSink());

  /// The reminder on [day] at [minute] past midnight.
  static DateTime timeOn(DateTime day, int minute) => DateTime(day.year, day.month, day.day, minute ~/ 60, minute % 60);

  /// Whether the reminder due at [now] goes out: the day has no play yet, a streak is alive until midnight, the
  /// chosen time has come and today has had no reminder.
  static bool shouldNotify({
    required bool enabled,
    required ListeningStreak streak,
    required DateTime now,
    required int minute,
    int? lastNotifiedDay,
  }) =>
      enabled &&
      !streak.today &&
      streak.current > 0 &&
      !now.isBefore(timeOn(now, minute)) &&
      lastNotifiedDay != ListeningStreak.dayNumberOf(now);

  /// When the next reminder is due and the streak it speaks for, or null when none is: today is kept, so tomorrow's
  /// guards today's count; today isn't kept yet and its time is still ahead; otherwise nothing is at stake (no streak,
  /// or today's time has passed and the streak ends tonight).
  static StreakReminderPlan? next({
    required bool enabled,
    required ListeningStreak streak,
    required DateTime now,
    required int minute,
  }) {
    if (!enabled || streak.current == 0) return null;
    if (streak.today) {
      return (at: timeOn(DateTime(now.year, now.month, now.day + 1), minute), days: streak.current);
    }
    final today = timeOn(now, minute);
    return now.isBefore(today) ? (at: today, days: streak.current) : null;
  }

  PlayHistory? _history;
  SharedPreferences? _prefs;
  bool _enabled = false;
  int _minute = defaultMinute;
  Timer? _timer;
  (int, bool, int)? _synced;
  Future<void>? _running;

  bool get enabled => _enabled;
  int get minute => _minute;

  static Future<(bool, int)> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getBool(enabledKey) ?? false, prefs.getInt(minuteKey) ?? defaultMinute);
  }

  /// Follows [history] (only while the reminder is on) and sets the next reminder.
  Future<void> start(PlayHistory history) async {
    _history = history;
    final prefs = _prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(enabledKey) ?? false;
    _minute = prefs.getInt(minuteKey) ?? defaultMinute;
    _follow();
    await _sync(force: true);
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await (_prefs ??= await SharedPreferences.getInstance()).setBool(enabledKey, value);
    _follow();
    await _sync(force: true);
  }

  Future<void> setMinute(int value) async {
    _minute = value;
    await (_prefs ??= await SharedPreferences.getInstance()).setInt(minuteKey, value);
    await _sync(force: true);
  }

  void _follow() {
    final history = _history;
    if (history == null) return;
    history.removeListener(_changed);
    if (_enabled) history.addListener(_changed);
  }

  void _changed() => unawaited(_sync());

  ListeningStreak _streak(PlayHistory history, DateTime now) =>
      clock == null ? ListeningStreak.of(history) : ListeningStreak.of(history, now: now);

  /// One at a time; a history change that leaves the day's state as it was does nothing.
  Future<void> _sync({bool force = false, bool due = false}) =>
      _running = (_running ?? Future.value()).then((_) => _apply(force: force, due: due)).catchError((Object e) {
        debugPrint('Streak reminder: $e');
      });

  Future<void> _apply({required bool force, required bool due}) async {
    final history = _history;
    final prefs = _prefs;
    if (history == null || prefs == null) return;
    final now = clock?.call() ?? DateTime.now();
    final streak = _streak(history, now);
    final state = (ListeningStreak.dayNumberOf(now), streak.today, streak.current);
    if (!force && !due && state == _synced) return;
    _synced = state;
    _timer?.cancel();
    _timer = null;

    if (!_enabled) {
      if (prefs.containsKey(scheduledKey)) {
        await sink.cancelScheduled();
        await prefs.remove(scheduledKey);
      }
      return;
    }
    if (due &&
        shouldNotify(
          enabled: true,
          streak: streak,
          now: now,
          minute: _minute,
          lastNotifiedDay: prefs.getInt(notifiedKey),
        )) {
      await sink.show(streak.current);
      await prefs.setInt(notifiedKey, ListeningStreak.dayNumberOf(now));
    }

    final plan = next(enabled: true, streak: streak, now: now, minute: _minute);
    if (sink.canSchedule) {
      if (plan != null) {
        await sink.schedule(plan.days, plan.at);
        await prefs.setInt(scheduledKey, plan.at.millisecondsSinceEpoch);
      } else if (prefs.containsKey(scheduledKey)) {
        await sink.cancelScheduled();
        await prefs.remove(scheduledKey);
      }
    } else if (plan != null) {
      _timer = Timer(plan.at.difference(now), () => unawaited(_sync(due: true)));
    }
  }

  @visibleForTesting
  bool get hasTimer => _timer?.isActive ?? false;

  @visibleForTesting
  void stop() {
    _timer?.cancel();
    _timer = null;
    _history?.removeListener(_changed);
  }
}

/// What a tap on the reminder carries: it only opens the app.
const streakNotePayload = 'streak';

/// The system's notifications, through the plugin the downloads set up.
class SystemStreakSink implements StreakNoteSink {
  static const _id = 7200;

  @override
  bool get canSchedule => !kIsWeb && (Host.isAndroid || Host.isIOS || Host.isMacOS);

  NotificationDetails get _details => NotificationDetails(
    android: AndroidNotificationDetails(
      'streak',
      tr.streakReminder,
      channelDescription: tr.streakReminderChannel,
      icon: 'ic_stat_download',
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: const DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentList: true),
    macOS: const DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentList: true),
    linux: const LinuxNotificationDetails(),
  );

  @override
  Future<void> show(int days) async {
    try {
      final plugin = await DownloadNotifications.sharedPlugin();
      await plugin?.show(
        id: _id,
        title: tr.streakReminderTitle(days),
        body: tr.streakReminderBody,
        notificationDetails: _details,
        payload: streakNotePayload,
      );
    } catch (e) {
      debugPrint('Streak notification: $e');
    }
  }

  @override
  Future<void> schedule(int days, DateTime at) async {
    try {
      final plugin = await DownloadNotifications.sharedPlugin();
      // An instant, not a place: the moment of the chosen local time, whichever zone the database would name.
      // Inexact: a reminder a few minutes late is fine, and exact alarms need a permission Play reserves for clocks.
      await plugin?.zonedSchedule(
        id: _id,
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        title: tr.streakReminderTitle(days),
        body: tr.streakReminderBody,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: streakNotePayload,
      );
    } catch (e) {
      debugPrint('Streak notification not scheduled: $e');
    }
  }

  @override
  Future<void> cancelScheduled() async {
    try {
      final plugin = await DownloadNotifications.sharedPlugin();
      await plugin?.cancel(id: _id);
    } catch (_) {}
  }
}
