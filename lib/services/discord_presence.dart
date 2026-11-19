import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/track.dart';
import '../platform/host.dart';
import 'language.dart';
import 'monochrome.dart';

/// What the Discord presence shows (Settings › Accounts & services › Discord).
@immutable
class DiscordOptions {
  const DiscordOptions({
    this.cover = true,
    this.time = true,
    this.listenButton = true,
    this.appButton = true,
    this.songInList = true,
    this.whilePaused = false,
    this.quality = true,
    this.showWhenIdle = true,
  });

  /// The song's cover; off: Riflay's logo.
  final bool cover;

  /// The time played and the time left (Discord draws the bar).
  final bool time;
  final bool listenButton;
  final bool appButton;

  /// The member list says the song's title; off: "Listening to Riflay".
  final bool songInList;

  /// A paused song stays shown, marked paused; off: the presence goes away.
  final bool whilePaused;

  /// The sound's quality ("FLAC 24/96", "Opus 160 kbps") on the line under the song, beside the album.
  final bool quality;

  /// Shows presence while browsing or idle; off: only shows when music is playing.
  final bool showWhenIdle;

  DiscordOptions copyWith({
    bool? cover,
    bool? time,
    bool? listenButton,
    bool? appButton,
    bool? songInList,
    bool? whilePaused,
    bool? quality,
    bool? showWhenIdle,
  }) => DiscordOptions(
    cover: cover ?? this.cover,
    time: time ?? this.time,
    listenButton: listenButton ?? this.listenButton,
    appButton: appButton ?? this.appButton,
    songInList: songInList ?? this.songInList,
    whilePaused: whilePaused ?? this.whilePaused,
    quality: quality ?? this.quality,
    showWhenIdle: showWhenIdle ?? this.showWhenIdle,
  );

  Map<String, Object> toJson() => {
    'cover': cover,
    'time': time,
    'listenButton': listenButton,
    'appButton': appButton,
    'songInList': songInList,
    'whilePaused': whilePaused,
    'quality': quality,
    'showWhenIdle': showWhenIdle,
  };

  factory DiscordOptions.fromJson(Map<String, Object?> j) {
    bool b(String k, bool d) => j[k] as bool? ?? d;
    const d = DiscordOptions();
    return DiscordOptions(
      cover: b('cover', d.cover),
      time: b('time', d.time),
      listenButton: b('listenButton', d.listenButton),
      appButton: b('appButton', d.appButton),
      songInList: b('songInList', d.songInList),
      whilePaused: b('whilePaused', d.whilePaused),
      quality: b('quality', d.quality),
      showWhenIdle: b('showWhenIdle', d.showWhenIdle),
    );
  }

  @override
  bool operator ==(Object other) => other is DiscordOptions && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// Discord Rich Presence over Discord's local IPC socket (no SDK, no network).
///
/// Protocol: frames of `[int32 LE opcode][int32 LE length][JSON]` over
/// `discord-ipc-N` (a Unix socket on Linux/macOS, a named pipe on Windows).
/// Opcode 0 is the handshake; opcode 1 carries commands such as SET_ACTIVITY.
class DiscordPresence {
  DiscordPresence(
    this.clientId, {
    @visibleForTesting Iterable<String> Function()? socketPaths,
    @visibleForTesting Future<String?> Function(Track)? monochromeCover,
    @visibleForTesting Duration heartbeat = const Duration(seconds: 30),
  }) : _socketPaths = socketPaths ?? candidatePaths,
       _monochromeCover = monochromeCover ?? _findMonochromeCover,
       _heartbeatEvery = heartbeat;

  final String clientId;
  final Iterable<String> Function() _socketPaths;
  final Future<String?> Function(Track) _monochromeCover;
  static Future<String?> _findMonochromeCover(Track track) async {
    final songs = await Monochrome.instance.search(track.title, limit: 50);
    return songs.where((song) => song.offlineId == track.offlineId).firstOrNull?.artworkUrl;
  }

  /// Discord allows 5 activity updates per 20 s; stay comfortably under that.
  static const _minInterval = Duration(seconds: 4);

