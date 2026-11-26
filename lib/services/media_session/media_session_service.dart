import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

/// What the system (or a key) asks the player to do.
enum MediaCommandKind { play, pause, togglePlayPause, next, previous, stop, seek, shuffle, repeat, like }

/// Repeat as the session shows it: off, the whole queue, or one song.
enum MediaRepeat { off, all, one }

/// Where a command came from. One physical press can arrive twice by two routes (a keyboard media key is seen by
/// the focused window's shortcuts and by the system's media session), so duplicates are judged per route.
enum MediaCommandSource {
  /// The system's media session: Windows SMTC, MPRIS, Android MediaSession, MPRemoteCommandCenter, the browser's
  /// Media Session. Bluetooth headsets and media keys reach the app through it.
  system,

  /// The app's own keyboard shortcuts (a media key while the window has focus).
  keyboard,

  /// Anything else in the app.
  app,
}

/// One command to the player. Every external control goes through [MediaSessionService.dispatch] as one of these.
@immutable
class MediaCommand {
  const MediaCommand(this.kind, {this.position, this.source = MediaCommandSource.system});

  const MediaCommand.play({MediaCommandSource source = MediaCommandSource.system})
    : this(MediaCommandKind.play, source: source);
  const MediaCommand.pause({MediaCommandSource source = MediaCommandSource.system})
    : this(MediaCommandKind.pause, source: source);
  const MediaCommand.toggle({MediaCommandSource source = MediaCommandSource.system})
    : this(MediaCommandKind.togglePlayPause, source: source);
  const MediaCommand.next({MediaCommandSource source = MediaCommandSource.system})
    : this(MediaCommandKind.next, source: source);
  const MediaCommand.previous({MediaCommandSource source = MediaCommandSource.system})
    : this(MediaCommandKind.previous, source: source);
  const MediaCommand.stop({MediaCommandSource source = MediaCommandSource.system})
    : this(MediaCommandKind.stop, source: source);
  const MediaCommand.seek(Duration to, {MediaCommandSource source = MediaCommandSource.system})
    : this(MediaCommandKind.seek, position: to, source: source);

  final MediaCommandKind kind;

  /// Where to seek to ([MediaCommandKind.seek] only).
  final Duration? position;
  final MediaCommandSource source;

  /// Commands that one press of one button may produce: play, pause, play/pause and stop are all "the play
  /// button" (a key seen as Play/Pause by the app and as Pause by the system).
  MediaCommandKind get _group => switch (kind) {
    MediaCommandKind.play ||
    MediaCommandKind.pause ||
    MediaCommandKind.togglePlayPause ||
    MediaCommandKind.stop => MediaCommandKind.togglePlayPause,
    _ => kind,
  };

  bool get _isExplicitPlayback =>
      kind == MediaCommandKind.play || kind == MediaCommandKind.pause || kind == MediaCommandKind.stop;

  @override
  String toString() => 'MediaCommand(${kind.name}${position == null ? '' : ' $position'}, ${source.name})';
}

/// Runs commands one at a time, in order, and drops the duplicates that rapid presses and double routes produce.
///
/// - The same button from two routes within [crossSourceWindow] is one press, run once.
/// - The same button from one route within [bounceWindow] is a bounce (or a headset repeating itself), run once.
/// - Pending seeks collapse to the last; pending play / pause / stop collapse to the last.
/// - A command that fails doesn't stop the ones after it.
class MediaCommandRouter {
  MediaCommandRouter(
    this._execute, {
    this.crossSourceWindow = const Duration(milliseconds: 350),
    this.bounceWindow = const Duration(milliseconds: 90),
    this.maxPending = 8,
    Duration Function()? clock,
  }) : _clock = clock ?? _monotonic;

  static final _stopwatch = Stopwatch()..start();
  static Duration _monotonic() => _stopwatch.elapsed;

  final Future<void> Function(MediaCommand) _execute;
  final Duration crossSourceWindow;
  final Duration bounceWindow;

  /// More pending than this and new commands are dropped: someone holding a key down, not a person choosing.
  final int maxPending;
  final Duration Function() _clock;

  final _last = <MediaCommandKind, ({MediaCommandSource source, Duration at})>{};
  final _pending = <MediaCommand>[];
  bool _running = false;
  bool _closed = false;
  Completer<void>? _idle;

