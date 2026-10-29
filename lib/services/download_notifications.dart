import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'youtube_importer.dart';

/// What the notification code needs to know about one download.
class JobSnapshot {
  const JobSnapshot({
    required this.videoId,
    required this.title,
    required this.status,
    this.progress = 0,
    this.converting = false,
  });

  factory JobSnapshot.of(DownloadJob job) => JobSnapshot(
    videoId: job.videoId,
    title: job.title,
    status: job.status,
    progress: job.progress,
    converting: job.converting,
  );

  final String videoId;
  final String title;
  final DownloadStatus status;
  final double progress;
  final bool converting;

  bool get isActive => status == DownloadStatus.queued || status == DownloadStatus.downloading;
}

class NoteAction {
  const NoteAction(this.id, this.label);
  final String id;
  final String label;

  @override
  bool operator ==(Object other) => other is NoteAction && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);
}

/// One notification, described without any platform detail.
class NoteContent {
  const NoteContent({
    required this.id,
    required this.title,
    required this.body,
    this.percent,
    this.indeterminate = false,
    this.ongoing = false,
    this.actions = const [],
    this.videoId,
  });

  final int id;
  final String title;
  final String body;

  /// 0..100 when the bar is determinate; null with [indeterminate] false means no bar.
  final int? percent;
  final bool indeterminate;

  /// Cannot be swiped away: a download that is still running.
  final bool ongoing;
  final List<NoteAction> actions;

  /// The song the actions act on; null for the summary.
  final String? videoId;

  bool get showsProgress => percent != null || indeterminate;

  @override
  bool operator ==(Object other) =>
      other is NoteContent &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.percent == percent &&
      other.indeterminate == indeterminate &&
      other.ongoing == ongoing &&
      listEquals(other.actions, actions);

  @override
  int get hashCode => Object.hash(id, title, body, percent, indeterminate, ongoing, Object.hashAll(actions));
}

const cancelAction = 'cancel';
const retryAction = 'retry';

/// The one notification that stands for all downloads (and, on Android, is the foreground service's).
const summaryNoteId = 7000;

