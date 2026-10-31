import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../platform/host.dart';
import 'download_notifications.dart';
import 'play_history.dart';
import 'wrap.dart';

/// Where the announcement goes (a system notification; a fake in tests).
abstract class WrapNoteSink {
  /// Whether a notification can be set for a later time on this platform.
  bool get canSchedule;

  Future<void> show(WrapMonth month);

  /// Sets a notification announcing [month] for [at] (local time).
  Future<void> schedule(WrapMonth month, DateTime at);

  Future<void> cancelScheduled();
}

/// "Your March in music is ready."
String wrapNoteTitle(WrapMonth m) => 'Your ${m.name} in music is ready';

/// Announces each month's Wrap once: when the 1st of the month comes (set ahead of time where the platform lets an
/// app do that), or the first time the app opens after it.
class WrapNotifier {
  WrapNotifier(this.sink);

  final WrapNoteSink sink;

  static const firstSeenKey = 'wrap.firstSeen';
  static const enabledKey = 'wrap.notify';
  static const notifiedKey = 'wrap.notified';
  static const scheduledKey = 'wrap.scheduled';

  /// The app's notifier. Its sink is the system's notifications.
  static final instance = WrapNotifier(SystemWrapSink());

  static Future<bool> isEnabled([SharedPreferences? prefs]) async =>
      (prefs ?? await SharedPreferences.getInstance()).getBool(enabledKey) ?? true;

  /// "Monthly Wrap notification" in Settings.
  Future<void> setEnabled(bool value, PlayHistory history, {DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, value);
    await run(history, now: now);
  }

  /// Remembers the first day the app ran, once.
  static Future<DateTime> firstSeen(SharedPreferences prefs, DateTime now) async {
    final saved = prefs.getInt(firstSeenKey);
    if (saved != null) return DateTime.fromMillisecondsSinceEpoch(saved);
    await prefs.setInt(firstSeenKey, now.millisecondsSinceEpoch);
    return now;
  }

  /// Looks at the clock and the history: announces a Wrap that is due, and sets the next announcement.
  Future<void> run(PlayHistory history, {DateTime? now}) async {
    now ??= DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final seen = await firstSeen(prefs, now);
    final enabled = prefs.getBool(enabledKey) ?? true;
    final available = MonthlyWrap.available(history, firstSeen: seen, now: now);
    final last = WrapMonth.parse(prefs.getString(notifiedKey));

    final due = MonthlyWrap.dueNotice(enabled: enabled, available: available, lastNotified: last, now: now);
    if (due != null) {
      // One set ahead of time has been delivered by the system already.
      final delivered =
          prefs.getString(scheduledKey) == due.key && !due.next.start.add(const Duration(hours: 10)).isAfter(now);
      if (!delivered) await sink.show(due);
      await prefs.setString(notifiedKey, due.key);
      await prefs.remove(scheduledKey);
    }

    if (!enabled || !sink.canSchedule) {
      if (prefs.containsKey(scheduledKey)) {
        await sink.cancelScheduled();
        await prefs.remove(scheduledKey);
      }
      return;
    }
    // Ahead of time only for a month that will qualify whatever happens: it already has enough plays.
    final at = MonthlyWrap.nextRelease(now);
    final announced = WrapMonth.of(at).previous;
    final notified = WrapMonth.parse(prefs.getString(notifiedKey));
    final ok =
        MonthlyWrap.unlocked(firstPlay: MonthlyWrap.firstPlayOf(history), firstSeen: seen, now: at) &&
        MonthlyWrap.playsIn(history, announced) >= MonthlyWrap.minPlays &&
        (notified == null || notified.compareTo(announced) < 0);
    if (ok) {
      await sink.schedule(announced, at);
      await prefs.setString(scheduledKey, announced.key);
    } else if (prefs.containsKey(scheduledKey)) {
      await sink.cancelScheduled();
      await prefs.remove(scheduledKey);
    }
  }
}

/// The system's notifications, through the plugin the downloads set up.
class SystemWrapSink implements WrapNoteSink {
  static const _id = 7100;

  @override
  bool get canSchedule => !kIsWeb && (Host.isAndroid || Host.isIOS || Host.isMacOS);

  NotificationDetails get _details => const NotificationDetails(
    android: AndroidNotificationDetails(
      'wrap',
      'Monthly Wrap',
      channelDescription: 'Your month in music, once it is over',
      icon: 'ic_stat_download',
    ),
    iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentList: true),
    macOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentList: true),
    linux: LinuxNotificationDetails(),
  );

  @override
  Future<void> show(WrapMonth month) async {
    try {
      final plugin = await DownloadNotifications.sharedPlugin();
      await plugin?.show(
        id: _id,
        title: wrapNoteTitle(month),
        body: 'Tap to see what you listened to.',
        notificationDetails: _details,
        payload: 'wrap:${month.key}',
      );
    } catch (e) {
      debugPrint('Wrap notification: $e');
    }
  }

  @override
  Future<void> schedule(WrapMonth month, DateTime at) async {
    try {
      final plugin = await DownloadNotifications.sharedPlugin();
      // An instant, not a place: the moment of 10:00 local on the 1st, whichever zone the database would name.
      await plugin?.zonedSchedule(
        id: _id,
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        title: wrapNoteTitle(month),
        body: 'Tap to see what you listened to.',
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'wrap:${month.key}',
      );
    } catch (e) {
      debugPrint('Wrap notification not scheduled: $e');
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