  /// Commands waiting to run (not counting the one running).
  int get pending => _pending.length;

  /// Completes once every accepted command has run.
  Future<void> get idle => !_running && _pending.isEmpty ? Future.value() : (_idle ??= Completer<void>()).future;

  /// Queues [c]; false when it was dropped as a duplicate.
  bool add(MediaCommand c) {
    if (_closed) return false;
    if (c.kind == MediaCommandKind.seek && c.position == null) return false;
    final now = _clock();
    if (c.kind != MediaCommandKind.seek) {
      final group = c._group;
      final last = _last[group];
      if (last != null) {
        final gap = now - last.at;
        if (last.source != c.source && gap < crossSourceWindow) return false;
        if (last.source == c.source && gap < bounceWindow) return false;
      }
      _last[group] = (source: c.source, at: now);
    }
    if (c.kind == MediaCommandKind.seek) {
      _pending.removeWhere((p) => p.kind == MediaCommandKind.seek);
    } else if (c._isExplicitPlayback) {
      _pending.removeWhere((p) => p._isExplicitPlayback);
    }
    if (_pending.length >= maxPending) return false;
    _pending.add(c);
    unawaited(_drain());
    return true;
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_pending.isNotEmpty && !_closed) {
        final c = _pending.removeAt(0);
        try {
          await _execute(c);
        } catch (e, s) {
          debugPrint('Media command $c failed: $e\n$s');
        }
      }
    } finally {
      _running = false;
      final idle = _idle;
      _idle = null;
      idle?.complete();
    }
  }

  void close() {
    _closed = true;
    _pending.clear();
    if (!_running) {
      final idle = _idle;
      _idle = null;
      idle?.complete();
    }
  }
}

/// How far a song has got in loading.
enum MediaProcessing { idle, loading, buffering, ready, completed }

/// The song as the system shows it.
@immutable
class MediaTrackInfo {
  const MediaTrackInfo({
    required this.id,
    required this.title,
    this.artist = '',
    this.album,
    this.duration,
    this.artUri,
  });

  final String id;
  final String title;
  final String artist;
  final String? album;
  final Duration? duration;

  /// An `http(s)` URL or a `file:` URI of the cover; null without one (or while it is being found).
  final Uri? artUri;

  MediaTrackInfo withArt(Uri? art) =>
      MediaTrackInfo(id: id, title: title, artist: artist, album: album, duration: duration, artUri: art);

  @override
  bool operator ==(Object other) =>
      other is MediaTrackInfo &&
      other.id == id &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.duration == duration &&
      other.artUri == artUri;

  @override
  int get hashCode => Object.hash(id, title, artist, album, duration, artUri);

  @override
  String toString() => 'MediaTrackInfo($id, $title, $artist)';
}

/// What the player is doing, as the system is told. Systems extrapolate the position from [position], [speed]
/// and the time of the update, so it is sent on changes (play, pause, seek, song), never on a clock.
@immutable
class MediaSessionState {
  const MediaSessionState({
    this.track,
    this.playing = false,
    this.processing = MediaProcessing.idle,
    this.position = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.speed = 1.0,
    this.canNext = false,
    this.canPrevious = false,
    this.shuffle = false,
    this.repeat = MediaRepeat.off,
    this.liked,
  });

  static const empty = MediaSessionState();

  final MediaTrackInfo? track;

  /// Whether the play button should offer Pause. False at the end of the queue, where nothing sounds.
  final bool playing;
  final MediaProcessing processing;
  final Duration position;
  final Duration bufferedPosition;
  final double speed;
  final bool canNext;
  final bool canPrevious;
  final bool shuffle;
  final MediaRepeat repeat;

  /// Whether the song is in Liked music; null when it can't be liked (not a YouTube Music song, signed out).
  final bool? liked;

  Duration? get duration => track?.duration;

  MediaSessionState copyWith({MediaTrackInfo? track}) => MediaSessionState(
    track: track ?? this.track,
    playing: playing,
    processing: processing,
    position: position,
    bufferedPosition: bufferedPosition,
    speed: speed,
    canNext: canNext,
    canPrevious: canPrevious,
    shuffle: shuffle,
    repeat: repeat,
    liked: liked,
  );