/// A stable notification id per song (FNV-1a, so it does not change between runs).
int noteIdFor(String videoId) {
  var h = 0x811c9dc5;
  for (final unit in videoId.codeUnits) {
    h = ((h ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return 10000 + h % 0x3fffffff;
}

int _percent(double progress) => (progress.clamp(0.0, 1.0) * 100).round();

/// The notification for one download, or null when it needs none (cancelled).
NoteContent? noteFor(JobSnapshot job, {int? idOverride}) {
  final id = idOverride ?? noteIdFor(job.videoId);
  switch (job.status) {
    case DownloadStatus.queued:
      return NoteContent(
        id: id,
        title: job.title,
        body: 'Waiting to start',
        indeterminate: true,
        ongoing: true,
        actions: const [NoteAction(cancelAction, 'Cancel')],
        videoId: job.videoId,
      );
    case DownloadStatus.downloading:
      if (job.converting) {
        return NoteContent(
          id: id,
          title: job.title,
          body: 'Converting…',
          indeterminate: true,
          ongoing: true,
          actions: const [NoteAction(cancelAction, 'Cancel')],
          videoId: job.videoId,
        );
      }
      final pct = _percent(job.progress);
      return NoteContent(
        id: id,
        title: pct > 0 ? '${job.title} · $pct%' : job.title,
        body: 'Downloading',
        percent: pct > 0 ? pct : null,
        indeterminate: pct == 0,
        ongoing: true,
        actions: const [NoteAction(cancelAction, 'Cancel')],
        videoId: job.videoId,
      );
    case DownloadStatus.done:
      return NoteContent(id: id, title: 'Downloaded ${job.title}', body: 'Saved to your library', videoId: job.videoId);
    case DownloadStatus.failed:
      return NoteContent(
        id: id,
        title: 'Couldn\'t download ${job.title}',
        body: 'Tap Retry to try again.',
        actions: const [NoteAction(retryAction, 'Retry')],
        videoId: job.videoId,
      );
    case DownloadStatus.cancelled:
      return null;
  }
}

/// The notification that stands for every running download: with one, that
/// song (so Android's service notification is the song's own); with several,
/// "Downloading 3 songs" and the overall progress.
NoteContent? summaryFor(List<JobSnapshot> jobs) {
  final active = jobs.where((j) => j.isActive).toList();
  if (active.isEmpty) return null;
  if (active.length == 1) return noteFor(active.single, idOverride: summaryNoteId);
  final working = active.where((j) => j.status == DownloadStatus.downloading && !j.converting).toList();
  final overall = active.fold<double>(0, (sum, j) => sum + (j.converting ? 1 : j.progress)) / active.length;
  final pct = _percent(overall);
  final names = active.take(2).map((j) => j.title).join(', ');
  final more = active.length > 2 ? ' +${active.length - 2}' : '';
  return NoteContent(
    id: summaryNoteId,
    title: 'Downloading ${active.length} songs',
    body: '$names$more',
    percent: working.isEmpty && pct == 0 ? null : pct,
    indeterminate: working.isEmpty && pct == 0,
    ongoing: true,
  );
}

/// Lets an update through at most once per [interval] for each key; a
/// change of kind (new key state) can be forced.
class NoteThrottle {
  NoteThrottle({this.interval = const Duration(milliseconds: 500)});

  final Duration interval;
  final Map<int, DateTime> _last = {};

  /// True when [id] may be updated at [now]; records the update if so.
  bool allow(int id, DateTime now, {bool force = false}) {
    final last = _last[id];
    if (!force && last != null && now.difference(last) < interval) return false;
    _last[id] = now;
    return true;
  }

  /// How long until [id] may be updated.
  Duration wait(int id, DateTime now) {
    final last = _last[id];
    if (last == null) return Duration.zero;
    final left = interval - now.difference(last);
    return left.isNegative ? Duration.zero : left;
  }

  void forget(int id) => _last.remove(id);
}

@pragma('vm:entry-point')
void _backgroundResponse(NotificationResponse response) {
  // Actions are handled in the app's own isolate (the foreground service keeps it alive);
  // this exists so Android accepts action buttons.
}

/// Download progress in the system's notifications, with Cancel and Retry; on
/// Android a foreground service keeps the downloads going with the screen off,
/// on iOS a background task asks for a little more running time.
class DownloadNotifications {
  DownloadNotifications._(this._importer);

  static DownloadNotifications? _instance;

  /// Starts following [importer]. Safe to call on every platform; does nothing where
  /// notifications are unavailable.
  static void attach(YoutubeImporter importer) {
    if (_instance != null || kIsWeb) return;
    _instance = DownloadNotifications._(importer).._start();
  }

  static const _channelId = 'downloads';
  static const _group = 'riflay.downloads';
  static const _channel = MethodChannel('riflay/downloads');

  final YoutubeImporter _importer;
  final _plugin = FlutterLocalNotificationsPlugin();
  final _throttle = NoteThrottle();
  final Map<String, DownloadStatus> _seen = {};
  final Map<int, NoteContent> _shown = {};
  final Map<int, NoteContent> _pending = {};
  final Map<int, Timer> _timers = {};

  bool _ready = false;
  bool _initializing = false;
  bool _asked = false;
  bool _allowed = true;
  bool _serviceOn = false;
  bool _backgroundTask = false;

  bool get _android => !kIsWeb && Platform.isAndroid;
  bool get _ios => !kIsWeb && Platform.isIOS;

  void _start() {
    _importer.addListener(_changed);
    _changed();
  }

  Future<void> _init() async {
    if (_ready || _initializing) return;
    _initializing = true;
    try {
      final category = DarwinNotificationCategory(
        'download',
        actions: [DarwinNotificationAction.plain(cancelAction, 'Cancel')],
      );
      final retry = DarwinNotificationCategory(
        'retry',
        actions: [DarwinNotificationAction.plain(retryAction, 'Retry')],
      );
      final darwin = DarwinInitializationSettings(
        // Asked when the first download starts, not at launch.
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
        notificationCategories: [category, retry],
      );
      final ok = await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('ic_stat_download'),
          iOS: darwin,
          macOS: darwin,
          linux: const LinuxInitializationSettings(defaultActionName: 'Open Riflay'),
          windows: const WindowsInitializationSettings(
            appName: 'Riflay',
            appUserModelId: 'dev.riflay.riflay',
            guid: '7d1f5c2e-3b9a-4c58-9f1e-2a6b8d4e0c13',
          ),
        ),
        onDidReceiveNotificationResponse: _tapped,
        onDidReceiveBackgroundNotificationResponse: _backgroundResponse,
      );
      _ready = ok != false;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
    _initializing = false;
  }

  Future<void> _askPermission() async {
    if (_asked) return;
    _asked = true;
    try {
      bool? granted;
      if (_android) {
        granted = await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (_ios) {
        granted = await _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, sound: false, badge: false);
      } else if (!kIsWeb && Platform.isMacOS) {
        granted = await _plugin
            .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, sound: false, badge: false);
      }
      // Denied: downloads carry on without notifications.
      if (granted == false) _allowed = false;
    } catch (e) {
      debugPrint('Notification permission: $e');
    }
  }

  void _tapped(NotificationResponse r) {
    final id = r.payload;
    if (id == null || id.isEmpty) return;
    final job = _importer.jobFor(id);
    if (job == null) return;
    switch (r.actionId) {
      case cancelAction:
        _importer.cancel(job);
      case retryAction:
        _importer.retry(job);
    }
  }

  var _busy = false;
  var _again = false;

  void _changed() {
    if (_busy) {
      _again = true;
      return;
    }
    unawaited(_sync());
  }

  Future<void> _sync() async {
    _busy = true;
    try {
      final jobs = [for (final j in _importer.jobs) JobSnapshot.of(j)];
      final active = jobs.where((j) => j.isActive).toList();

      if (active.isNotEmpty) {
        await _init();
        if (!_asked && _ready) await _askPermission();
      }
      _background(active.isNotEmpty);
      if (!_ready) return;

      final seenNow = <String>{};
      final terminal = <NoteContent>[];
      for (final job in jobs) {
        seenNow.add(job.videoId);
        final before = _seen[job.videoId];
        _seen[job.videoId] = job.status;
        if (job.status == DownloadStatus.cancelled) {
          await _remove(noteIdFor(job.videoId));
        } else if (!job.isActive && before != job.status && before != null) {
          final note = noteFor(job);
          if (note != null) terminal.add(note);
        }
      }
      _seen.removeWhere((id, _) => !seenNow.contains(id));

      // The service's notification goes before the finished ones appear.
      await _updateActive(active);
      for (final note in terminal) {
        await _post(note, force: true);
      }
    } catch (e) {
      debugPrint('Download notifications: $e');
    } finally {
      _busy = false;
      if (_again) {
        _again = false;
        unawaited(_sync());
      }
    }
  }

  Future<void> _updateActive(List<JobSnapshot> active) async {
    final summary = summaryFor(active);
    final wanted = <int>{};
    final serviceMode = _android;
    if (summary != null) {
      if (serviceMode) {
        await _service(summary);
      } else if (active.length > 1) {
        wanted.add(summary.id);
        _queue(summary);
      }
      if (active.length > 1 || !serviceMode) {
        for (final job in active) {
          final note = noteFor(job);
          if (note == null) continue;
          wanted.add(note.id);
          _queue(note);
        }
      }
    } else if (serviceMode) {
      await _stopService();
    }
    // Active notes of jobs that are no longer running or no longer listed go away.
    for (final id in _shown.keys.toList()) {
      final note = _shown[id]!;
      if (note.ongoing && !wanted.contains(id) && !(serviceMode && id == summaryNoteId)) {
        await _remove(id);
      }
    }
  }

  /// Posts [note] now or, when it was updated a moment ago, a moment from now with the newest content.
  void _queue(NoteContent note) {
    if (_shown[note.id] == note) {
      _pending.remove(note.id);
      return;
    }
    final now = DateTime.now();
    final changedKind = _shown[note.id]?.indeterminate != note.indeterminate || _shown[note.id] == null;
    if (_throttle.allow(note.id, now, force: changedKind)) {
      _timers.remove(note.id)?.cancel();
      _pending.remove(note.id);
      unawaited(_post(note));
    } else {
      _pending[note.id] = note;
      _timers[note.id] ??= Timer(_throttle.wait(note.id, now), () {
        _timers.remove(note.id);
        final next = _pending.remove(note.id);
        if (next != null && _throttle.allow(next.id, DateTime.now(), force: true)) unawaited(_post(next));
      });
    }
  }

  Future<void> _post(NoteContent note, {bool force = false}) async {
    if (!_ready || !_allowed) return;
    if (force) {
      _timers.remove(note.id)?.cancel();
      _pending.remove(note.id);
      _throttle.allow(note.id, DateTime.now(), force: true);
    }
    _shown[note.id] = note;
    try {
      await _plugin.show(
        id: note.id,
        title: note.title,
        body: note.body,
        notificationDetails: _details(note),
        payload: note.videoId ?? '',
      );
    } catch (e) {
      debugPrint('Showing a notification: $e');
    }
  }

  Future<void> _remove(int id) async {
    _timers.remove(id)?.cancel();
    _pending.remove(id);
    _throttle.forget(id);
    if (_shown.remove(id) == null && !_ready) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  NotificationDetails _details(NoteContent n) {
    final actions = n.actions;
    final isSummary = n.id == summaryNoteId;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Downloads',
        channelDescription: 'Progress of songs being downloaded',
        icon: 'ic_stat_download',
        importance: n.ongoing ? Importance.low : Importance.defaultImportance,
        priority: n.ongoing ? Priority.low : Priority.defaultPriority,
        ongoing: n.ongoing,
        autoCancel: !n.ongoing,
        onlyAlertOnce: true,
        showProgress: n.showsProgress,
        maxProgress: 100,
        progress: n.percent ?? 0,
        indeterminate: n.indeterminate,
        groupKey: n.ongoing ? _group : null,
        setAsGroupSummary: isSummary && n.ongoing,
        category: n.ongoing ? AndroidNotificationCategory.progress : AndroidNotificationCategory.status,
        actions: [for (final a in actions) AndroidNotificationAction(a.id, a.label, cancelNotification: false)],
      ),
      iOS: _darwinDetails(n),
      macOS: _darwinDetails(n),
      linux: LinuxNotificationDetails(
        category: LinuxNotificationCategory.transferComplete,
        urgency: n.ongoing ? LinuxNotificationUrgency.low : LinuxNotificationUrgency.normal,
        resident: n.ongoing,
        transient: !n.ongoing && actions.isEmpty,
        actions: [for (final a in actions) LinuxNotificationAction(key: a.id, label: a.label)],
      ),
      windows: WindowsNotificationDetails(
        actions: [for (final a in actions) WindowsAction(content: a.label, arguments: a.id)],
        progressBars: n.showsProgress
            ? [WindowsProgressBar(id: 'p${n.id}', status: n.body, value: n.percent == null ? null : n.percent! / 100)]
            : const [],
      ),
    );
  }

  DarwinNotificationDetails _darwinDetails(NoteContent n) => DarwinNotificationDetails(
    presentAlert: true,
    presentBanner: true,
    presentList: true,
    presentSound: false,
    presentBadge: false,
    threadIdentifier: _group,
    categoryIdentifier: n.actions.any((a) => a.id == retryAction)
        ? 'retry'
        : n.actions.isEmpty
        ? null
        : 'download',
  );

  // ---- background running ----

  Future<void> _service(NoteContent note) async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    if (_serviceOn && _shown[note.id] == note) return;
    if (_serviceOn && !_throttle.allow(note.id, DateTime.now())) {
      _pending[note.id] = note;
      _timers[note.id] ??= Timer(_throttle.wait(note.id, DateTime.now()), () {
        _timers.remove(note.id);
        final next = _pending.remove(note.id);
        if (next != null && _serviceOn) unawaited(_service(next));
      });
      return;
    }
    _throttle.allow(note.id, DateTime.now(), force: true);
    _shown[note.id] = note;
    try {
      await android.startForegroundService(
        id: note.id,
        title: note.title,
        body: note.body,
        notificationDetails: _details(note).android,
        payload: note.videoId ?? '',
        foregroundServiceTypes: {AndroidServiceForegroundType.foregroundServiceTypeDataSync},
      );
      _serviceOn = true;
    } catch (e) {
      // Not allowed to start from here (battery restrictions): downloads go on while the app is open.
      debugPrint('Download service: $e');
    }
  }

  Future<void> _stopService() async {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _pending.clear();
    _shown.remove(summaryNoteId);
    _throttle.forget(summaryNoteId);
    if (!_serviceOn) return;
    _serviceOn = false;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.stopForegroundService();
    } catch (_) {}
  }

  /// iOS: ask for background running time while a download is going.
  void _background(bool running) {
    if (!_ios || running == _backgroundTask) return;
    _backgroundTask = running;
    unawaited(_channel.invokeMethod<void>(running ? 'start' : 'stop').catchError((_) {}));
  }
}
