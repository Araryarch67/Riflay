import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import '../app_version.dart';
import '../models/track.dart';
import 'play_history.dart';
import 'player_controller.dart';
import 'private_files.dart';
import 'ytmusic_play_report.dart';

/// One song listened to, as the scrobbling services want it.
@immutable
class Listen {
  const Listen({
    required this.artist,
    required this.title,
    required this.startedAt,
    this.album,
    this.duration,
    this.videoId,
  });

  final String artist;
  final String title;
  final String? album;

  /// When the play started, in seconds since 1970 (both services date a listen by its start).
  final int startedAt;
  final Duration? duration;
  final String? videoId;

  /// [t] as a listen started at [startedAt], or null when it has no real artist to send.
  static Listen? of(Track t, {required DateTime startedAt, Duration? duration}) {
    final artist = t.artist.trim();
    final title = t.title.trim();
    if (artist.isEmpty || artist == Track.unknownArtist || title.isEmpty) return null;
    final album = t.album?.trim();
    return Listen(
      artist: artist,
      title: title,
      album: album == null || album.isEmpty ? null : album,
      startedAt: startedAt.millisecondsSinceEpoch ~/ 1000,
      duration: t.duration ?? duration,
      videoId: t.videoId,
    );
  }

  Map<String, dynamic> toJson() => {
    'a': artist,
    't': title,
    's': startedAt,
    if (album != null) 'b': album,
    if (duration != null) 'd': duration!.inMilliseconds,
    if (videoId != null) 'v': videoId,
  };