  /// A failed connection retries at 1 s, 2 s, 4 s… up to half a minute, so Discord starting late is picked up
  /// without hammering a closed pipe on every update.
  static const _minBackoff = Duration(seconds: 1);
  static const _maxBackoff = Duration(seconds: 30);

  /// Where the "Download Riflay" button leads: the newest release, files for every OS.
  static const downloadUrl = 'https://github.com/Araryarch67/Riflay/releases/latest';

  _IpcConnection? _conn;
  Future<_IpcConnection?>? _connecting;
  bool _sending = false;
  Timer? _reconnect;
  Timer? _heartbeat;
  final Duration _heartbeatEvery;
  Duration _backoff = _minBackoff;
  DateTime _lastSent = DateTime(0);
  Timer? _pending;
  Map<String, dynamic>? _wanted;
  bool _disposed = false;
  final _monochromeCovers = <String, Future<String?>>{};
  bool _enabled = true;
  DateTime _appStartTime = DateTime.now();

  static void _log(String message) => debugPrint('[Discord RPC] $message');

  @visibleForTesting
  set appStartTimeForTesting(DateTime t) => _appStartTime = t;

  DateTime get appStartTime => _appStartTime;

  /// What the presence shows; Settings sets it.
  DiscordOptions options = const DiscordOptions();

