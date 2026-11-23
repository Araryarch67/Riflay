import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/host.dart';
import 'private_files.dart';
import 'spotify_account.dart';

/// The bridge couldn't sign in or serve a song; [reason] is its own word for why (`auth`, `failed`…), for the log.
class SpotifyBridgeError implements Exception {
  const SpotifyBridgeError(this.reason);
  final String reason;

  @override
  String toString() => 'Spotify bridge: $reason';
}

/// Plays Spotify songs from the signed-in Premium account: `spotify_bridge` (tool/spotify_bridge, librespot) runs
/// beside Riflay, signs in with the account's token and serves each song's audio on a loopback port, which mpv
/// reads like any stream (see `SpotifyAudioSource`). Started on the first Spotify song, not at launch; it ends
/// with Riflay (its stdin closes).
///
/// The first sign-in uses the web player's token ([SpotifyAccount.auth]); librespot then keeps credentials of its
/// own in the app's private folder, which later launches use.
class SpotifyBridge {
  SpotifyBridge({this.executable, this.directory, Future<String> Function({bool force})? token})
    : _token = token ?? _accountToken;

  static final instance = SpotifyBridge();

  /// The bridge's file, when it is not the one beside the app (tests).
  final String? executable;
  final Directory? directory;
  final Future<String> Function({bool force}) _token;

  static const _name = 'spotify_bridge.exe';
  static const _folder = 'spotify_bridge';

  static Future<String> _accountToken({bool force = false}) async =>
      (await SpotifyAccount.instance.auth(force: force)).accessToken;

  /// Whether this build plays Spotify songs: Windows for now, with the bridge beside the app.
  /// `RIFLAY_NO_SPOTIFY_PLAYBACK` leaves it out (the Spotify page then only imports).
  static final bool supported = () {
    if (!Host.isWindows || Host.environment.containsKey('RIFLAY_NO_SPOTIFY_PLAYBACK')) return false;
    return File(p.join(File(Platform.resolvedExecutable).parent.path, _name)).existsSync();
  }();

  Process? _process;
  Future<({int port, String secret})>? _ready;
  final _pending = <int, Completer<Object?>>{};
  int _nextId = 0;

  Future<Directory> _state() async => directory ?? Directory(p.join((await PrivateFiles.dir()).path, _folder));

  /// Where mpv fetches [trackId] from. Starts the bridge and signs in on first use.
  Future<Uri> streamUri(String trackId) async {
    final at = await (_ready ??= _start());
    return Uri(scheme: 'http', host: '127.0.0.1', port: at.port, pathSegments: [at.secret, trackId]);
  }

  Future<({int port, String secret})> _start() async {
    try {
      final host = executable ?? p.join(File(Platform.resolvedExecutable).parent.path, _name);
      final state = await _state();
      await state.create(recursive: true);
      final process = await Process.start(host, [state.path], runInShell: false);
      _process = process;
      // Only written with RIFLAY_SPOTIFY_LOG; librespot's lines can name the account.
      process.stderr.drain<void>().ignore();
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        try {
          final reply = jsonDecode(line) as Map;
          final done = _pending.remove(reply['id']);
          if (done == null) return;
          if (reply.containsKey('error')) {
            done.completeError(SpotifyBridgeError('${reply['error']}'));
          } else {
            done.complete(reply['result']);
          }
        } catch (_) {
          // Only protocol replies are read.
        }
      });
      process.exitCode.then((_) {
        if (_process != process) return;
        _process = null;
        _ready = null;
        for (final request in _pending.values) {
          if (!request.isCompleted) request.completeError(const SpotifyBridgeError('closed'));
        }
        _pending.clear();
      }).ignore();
      final hello = await _call('hello');
      if (hello is! Map || hello['port'] is! int || hello['secret'] is! String) {
        throw const SpotifyBridgeError('hello');
      }
      await signIn();
      return (port: hello['port'] as int, secret: hello['secret'] as String);
    } catch (e) {
      debugPrint('Spotify bridge not started: $e');
      _stop();
      rethrow;
    }
  }

  /// Signs the bridge in. Its kept credentials go first; the web player's token is for the first time and for
  /// when Spotify stops taking those ([fresh] asks the account for a new token).
  Future<void> signIn({bool fresh = false}) async {
    try {
      await _call('login', {'token': await _token(force: fresh)}, const Duration(seconds: 40));
    } on SpotifyBridgeError catch (e) {
      if (fresh || e.reason != 'auth') rethrow;
      await _call('login', {'token': await _token(force: true)}, const Duration(seconds: 40));
    }
  }

  Future<Object?> _call(
    String method, [
    Map<String, Object?> params = const {},
    Duration timeout = const Duration(seconds: 15),
  ]) async {
    final process = _process;
    if (process == null) throw const SpotifyBridgeError('closed');
    final id = ++_nextId;
    final request = Completer<Object?>();
    _pending[id] = request;
    try {
      process.stdin.writeln(jsonEncode({'id': id, 'method': method, 'params': params}));
      return await request.future.timeout(timeout);
    } finally {
      _pending.remove(id);
    }
  }

  void _stop() {
    final process = _process;
    _process = null;
    _ready = null;
    process?.stdin.close().catchError((Object _) {});
    process?.kill();
  }

  /// Signing out of Spotify: the bridge stops and the credentials librespot kept are deleted.
  Future<void> signOut() async {
    _stop();
    try {
      final kept = File(p.join((await _state()).path, 'credentials.json'));
      if (await kept.exists()) await kept.delete();
    } catch (e) {
      debugPrint('Spotify bridge: credentials not deleted: $e');
    }
  }
}