  static Listen? fromJson(Object? j) {
    if (j is! Map || j['a'] is! String || j['t'] is! String || j['s'] is! int) return null;
    return Listen(
      artist: j['a'] as String,
      title: j['t'] as String,
      startedAt: j['s'] as int,
      album: j['b'] as String?,
      duration: switch (j['d']) {
        final int ms => Duration(milliseconds: ms),
        _ => null,
      },
      videoId: j['v'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Listen &&
      other.artist == artist &&
      other.title == title &&
      other.album == album &&
      other.startedAt == startedAt &&
      other.duration == duration &&
      other.videoId == videoId;

  @override
  int get hashCode => Object.hash(artist, title, album, startedAt, duration, videoId);
}

/// What [ScrobbleTracker] found in one look at the player.
sealed class ScrobbleEvent {
  const ScrobbleEvent(this.listen);
  final Listen listen;
}

/// A song started playing: shown as "now playing" on the profile.
class NowPlaying extends ScrobbleEvent {
  const NowPlaying(super.listen);
}

/// A play that counts, to be sent.
class Scrobbled extends ScrobbleEvent {
  const Scrobbled(super.listen);
}

/// Decides when a play is a scrobble, by the rule Last.fm and ListenBrainz share: the song is longer than 30
/// seconds, and half of it or 4 minutes (whichever is less) was listened to. Seeks add nothing. A song whose
/// length isn't known counts after 4 minutes, or when it ends after at least 30 seconds.
///
/// Pure: feed it what the player says, with the time from [now] (tests pass their own).
class ScrobbleTracker {
  ScrobbleTracker({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const minLength = Duration(seconds: 30);
  static const maxWait = Duration(minutes: 4);

  final DateTime Function() _now;

  // Its own threshold is never reached: the rule here depends on the song's length, which may arrive late.
  final _clock = PlayReportClock(threshold: const Duration(days: 365));
  String? _id;
  DateTime? _startedAt;
  bool _announced = false;
  bool _scrobbled = false;

  /// How much of a song of [length] must be heard; null when it never counts.
  static Duration? needed(Duration? length) {
    if (length == null || length <= Duration.zero) return maxWait;
    if (length <= minLength) return null;
    final half = length ~/ 2;
    return half < maxWait ? half : maxWait;
  }

  List<ScrobbleEvent> tick({
    required Track? track,
    required Duration position,
    required bool playing,
    required bool ended,
    Duration? duration,
  }) {
    if (track?.id != _id) {
      _id = track?.id;
      _restart();
    }
    if (track == null) return const [];
    final before = _clock.heard;
    final over = _clock.tick(trackId: track.id, position: position, playing: playing, ended: ended);
    // Looped back or played again (repeat one): a new play.
    if (_clock.heard < before) _restart();
    final out = <ScrobbleEvent>[];
    final length = track.duration ?? duration;
    Listen? listen() => Listen.of(track, startedAt: _startedAt ?? _now(), duration: length);
    if (playing && !ended && !_announced) {
      _announced = true;
      _startedAt ??= _now().subtract(_clock.heard);
      if (listen() case final l?) out.add(NowPlaying(l));
    }
    if (!_scrobbled) {
      final need = needed(length);
      final heard = _clock.heard;
      final counts =
          need != null && (heard >= need || (over && heard >= minLength && (length == null || length > minLength)));
      if (counts) {
        _scrobbled = true;
        if (listen() case final l?) out.add(Scrobbled(l));
      }
    }
    return out;
  }

  void _restart() {
    _startedAt = null;
    _announced = false;
    _scrobbled = false;
  }
}

/// A service turned a request down. [signedOut]: the sign-in no longer works, so the account was disconnected.
/// [retry]: worth sending again later (no connection, the service is busy).
class ScrobbleError implements Exception {
  const ScrobbleError(this.message, {this.signedOut = false, this.retry = false});
  final String message;
  final bool signedOut;
  final bool retry;

  @override
  String toString() => 'ScrobbleError: $message';
}

/// A scrobbling service: where listens go once its account is connected.
abstract class ScrobbleService {
  ScrobbleService(this._client);

  final http.Client _client;

  /// The key it is saved under.
  String get id;

  /// Its name, as the settings show it.
  String get label;

  /// How many listens one request can carry.
  int get maxBatch;

  /// The account's name, once connected.
  String? user;

  bool get connected;

  /// Shows [l] as playing now. Failures don't matter: the next song sends its own.
  Future<void> nowPlaying(Listen l);

  /// Sends [batch] (at most [maxBatch]). Throws [ScrobbleError].
  Future<void> submit(List<Listen> batch);

  /// The account's past listens, newest first, a page at a time. Throws [ScrobbleError].
  Stream<List<Listen>> history();

  Map<String, dynamic> saveJson();
  void loadJson(Map<String, dynamic> j);
  void forget();
}

/// ListenBrainz: listens sent with the account's user token (from listenbrainz.org/settings).
class ListenBrainz extends ScrobbleService {
  ListenBrainz(super.client, {this.base = 'https://api.listenbrainz.org'});

  final String base;
  String? token;

  /// Where the user finds their token.
  static const tokenPage = 'https://listenbrainz.org/settings/';

  @override
  String get id => 'listenbrainz';
  @override
  String get label => 'ListenBrainz';
  @override
  int get maxBatch => 100;
  @override
  bool get connected => token != null;

  Map<String, String> _headers(String token) => {
    'Authorization': 'Token $token',
    'Content-Type': 'application/json',
    'User-Agent': 'Riflay/$appVersion',
  };

  /// Checks [candidate] and keeps it with its user name. Throws [ScrobbleError] when it isn't valid.
  Future<void> connect(String candidate) async {
    final t = candidate.trim();
    final r = await _send(() => _client.get(Uri.parse('$base/1/validate-token'), headers: _headers(t)));
    final j = _json(r.body);
    if (r.statusCode != 200 || j['valid'] != true) {
      throw const ScrobbleError('ListenBrainz says this token isn\'t valid.');
    }
    token = t;
    user = j['user_name'] as String?;
  }

  Map<String, dynamic> _payload(Listen l, {bool playingNow = false}) => {
    if (!playingNow) 'listened_at': l.startedAt,
    'track_metadata': {
      'artist_name': l.artist,
      'track_name': l.title,
      if (l.album != null) 'release_name': l.album,
      'additional_info': {
        'media_player': 'Riflay',
        'submission_client': 'Riflay',
        'submission_client_version': appVersion,
        if (l.duration != null) 'duration_ms': l.duration!.inMilliseconds,
        if (l.videoId != null) ...{
          'origin_url': 'https://music.youtube.com/watch?v=${l.videoId}',
          'music_service': 'music.youtube.com',
        },
      },
    },
  };

  @override
  Future<void> nowPlaying(Listen l) => _submit({
    'listen_type': 'playing_now',
    'payload': [_payload(l, playingNow: true)],
  });

  @override
  Future<void> submit(List<Listen> batch) => _submit({
    'listen_type': batch.length == 1 ? 'single' : 'import',
    'payload': [for (final l in batch) _payload(l)],
  });

  Future<void> _submit(Map<String, dynamic> body) async {
    final t = token;
    if (t == null) throw const ScrobbleError('Not connected', signedOut: true);
    final r = await _send(
      () => _client.post(Uri.parse('$base/1/submit-listens'), headers: _headers(t), body: jsonEncode(body)),
    );
    if (r.statusCode == 200) return;
    debugPrint('ListenBrainz answered ${r.statusCode}: ${r.body}');
    if (r.statusCode == 401) throw const ScrobbleError('ListenBrainz signed out', signedOut: true);
    throw ScrobbleError('ListenBrainz refused the listens', retry: r.statusCode == 429 || r.statusCode >= 500);
  }

  @override
  Stream<List<Listen>> history() async* {
    final t = token;
    final name = user;
    if (t == null || name == null) throw const ScrobbleError('Not connected', signedOut: true);
    int? before;
    while (true) {
      final uri = Uri.parse('$base/1/user/${Uri.encodeComponent(name)}/listens')
          .replace(queryParameters: {'count': '1000', if (before != null) 'max_ts': '$before'});
      final r = await _withRetry(() async {
        final r = await _send(() => _client.get(uri, headers: _headers(t)));
        if (r.statusCode == 401) throw const ScrobbleError('ListenBrainz signed out', signedOut: true);
        if (r.statusCode != 200) throw ScrobbleError('ListenBrainz answered ${r.statusCode}', retry: true);
        return r;
      });
      final listens = (_json(r.body)['payload'] as Map?)?['listens'];
      if (listens is! List || listens.isEmpty) return;
      final page = <Listen>[];
      int? oldest;
      for (final l in listens.whereType<Map<String, dynamic>>()) {
        final at = l['listened_at'];
        final meta = l['track_metadata'];
        if (at is! int || meta is! Map) continue;
        oldest = oldest == null || at < oldest ? at : oldest;
        final info = meta['additional_info'];
        final ms = info is Map ? info['duration_ms'] : null;
        final sec = info is Map ? info['duration'] : null;
        final origin = info is Map ? info['origin_url'] as String? : null;
        final artist = meta['artist_name'], title = meta['track_name'];
        if (artist is! String || title is! String || artist.isEmpty || title.isEmpty) continue;
        page.add(
          Listen(
            artist: artist,
            title: title,
            album: meta['release_name'] as String?,
            startedAt: at,
            duration: ms is int ? Duration(milliseconds: ms) : (sec is int ? Duration(seconds: sec) : null),
            videoId: origin == null ? null : _videoId.firstMatch(origin)?[1],
          ),
        );
      }
      if (oldest == null || oldest == before) return;
      yield page;
      before = oldest;
    }
  }

  @override
  Map<String, dynamic> saveJson() => {'token': token, 'user': user};

  @override
  void loadJson(Map<String, dynamic> j) {
    token = j['token'] as String?;
    user = j['user'] as String?;
  }

  @override
  void forget() {
    token = null;
    user = null;
  }
}

/// Last.fm: the account is connected in the browser (Last.fm's desktop sign-in), and listens are sent with the
/// session key it gives. Needs an API account: [apiKey] and [secret] come from the build
/// (`--dart-define=RIFLAY_LASTFM_KEY=… --dart-define=RIFLAY_LASTFM_SECRET=…`); without them Last.fm isn't offered.
class LastFm extends ScrobbleService {
  LastFm(super.client, {required this.apiKey, required this.secret, this.base = 'https://ws.audioscrobbler.com/2.0/'});

  final String apiKey;
  final String secret;
  final String base;
  String? session;

  bool get available => apiKey.isNotEmpty && secret.isNotEmpty;

  @override
  String get id => 'lastfm';
  @override
  String get label => 'Last.fm';
  @override
  int get maxBatch => 50;
  @override
  bool get connected => session != null;

  /// The request signature: every parameter but `format`, sorted by name, then the secret, MD5'd.
  @visibleForTesting
  String sign(Map<String, String> params) {
    final keys = params.keys.where((k) => k != 'format' && k != 'callback').toList()..sort();
    final b = StringBuffer();
    for (final k in keys) {
      b
        ..write(k)
        ..write(params[k]);
    }
    b.write(secret);
    return md5.convert(utf8.encode(b.toString())).toString();
  }

  Future<Map<String, dynamic>> _call(Map<String, String> params, {bool post = true}) async {
    final all = {...params, 'api_key': apiKey};
    all['api_sig'] = sign(all);
    all['format'] = 'json';
    final r = await _send(
      () => post
          ? _client.post(Uri.parse(base), headers: {'User-Agent': 'Riflay/$appVersion'}, body: all)
          : _client.get(Uri.parse(base).replace(queryParameters: all), headers: {'User-Agent': 'Riflay/$appVersion'}),
    );
    final j = _json(r.body);
    if (j['error'] case final int code) {
      debugPrint('Last.fm answered error $code: ${j['message']}');
      throw ScrobbleError(
        'Last.fm error $code',
        // 9: the session key no longer works. 11, 16: the service is offline. 29: too many requests.
        signedOut: code == 9,
        retry: code == 11 || code == 16 || code == 29,
      );
    }
    if (r.statusCode != 200) throw ScrobbleError('Last.fm answered ${r.statusCode}', retry: r.statusCode >= 500);
    return j;
  }

  String? _token;

  /// Starts a sign-in: the page to open in the browser, where the user allows Riflay.
  Future<Uri> beginSignIn() async {
    final j = await _call({'method': 'auth.getToken'}, post: false);
    final t = j['token'] as String?;
    if (t == null) throw const ScrobbleError('Last.fm gave no token');
    _token = t;
    return Uri.parse('https://www.last.fm/api/auth/').replace(queryParameters: {'api_key': apiKey, 'token': t});
  }

  /// After [beginSignIn]: true once the user has allowed Riflay (the session is kept), false while they haven't
  /// yet. Throws when the sign-in ran out of time.
  Future<bool> finishSignIn() async {
    final t = _token;
    if (t == null) throw const ScrobbleError('No sign-in started');
    try {
      final j = await _call({'method': 'auth.getSession', 'token': t}, post: false);
      final s = j['session'];
      if (s is! Map || s['key'] is! String) return false;
      session = s['key'] as String;
      user = s['name'] as String?;
      _token = null;
      return true;
    } on ScrobbleError catch (e) {
      // 14: not allowed yet. Anything else (15: the token expired) ends the sign-in.
      if (e.message == 'Last.fm error 14') return false;
      _token = null;
      rethrow;
    }
  }

  Map<String, String> _track(Listen l, [String suffix = '']) => {
    'artist$suffix': l.artist,
    'track$suffix': l.title,
    if (l.album != null) 'album$suffix': l.album!,
    if (l.duration != null) 'duration$suffix': '${l.duration!.inSeconds}',
  };

  @override
  Future<void> nowPlaying(Listen l) async {
    final sk = session;
    if (sk == null) return;
    await _call({'method': 'track.updateNowPlaying', 'sk': sk, ..._track(l)});
  }

  @override
  Future<void> submit(List<Listen> batch) async {
    final sk = session;
    if (sk == null) throw const ScrobbleError('Not connected', signedOut: true);
    await _call({
      'method': 'track.scrobble',
      'sk': sk,
      for (final (i, l) in batch.indexed) ...{..._track(l, '[$i]'), 'timestamp[$i]': '${l.startedAt}'},
    });
  }

  @override
  Stream<List<Listen>> history() async* {
    final name = user;
    if (name == null) throw const ScrobbleError('Not connected', signedOut: true);
    var pages = 1;
    for (var page = 1; page <= pages; page++) {
      final j = await _withRetry(
        () => _call({'method': 'user.getRecentTracks', 'user': name, 'limit': '200', 'page': '$page'}, post: false),
      );
      final recent = j['recenttracks'];
      if (recent is! Map) return;
      pages = int.tryParse('${(recent['@attr'] as Map?)?['totalPages']}') ?? 1;
      // One track comes back as an object, not a list.
      final tracks = switch (recent['track']) {
        final List<dynamic> l => l,
        final Map<dynamic, dynamic> m => [m],
        _ => const [],
      };
      yield [for (final t in tracks.whereType<Map<String, dynamic>>()) ?_recent(t)];
    }
  }

  static Listen? _recent(Map<String, dynamic> t) {
    if ((t['@attr'] as Map?)?['nowplaying'] == 'true') return null; // still playing: not a listen yet
    final at = int.tryParse('${(t['date'] as Map?)?['uts']}');
    String? text(Object? v) => switch (v) {
      final Map<dynamic, dynamic> m when m['#text'] is String && (m['#text'] as String).isNotEmpty => m['#text'],
      final String s when s.isNotEmpty => s,
      _ => null,
    };
    final artist = text(t['artist']);
    final title = text(t['name']);
    if (at == null || artist == null || title == null) return null;
    return Listen(artist: artist, title: title, album: text(t['album']), startedAt: at);
  }

  @override
  Map<String, dynamic> saveJson() => {'session': session, 'user': user};

  @override
  void loadJson(Map<String, dynamic> j) {
    session = j['session'] as String?;
    user = j['user'] as String?;
  }

  @override
  void forget() {
    session = null;
    user = null;
    _token = null;
  }
}

final _videoId = RegExp(r'[?&]v=([A-Za-z0-9_-]{11})');

/// [request] again, up to 3 times with a growing wait, while it fails in a way worth retrying (busy, offline).
Future<T> _withRetry<T>(Future<T> Function() request) async {
  for (var attempt = 1; ; attempt++) {
    try {
      return await request();
    } on ScrobbleError catch (e) {
      if (!e.retry || attempt >= 3) rethrow;
      await Future<void>.delayed(Duration(seconds: 2 * attempt));
    }
  }
}

Future<http.Response> _send(Future<http.Response> Function() request) async {
  try {
    return await request().timeout(const Duration(seconds: 20));
  } on ScrobbleError {
    rethrow;
  } catch (e) {
    debugPrint('Scrobbling request failed: $e');
    throw const ScrobbleError('No connection', retry: true);
  }
}

Map<String, dynamic> _json(String body) {
  try {
    final j = jsonDecode(body);
    return j is Map<String, dynamic> ? j : const {};
  } catch (_) {
    return const {};
  }
}

/// Sends what is played to the connected Last.fm and ListenBrainz accounts.
///
/// Each service has its own queue of listens, kept in the app's folder with the sign-ins (`scrobbling.json`,
/// readable by this user only), so listens made offline, or while a service is down, go out later in order.
/// Nothing is sent while no account is connected.
///
/// `--dart-define=RIFLAY_SCROBBLE_DRY_RUN=true` prints what would be sent instead of sending it.
class Scrobbler extends ChangeNotifier {
  Scrobbler({http.Client? client, File? file, String lastFmKey = '', String lastFmSecret = '', this.dryRun = false})
    : _fileOverride = file {
    final c = client ?? http.Client();
    listenBrainz = ListenBrainz(c);
    lastFm = LastFm(c, apiKey: lastFmKey, secret: lastFmSecret);
  }

  /// The app's scrobbler. Tests may swap it.
  static Scrobbler instance = Scrobbler(
    lastFmKey: const String.fromEnvironment('RIFLAY_LASTFM_KEY'),
    lastFmSecret: const String.fromEnvironment('RIFLAY_LASTFM_SECRET'),
    dryRun: const bool.fromEnvironment('RIFLAY_SCROBBLE_DRY_RUN'),
  );

  static const _name = 'scrobbling.json';

  /// Listens kept per service while they can't be sent; the oldest go past this.
  static const maxQueued = 3000;

  /// The wait before a failed send is tried again, doubled each time up to [_maxRetry].
  static const _firstRetry = Duration(minutes: 1);
  static const _maxRetry = Duration(minutes: 30);

  final bool dryRun;
  final File? _fileOverride;
  late final ListenBrainz listenBrainz;
  late final LastFm lastFm;

  /// The services this build offers, in the order the settings list them.
  List<ScrobbleService> get services => [if (lastFm.available) lastFm, listenBrainz];

  bool get anyConnected => services.any((s) => s.connected);

  final _queues = <String, List<Listen>>{};
  bool _loaded = false;
  bool _sending = false;
  Timer? _retry;
  Duration _retryAfter = _firstRetry;
  Future<void> _io = Future.value();

  ScrobbleTracker _tracker = ScrobbleTracker();
  PlayerController? _controller;
  final _subs = <StreamSubscription<dynamic>>[];

  /// Called with a calm sentence when an account had to be disconnected.
  void Function(String message)? onMessage;

  /// Listens of [s] waiting to be sent.
  int pending(ScrobbleService s) => _queues[s.id]?.length ?? 0;

  @visibleForTesting
  List<Listen> queueOf(ScrobbleService s) => List.unmodifiable(_queues[s.id] ?? const []);

  // Saving ──────────────────────────────────────────────────────────────────

  Future<File?> _file() async {
    if (_fileOverride != null) return _fileOverride;
    try {
      return await PrivateFiles.file(_name);
    } catch (_) {
      return null; // no app folder (widget tests): kept in memory only
    }
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final file = await _file();
    if (file == null || !file.existsSync()) return;
    try {
      final j = jsonDecode(await file.readAsString());
      if (j is! Map<String, dynamic>) return;
      for (final s in [lastFm, listenBrainz]) {
        if (j[s.id] case final Map<String, dynamic> saved) s.loadJson(saved);
        if (j['queue'] case final Map<String, dynamic> q) {
          if (q[s.id] case final List<dynamic> list) {
            _queues[s.id] = [for (final l in list.map(Listen.fromJson)) ?l];
          }
        }
      }
    } catch (e) {
      debugPrint('Scrobbling settings unreadable, starting over: $e');
    }
    notifyListeners();
  }

  Future<void> _save() {
    final contents = jsonEncode({
      for (final s in [lastFm, listenBrainz]) s.id: s.saveJson(),
      'queue': {
        for (final e in _queues.entries)
          if (e.value.isNotEmpty) e.key: [for (final l in e.value) l.toJson()],
      },
    });
    return _io = _io.then((_) async {
      final file = await _file();
      if (file == null) return;
      try {
        await PrivateFiles.write(file, contents, secret: true);
      } catch (e) {
        debugPrint('Saving scrobbling settings failed: $e');
      }
    });
  }

  // Accounts ────────────────────────────────────────────────────────────────

  /// Connects ListenBrainz with the user's token. Throws [ScrobbleError] when it isn't valid or can't be checked.
  Future<void> connectListenBrainz(String token) async {
    await listenBrainz.connect(token);
    notifyListeners();
    await _save();
  }

  /// Disconnects [s]; its waiting listens are dropped.
  Future<void> disconnect(ScrobbleService s) async {
    s.forget();
    _queues.remove(s.id);
    notifyListeners();
    await _save();
  }

  /// Saves a sign-in finished elsewhere ([LastFm.finishSignIn]).
  Future<void> connected(ScrobbleService s) async {
    notifyListeners();
    await _save();
  }

  // Sending ─────────────────────────────────────────────────────────────────

  /// Hands [events] to every connected service.
  void handle(List<ScrobbleEvent> events) {
    var queued = false;
    for (final e in events) {
      for (final s in services) {
        if (!s.connected) continue;
        switch (e) {
          case NowPlaying(:final listen):
            if (dryRun) {
              debugPrint('[scrobble] ${s.label} now playing: ${listen.artist} - ${listen.title}');
            } else {
              s.nowPlaying(listen).catchError((Object err) => debugPrint('Now playing not sent: $err'));
            }
          case Scrobbled(:final listen):
            final q = _queues.putIfAbsent(s.id, () => []);
            q.add(listen);
            if (q.length > maxQueued) q.removeRange(0, q.length - maxQueued);
            queued = true;
        }
      }
    }
    if (queued) {
      notifyListeners();
      // Online, the listens are saved once, after they went out; a send already running saves them here.
      _background = _sending ? _save() : send();
    }
  }

  Future<void> _background = Future.value();

  /// Done once the listens last handed over have been saved and a send tried.
  @visibleForTesting
  Future<void> settled() => _background;

  /// Sends what is waiting, oldest first. Safe to call at any time.
  Future<void> send() async {
    if (_sending) return;
    _sending = true;
    _retry?.cancel();
    _retry = null;
    var failed = false;
    // Something was waiting, so the queue on disk changes whichever way the sending goes.
    final had = _queues.values.any((q) => q.isNotEmpty);
    try {
      for (final s in services) {
        final q = _queues[s.id];
        while (s.connected && q != null && q.isNotEmpty) {
          final batch = q.take(s.maxBatch).toList();
          try {
            if (dryRun) {
              for (final l in batch) {
                debugPrint('[scrobble] ${s.label}: ${l.artist} - ${l.title} at ${l.startedAt}');
              }
            } else {
              await s.submit(batch);
            }
            q.removeRange(0, batch.length);
          } on ScrobbleError catch (e) {
            if (e.signedOut) {
              s.forget();
              _queues.remove(s.id);
              onMessage?.call('${s.label} signed you out. Connect it again in Settings.');
            } else if (e.retry) {
              failed = true;
            } else {
              // Refused for good (bad data): dropped, so the rest can go.
              q.removeRange(0, batch.length);
              continue;
            }
            break;
          }
        }
      }
    } finally {
      _sending = false;
    }
    if (_disposed) return;
    if (failed) {
      _retry = Timer(_retryAfter, () => unawaited(send()));
      _retryAfter = _retryAfter * 2 > _maxRetry ? _maxRetry : _retryAfter * 2;
    } else {
      _retryAfter = _firstRetry;
    }
    if (!had) return;
    notifyListeners();
    await _save();
  }

  // Bringing past listens in ────────────────────────────────────────────────

  /// The service whose past listens are being brought in, if any.
  ScrobbleService? get importing => _importing;
  ScrobbleService? _importing;

  /// Listens read so far by the import in progress.
  int get importRead => _importRead;
  int _importRead = 0;
  bool _cancelImport = false;

  /// Plays brought in at most, newest first: the history keeps 150,000 in all.
  static const maxImport = 100000;

  /// A song of unknown length counts as this long in the stats.
  static const _assumedLength = 210;

  /// Brings [s]'s past listens into [history], matched to songs in [library] (by artist and title) where they
  /// can be, otherwise to their YouTube video, otherwise as songs only the stats show. Returns how many plays were
  /// added; ones already in the history are skipped, so running it again adds only what is new.
  /// Throws [ScrobbleError].
  Future<int> importHistory(ScrobbleService s, {required PlayHistory history, required List<Track> library}) async {
    if (_importing != null) return 0;
    _importing = s;
    _importRead = 0;
    _cancelImport = false;
    notifyListeners();
    try {
      final byName = <String, Track>{};
      for (final t in library) {
        final key = '${SongInfo.normalize(t.artist)}|${SongInfo.normalize(t.title)}';
        // A file on this device wins over a streamed copy of the same song.
        if (!t.isRemote || !byName.containsKey(key)) byName[key] = t;
      }
      final plays = <ImportedPlay>[];
      await for (final page in s.history()) {
        for (final l in page) {
          plays.add(_imported(l, byName));
        }
        _importRead += page.length;
        notifyListeners();
        if (_cancelImport || plays.length >= maxImport) break;
      }
      if (_cancelImport) return 0;
      return await history.importPlays(plays);
    } on ScrobbleError catch (e) {
      if (e.signedOut) await disconnect(s);
      rethrow;
    } finally {
      _importing = null;
      notifyListeners();
    }
  }

  /// Stops the import in progress after the page it is reading; nothing is added.
  void cancelImport() => _cancelImport = true;

  static ImportedPlay _imported(Listen l, Map<String, Track> byName) {
    final local = byName['${SongInfo.normalize(l.artist)}|${SongInfo.normalize(l.title)}'];
    final id = l.videoId;
    final song = switch (local) {
      final t? => SongInfo.of(t),
      _ when id != null => SongInfo(key: 'yt:$id', title: l.title, artist: l.artist, album: l.album, videoId: id),
      _ => SongInfo(key: SongInfo.importedKey(l.artist, l.title), title: l.title, artist: l.artist, album: l.album),
    };
    final length = local?.duration ?? l.duration;
    return ImportedPlay(song, l.startedAt, length?.inSeconds ?? _assumedLength);
  }

  // Following the player ────────────────────────────────────────────────────

  /// Loads the accounts and starts following [controller]'s player.
  Future<void> start(PlayerController controller) async {
    _controller = controller;
    await load();
    for (final s in _subs) {
      await s.cancel();
    }
    _tracker = ScrobbleTracker();
    _subs
      ..clear()
      ..add(controller.player.positionStream.listen((_) => _pollThrottled()))
      ..add(controller.player.playerStateStream.listen((_) => _poll()))
      ..add(controller.player.sequenceStateStream.listen((_) => _poll()));
    if (_queues.values.any((q) => q.isNotEmpty)) unawaited(send());
  }

  DateTime? _lastPoll;

  void _pollThrottled() {
    final last = _lastPoll;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 1)) return;
    _poll();
  }

  void _poll() {
    _lastPoll = DateTime.now();
    final c = _controller;
    if (c == null || !anyConnected) return;
    final events = _tracker.tick(
      track: c.currentTrack,
      position: c.position,
      playing: c.isPlaying,
      ended: c.player.processingState == ProcessingState.completed,
      duration: c.duration,
    );
    if (events.isNotEmpty) handle(events);
  }

  /// Stops following the player and saves what is waiting.
  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _controller = null;
    _retry?.cancel();
    await _save();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