  static bool get supported => Host.isLinux || Host.isWindows || Host.isMacOS;

  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) {
      _wanted = null;
      _pending?.cancel();
      _reconnect?.cancel();
      _reconnect = null;
      _heartbeat?.cancel();
      _heartbeat = null;
      _backoff = _minBackoff;
      if (_conn != null) unawaited(_send());
    }
  }

  /// Shows [track] as playing from [position] ([quality]: "FLAC · 24-bit / 96 kHz"), or shows browsing presence
  /// when [options.showWhenIdle] is true, or clears the presence.
  void update({
    required Track? track,
    required bool playing,
    required Duration position,
    Duration? duration,
    String? quality,
    String? browsingLocation,
  }) {
    if (!supported || !_enabled) return;
    if (track != null && playing) {
      _wanted = activity(track, position: position, duration: duration, quality: quality, playing: true);
    } else if (track != null && !playing && options.whilePaused) {
      _wanted = activity(track, position: position, duration: duration, quality: quality, playing: false);
    } else if (options.showWhenIdle) {
      _wanted = idleActivity(location: browsingLocation);
    } else {
      _wanted = null;
    }
    // Nothing shown yet and nothing to show: don't wake Discord up just to clear.
    if (_wanted == null && _conn == null && _connecting == null) {
      _pending?.cancel();
      return;
    }
    _schedule();
    if (track != null &&
        options.cover &&
        track.artworkUrl == null &&
        (track.offlineId?.startsWith('monochrome:') ?? false)) {
      final wanted = _wanted;
      final key = track.offlineId!;
      if (!_monochromeCovers.containsKey(key)) {
        if (_monochromeCovers.length >= 64) _monochromeCovers.remove(_monochromeCovers.keys.first);
        _monochromeCovers[key] = _monochromeCover(track).then((cover) => cover, onError: (Object _) => null);
      }
      _monochromeCovers[key]!.then((cover) {
        if (_disposed ||
            !_enabled ||
            !options.cover ||
            cover == null ||
            wanted == null ||
            !identical(_wanted, wanted)) {
          return;
        }
        (wanted['assets'] as Map)['large_image'] = cover;
        _schedule();
      });
    }
  }

  void _schedule() {
    _pending?.cancel();
    var wait = _minInterval - DateTime.now().difference(_lastSent);
    // A clock change must not stall the presence for longer than one rate-limit window.
    if (wait > _minInterval) wait = _minInterval;
    _pending = Timer(wait.isNegative ? Duration.zero : wait, _send);
  }

  /// Maps an in-app location to a friendly, localized browsing description.
  static String browsingDetails(String? location) {
    final loc = location?.toLowerCase().trim();
    if (loc == null || loc.isEmpty || loc == 'home') return tr.discordBrowsingMusic;
    if (loc == 'library' || loc.startsWith('collection')) return tr.discordBrowsingLibrary;
    if (loc == 'search') return tr.discordSearchingMusic;
    if (loc == 'downloads') return tr.discordBrowsingDownloads;
    if (loc == 'queue') return tr.discordViewingQueue;
    if (loc == 'lyrics') return tr.discordViewingLyrics;
    if (loc == 'settings' || loc.startsWith('settings')) return tr.discordInSettings;
    if (loc == 'listen') return tr.discordListeningTogether;
    if (loc == 'stats' || loc == 'wrap') return tr.discordViewingStats;
    return tr.discordBrowsingMusic;
  }

  /// What is sent to Discord when the user is browsing Riflay or idle (no music playing).
  Map<String, dynamic> idleActivity({String? location}) {
    final details = browsingDetails(location);
    return {
      'type': 0, // Show the app name first while browsing.
      'status_display_type': 0,
      'details': _clip(details),
      if (options.time) 'timestamps': {'start': _appStartTime.millisecondsSinceEpoch},
      'assets': {'large_image': 'openmusic'},
      'buttons': [
        if (options.appButton) {'label': 'Download Riflay', 'url': downloadUrl},
      ],
    };
  }

  /// What is sent to Discord for [t] at [position], as [options] say. Settings' preview draws this very map, so
  /// what it shows is what Discord gets.
  Map<String, dynamic> activity(
    Track t, {
    required Duration position,
    Duration? duration,
    String? quality,
    bool playing = true,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = now - position.inMilliseconds;
    final videoId = t.videoId ?? _videoIdFrom(t.sourceUrl);
    // YouTube's own thumbnails are 4:3 with black bars; a song's square art is preferred.
    final cover = !options.cover
        ? null
        : t.artworkUrl ?? (videoId == null ? null : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg');
    final listenUrl = videoId != null
        ? 'https://music.youtube.com/watch?v=$videoId'
        : t.soundcloudId != null || t.spotifyId != null
        ? t.sourceUrl
        : null;
    final artistUrl = t.artistId == null || t.soundcloudId != null
        ? null
        : 'https://music.youtube.com/channel/${t.artistId}';
    final artist = t.artist.trim();
    final shown = options.quality && quality != null ? shortQuality(quality) : null;
    return {
      'type': 2, // "Listening to"
      // The member list shows the song's title (2) or the app's name (0).
      'status_display_type': options.songInList ? 2 : 0,
      // Laid out like the music apps' own presence: the song, then who sings it, then the album under the cover.
      'details': _clip(t.title),
      'details_url': ?listenUrl,
      'state': _clip(artist.isNotEmpty ? artist : (quality ?? 'Riflay')),
      'state_url': ?artistUrl,
      // Paused: no clock, which would run on.
      if (options.time && playing)
        'timestamps': {'start': start, 'end': ?(duration == null ? null : start + duration.inMilliseconds)},
      'assets': {
        // Remote URLs work as images; local files fall back to the logo, an art
        // asset in the Discord developer portal still named after the app's old name.
        'large_image': cover ?? 'openmusic',
        // The line under the song: the album, and the sound's quality for all to see.
        'large_text': _clip([t.album ?? t.title, ?shown].join(' · ')),
        'large_url': ?listenUrl,
        // The app's logo on the cover's corner, with the sound's quality for those who hover it.
        if (cover != null || !playing) 'small_image': 'openmusic',
        if (cover != null || !playing) 'small_text': _clip([if (!playing) tr.paused, ?quality, 'Riflay'].join(' · ')),
      },
      // Discord allows two buttons; friends who like the music can get the app.
      'buttons': [
        if (options.listenButton && listenUrl != null) {'label': 'Listen on YouTube Music', 'url': listenUrl},
        if (options.appButton) {'label': 'Download Riflay', 'url': downloadUrl},
      ],
    };
  }

  /// [quality] ("FLAC · 24-bit / 96 kHz") as short as a profile line wants it: "FLAC 24/96", "Opus 160 kbps",
  /// "WAV 32-bit float/48". The home-screen widget's quality chip shows it too.
  static String shortQuality(String quality) => quality
      .replaceAllMapped(RegExp(r'(\d+)-bit / ([\d.]+) kHz'), (m) => '${m[1]}/${m[2]}')
      .replaceAllMapped(RegExp(r'(\d+-bit float) / ([\d.]+) kHz'), (m) => '${m[1]}/${m[2]}')
      .replaceAll(' kHz', '')
      .replaceAll(' · ', ' ');

  static String? _videoIdFrom(String? url) => url == null ? null : Uri.tryParse(url)?.queryParameters['v'];

  /// Discord requires 2–128 characters.
  static String _clip(String s) {
    final t = s.trim();
    if (t.length < 2) return t.padRight(2, ' ');
    return t.length > 128 ? '${t.substring(0, 127)}…' : t;
  }

  Future<void> _send() async {
    if (_disposed || _sending || (_conn == null && (_wanted == null || _reconnect != null))) return;
    _sending = true;
    try {
      final conn = await _ensureConnected();
      if (conn == null || !identical(conn, _conn) || _disposed) return;
      // The player can skip, pause or disable RPC while Discord is handshaking.
      final activity = _enabled ? _wanted : null;
      final nonce = '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
      conn.send(1, {
        'cmd': 'SET_ACTIVITY',
        'args': {'pid': pid, 'activity': activity},
        'nonce': nonce,
      });
      if (activity == null) {
        _heartbeat?.cancel();
        _heartbeat = null;
      } else {
        _startHeartbeat();
      }
      _lastSent = DateTime.now();
      _pending?.cancel();
      _log('SET_ACTIVITY sent (nonce $nonce${activity == null ? ', clearing' : ''})');
    } catch (e) {
      _log('SET_ACTIVITY failed to send ($e); will reconnect');
      _drop();
    } finally {
      _sending = false;
    }
  }

  /// Shares one connection attempt between calls: an update arriving while the handshake is in flight now waits
  /// for it instead of being dropped.
  Future<_IpcConnection?> _ensureConnected() {
    final conn = _conn;
    if (conn != null) return Future.value(conn);
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<_IpcConnection?> _connect() async {
    final paths = _socketPaths().toList();
    _log('scanning ${paths.length} IPC endpoint(s)');
    for (final path in paths) {
      if (_disposed || !_enabled) return null;
      _IpcConnection? conn;
      try {
        conn = await _IpcConnection.open(path, onClosed: _lost, onMessage: _onMessage);
        if (conn == null) continue;
        _log('IPC connected: $path');
        conn.send(0, {'v': 1, 'client_id': clientId});
        _log('handshake sent to $path (v1, client $clientId)');
        final ready = await conn.ready.timeout(const Duration(seconds: 3), onTimeout: () => false);
        if (ready && !_disposed && _enabled) {
          _log('handshake accepted by $path');
          _conn = conn;
          _backoff = _minBackoff;
          _reconnect?.cancel();
          _reconnect = null;

          return conn;
        }
        _log('handshake refused by $path; trying the next endpoint');
        conn.close();
      } catch (e) {
        _log('IPC handshake on $path failed ($e); trying the next endpoint');
        conn?.close();
      }
    }
    if (!_disposed && _enabled) {
      _log('no Discord IPC endpoint answered; retrying in ${_backoff.inMilliseconds} ms');
      _scheduleReconnect();
    }
    return null; // Discord isn't running; the retry timer tries again.
  }

  /// Logs what Discord answered, so a device where the presence silently stays empty can be told apart from one
  /// whose activity Discord rejected.
  void _onMessage(int op, Map<String, dynamic> payload) {
    if (payload['evt'] == 'READY') return; // The handshake's own await logs it.
    final cmd = payload['cmd'];
    final nonce = payload['nonce'];
    final suffix = nonce == null ? '' : ' (nonce $nonce)';
    if (payload['evt'] == 'ERROR') {
      _log('$cmd rejected$suffix: ${payload['data']}');
    } else if (cmd == 'SET_ACTIVITY') {
      _log('SET_ACTIVITY ok$suffix');
    }
  }

  /// A connection was closed by Discord (quit, restart, or a pipe error): retry with backoff and put the last
  /// presence back once it is listening again.
  void _lost(_IpcConnection conn) {
    if (!identical(conn, _conn)) return; // An abandoned attempt must not drop the live connection.
    _log('IPC closed: ${conn.path}');
    _conn = null;
    conn.close();
    _scheduleReconnect();
  }

  void _drop() {
    final conn = _conn;
    if (conn == null) return;
    _conn = null;
    conn.close();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    // Nothing to restore: reconnecting only to clear a presence Discord already forgot would be wasted work.
    if (_disposed || !_enabled || _wanted == null || _reconnect != null) return;
    final delay = _backoff;
    _reconnect = Timer(delay, () {
      _reconnect = null;
      if (_disposed || !_enabled || _conn != null) return;
      unawaited(_send());
    });
    _backoff = Duration(milliseconds: min(_backoff.inMilliseconds * 2, _maxBackoff.inMilliseconds));
  }

  /// While connected, resend now and then: a restarted Discord forgets the activity, and on Windows the pipe
  /// only reports the hang-up on the next write.
  void _startHeartbeat() {
    if (_heartbeat != null || _heartbeatEvery <= Duration.zero) return;
    _heartbeat = Timer.periodic(_heartbeatEvery, (_) {
      if (_disposed || !_enabled) return;
      if (_conn == null) {
        _scheduleReconnect();
        return;
      }
      // Never let the keepalive push a burst past Discord's 5 updates per 20 s.
      if (_wanted != null && DateTime.now().difference(_lastSent) >= _minInterval) unawaited(_send());
    });
  }

  /// Every endpoint Discord may be listening on: `discord-ipc-0` to `discord-ipc-9`, in the order Discord's own
  /// client tries them, since another client (Canary, PTB, Vesktop…) can hold the first ones.
  static Iterable<String> candidatePaths() sync* {
    if (Host.isWindows) {
      for (var i = 0; i < 10; i++) {
        yield r'\\?\pipe\discord-ipc-'
            '$i';
      }
      return;
    }
    // Where Discord itself looks for the socket: every one of these that is set,
    // in its order, then /tmp. A shared /tmp is last because it is open to other
    // accounts on the machine, which could stand in for Discord there and hear
    // what's playing; the user's own runtime directories are preferred.
    final env = Host.environment;
    final bases = <String>[];
    for (final key in const ['XDG_RUNTIME_DIR', 'TMPDIR', 'TMP', 'TEMP']) {
      final dir = env[key];
      if (dir != null && dir.isNotEmpty && !bases.contains(dir)) bases.add(dir);
    }
    if (!bases.contains('/tmp')) bases.add('/tmp');
    // Plain installs, then Flatpak and Snap sandboxes.
    const subdirs = [
      '',
      'app/com.discordapp.Discord/',
      'app/dev.vencord.Vesktop/',
      'snap.discord/',
      '.flatpak/com.discordapp.Discord/xdg-run/',
    ];
    for (final base in bases) {
      for (final sub in subdirs) {
        for (var i = 0; i < 10; i++) {
          yield '$base/${sub}discord-ipc-$i';
        }
      }
    }
  }

  void dispose() {
    _disposed = true;
    _pending?.cancel();
    _reconnect?.cancel();
    _heartbeat?.cancel();
    final conn = _conn;
    if (conn != null) {
      try {
        conn.send(1, {
          'cmd': 'SET_ACTIVITY',
          'args': {'pid': pid, 'activity': null},
          'nonce': 'bye',
        });
      } catch (_) {}
    }
    _drop();
  }
}

/// One framed IPC connection (socket or named pipe).
class _IpcConnection {
  _IpcConnection._(this.path, this._write, this._closer, this._onLost, this._onMessage);

  /// The endpoint this came from, for logs.
  final String path;
  final void Function(List<int> bytes) _write;
  final void Function() _closer;
  final void Function(_IpcConnection conn) _onLost;
  final void Function(int op, Map<String, dynamic> payload)? _onMessage;
  final _ready = Completer<bool>();
  final _buffer = BytesBuilder();
  bool _closed = false;

  Future<bool> get ready => _ready.future;

  static Future<_IpcConnection?> open(
    String path, {
    required void Function(_IpcConnection conn) onClosed,
    void Function(int op, Map<String, dynamic> payload)? onMessage,
  }) async {
    try {
      if (Host.isWindows) {
        final pipe = await File(path).open(mode: FileMode.append);
        late final _IpcConnection conn;
        // A RandomAccessFile runs one operation at a time: a read left waiting for
        // Discord made every write fail ("an async operation is currently pending").
        // Discord answers each message with one frame, so each write reads its answer.
        var queue = Future<void>.value();
        void enqueue(Future<void> Function() op) =>
            queue = queue.then((_) => op()).catchError((Object _) => conn._onClosed());
        conn = _IpcConnection._(
          path,
          (b) => enqueue(() async {
            await pipe.writeFrom(b);
            await conn._readFrame(pipe).timeout(const Duration(seconds: 5));
          }),
          () => enqueue(pipe.close),
          onClosed,
          onMessage,
        );
        return conn;
      }
      if (FileSystemEntity.typeSync(path) != FileSystemEntityType.unixDomainSock) return null;
      final socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      ).timeout(const Duration(seconds: 2));
      final conn = _IpcConnection._(path, socket.add, socket.destroy, onClosed, onMessage);
      // A write after Discord hung up fails here, not in send(): listen does the cleanup.
      socket.done.ignore();
      socket.listen(conn._onData, onDone: conn._onClosed, onError: (_) => conn._onClosed());
      return conn;
    } catch (_) {
      return null;
    }
  }

  /// Reads one frame (Windows: the answer to the message just written).
  Future<void> _readFrame(RandomAccessFile pipe) async {
    Future<Uint8List> exactly(int n) async {
      final out = BytesBuilder(copy: false);
      while (out.length < n) {
        final chunk = await pipe.read(n - out.length);
        if (chunk.isEmpty) throw const FileSystemException('Discord closed the pipe');
        out.add(chunk);
      }
      return out.takeBytes();
    }

    final header = await exactly(8);
    final length = ByteData.sublistView(header).getInt32(4, Endian.little);
    if (length < 0 || length > _maxFrame) throw const FileSystemException('Not a Discord frame');
    _onData([...header, ...await exactly(length)]);
  }

  /// Discord's replies are a few hundred bytes; anything this big isn't Discord.
  static const _maxFrame = 64 << 10;

  void _onClosed() {
    if (_closed) return;
    _closed = true;
    if (!_ready.isCompleted) _ready.complete(false);
    try {
      _closer();
    } catch (_) {}
    _onLost(this);
  }

  void _onData(List<int> data) {
    _buffer.add(data);
    var bytes = _buffer.toBytes();
    while (bytes.length >= 8) {
      final header = ByteData.sublistView(bytes, 0, 8);
      final op = header.getInt32(0, Endian.little);
      final len = header.getInt32(4, Endian.little);
      if (len < 0 || len > _maxFrame) {
        _onClosed();
        return;
      }
      if (bytes.length < 8 + len) break;
      final Map<String, dynamic> payload;
      try {
        payload = jsonDecode(utf8.decode(bytes.sublist(8, 8 + len))) as Map<String, dynamic>;
      } catch (_) {
        _onClosed(); // Not a Discord frame; start over on a fresh connection.
        return;
      }
      _handle(op, payload);
      bytes = bytes.sublist(8 + len);
    }
    _buffer
      ..clear()
      ..add(bytes);
  }

  void _handle(int op, Map<String, dynamic> payload) {
    if (op == 1 && payload['evt'] == 'READY' && !_ready.isCompleted) {
      _ready.complete(true);
      return;
    }
    if (op == 2) {
      // CLOSE: bad client id, a second client for the same app, etc.
      if (!_ready.isCompleted) _ready.complete(false);
      _onClosed();
      return;
    }
    if (op == 3 && !Host.isWindows) {
      send(4, payload);
      return;
    }
    _onMessage?.call(op, payload);
  }

  void send(int op, Map<String, dynamic> payload) {
    if (_closed) throw const SocketException('closed');
    final body = utf8.encode(jsonEncode(payload));
    final header = ByteData(8)
      ..setInt32(0, op, Endian.little)
      ..setInt32(4, body.length, Endian.little);
    _write([...header.buffer.asUint8List(), ...body]);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _closer();
    } catch (_) {}
  }
}