  /// The same as [other] but for where the song is (which moves on its own while playing).
  bool sameApartFromPosition(MediaSessionState other) =>
      other.track == track &&
      other.playing == playing &&
      other.processing == processing &&
      other.speed == speed &&
      other.canNext == canNext &&
      other.canPrevious == canPrevious &&
      other.shuffle == shuffle &&
      other.repeat == repeat &&
      other.liked == liked;

  @override
  bool operator ==(Object other) =>
      other is MediaSessionState &&
      sameApartFromPosition(other) &&
      other.position == position &&
      other.bufferedPosition == bufferedPosition;

  @override
  int get hashCode => Object.hash(
    track,
    playing,
    processing,
    position,
    bufferedPosition,
    speed,
    canNext,
    canPrevious,
    shuffle,
    repeat,
    liked,
  );

  @override
  String toString() =>
      'MediaSessionState($track, playing: $playing, ${processing.name}, at $position, x$speed, '
      'next: $canNext, previous: $canPrevious, shuffle: $shuffle, repeat: ${repeat.name}, liked: $liked)';
}

/// The player as the media session sees it: what it is doing, and the commands it takes. Riflay's is
/// [PlayerControllerBinding] over `PlayerController`; there is no second audio engine.
abstract class MediaSessionPlayer implements Listenable {
  /// What is playing now. The cover is the song's URL when it has one; local covers come from [artworkFor].
  MediaSessionState snapshot();

  /// Fires when the position jumps (a seek, a new song) or loading changes, which [addListener] may not report.
  Stream<void> get discontinuities;

  /// A cover for [track] the system can open (a `file:` URI), found once per song; null without one.
  Future<Uri?> artworkFor(MediaTrackInfo track);

  Future<void> play();
  Future<void> pause();
  Future<void> togglePlayPause();
  Future<void> next();
  Future<void> previous();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> toggleShuffle();

  /// Off → all → one → off.
  Future<void> cycleRepeat();

  /// In or out of Liked music (only when the state's `liked` isn't null).
  Future<void> toggleLike();
}

/// One platform's media session: Windows SMTC, or audio_service (Android, iOS, macOS, Linux MPRIS, the web).
abstract class MediaSessionAdapter {
  String get name;

  /// Starts the platform's session; what the system asks comes to [onCommand]. False where it is unavailable.
  Future<bool> attach(void Function(MediaCommand) onCommand);

  /// Tells the system about [state]. Called on changes only, in order, never two at once.
  Future<void> update(MediaSessionState state);

  Future<void> detach();
}

/// The one media session of the app, whatever the platform: mirrors the player to every [MediaSessionAdapter] and
/// sends what the system asks back to the player, one command at a time.
///
/// Event-driven: it publishes when the player notifies or its position jumps, and only what changed.
class MediaSessionService {
  MediaSessionService._(this._player, {MediaCommandRouter Function(Future<void> Function(MediaCommand))? router}) {
    _router = (router ?? MediaCommandRouter.new)(_execute);
  }

  static MediaSessionService? _instance;
  static Future<MediaSessionService>? _starting;

  /// The running session, if any.
  static MediaSessionService? get instance => _instance;

  /// Starts the session for [player] on [adapters]. There is only ever one: a second start (a hot restart, a second
  /// caller) gets the first.
  static Future<MediaSessionService> start(
    MediaSessionPlayer player,
    List<MediaSessionAdapter> adapters, {
    MediaCommandRouter Function(Future<void> Function(MediaCommand))? router,
  }) {
    if (_instance case final s? when !s._disposed) return Future.value(s);
    return _starting ??= () async {
      try {
        final s = MediaSessionService._(player, router: router);
        await s._attach(adapters);
        _instance = s;
        return s;
      } finally {
        _starting = null;
      }
    }();
  }

  /// Sends [c] to the running session's player; false without a session or when [c] was a duplicate.
  static bool route(MediaCommand c) => _instance?.dispatch(c) ?? false;

  final MediaSessionPlayer _player;
  late final MediaCommandRouter _router;
  final _adapters = <_AdapterLink>[];
  final _arts = <String, Uri?>{};
  final _artLoading = <String>{};
  StreamSubscription<void>? _jumps;
  MediaSessionState? _shown;
  bool _disposed = false;

  /// The adapters that started (the others had no session on this platform).
  List<String> get adapters => [for (final a in _adapters) a.adapter.name];

  /// The state last sent to the system.
  MediaSessionState? get shown => _shown;

  /// Completes once every command so far has run and the system was told the result.
  Future<void> get settled async {
    await _router.idle;
    for (final a in _adapters) {
      await a.flushed;
    }
  }

  Future<void> _attach(List<MediaSessionAdapter> adapters) async {
    for (final a in adapters) {
      try {
        if (await a.attach(dispatch)) _adapters.add(_AdapterLink(a));
      } catch (e) {
        debugPrint('Media session ${a.name} unavailable: $e');
      }
    }
    _player.addListener(_onPlayer);
    _jumps = _player.discontinuities.listen((_) => _publish(force: true));
    _publish(force: true);
  }

  /// Queues [c] for the player; false when it was dropped (a duplicate, or the session is closed).
  bool dispatch(MediaCommand c) => !_disposed && _router.add(c);

  Future<void> _execute(MediaCommand c) async {
    switch (c.kind) {
      case MediaCommandKind.play:
        await _player.play();
      case MediaCommandKind.pause:
        await _player.pause();
      case MediaCommandKind.togglePlayPause:
        await _player.togglePlayPause();
      case MediaCommandKind.next:
        await _player.next();
      case MediaCommandKind.previous:
        await _player.previous();
      case MediaCommandKind.stop:
        await _player.stop();
      case MediaCommandKind.seek:
        var to = c.position!;
        final end = _player.snapshot().duration;
        if (to.isNegative) to = Duration.zero;
        if (end != null && end > Duration.zero && to > end) to = end;
        await _player.seek(to);
      case MediaCommandKind.shuffle:
        await _player.toggleShuffle();
      case MediaCommandKind.repeat:
        await _player.cycleRepeat();
      case MediaCommandKind.like:
        await _player.toggleLike();
    }
    // The system shows what happened, also when nothing did (Next at the end of the queue).
    _publish(force: true);
  }

  void _onPlayer() => _publish();

  /// Coming back to the foreground: the system may have dropped what it was told while the app was away.
  void handleLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _publish(force: true, resend: true);
  }

  void _publish({bool force = false, bool resend = false}) {
    if (_disposed) return;
    var s = _player.snapshot();
    final t = s.track;
    if (t != null && t.artUri == null) {
      if (_arts.containsKey(t.id)) {
        s = s.copyWith(track: t.withArt(_arts[t.id]));
      } else {
        _findArt(t);
      }
    }
    final last = _shown;
    if (!resend && last != null && (force ? last == s : last.sameApartFromPosition(s))) return;
    _shown = s;
    for (final a in _adapters) {
      a.send(s);
    }
  }

  void _findArt(MediaTrackInfo t) {
    if (!_artLoading.add(t.id)) return;
    _player.artworkFor(t).then<Uri?>((u) => u, onError: (Object _) => null).then((art) {
      _artLoading.remove(t.id);
      // A few songs' covers are kept: the queue goes back and forth.
      if (_arts.length > 32) _arts.remove(_arts.keys.first);
      _arts[t.id] = art;
      if (art != null && _shown?.track?.id == t.id) _publish(force: true);
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (identical(_instance, this)) _instance = null;
    _router.close();
    _player.removeListener(_onPlayer);
    await _jumps?.cancel();
    for (final a in _adapters) {
      await a.flushed;
      try {
        await a.adapter.detach();
      } catch (e) {
        debugPrint('Media session ${a.adapter.name}: $e');
      }
    }
    _adapters.clear();
  }

  /// Forgets the running session without detaching it, for tests.
  @visibleForTesting
  static void resetForTest() {
    _instance = null;
    _starting = null;
  }
}

/// Sends states to one adapter in order, never two at once; a state that arrives while one is being sent waits, and
/// only the latest of those is sent.
class _AdapterLink {
  _AdapterLink(this.adapter);

  final MediaSessionAdapter adapter;
  MediaSessionState? _next;
  Future<void>? _sending;

  Future<void> get flushed => _sending ?? Future.value();

  void send(MediaSessionState s) {
    _next = s;
    _sending ??= _run();
  }

  Future<void> _run() async {
    try {
      while (_next != null) {
        final s = _next!;
        _next = null;
        try {
          await adapter.update(s);
        } catch (e) {
          debugPrint('Media session ${adapter.name}: $e');
        }
      }
    } finally {
      _sending = null;
    }
  }
}
