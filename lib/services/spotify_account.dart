import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playlist_transfer.dart';
import 'private_files.dart';
import 'spotify_library.dart';
import 'spotify_session.dart';

/// The signed-in Spotify account: the web-player session kept in the
/// app's private folder, fresh tokens on demand, and what was imported so far.
///
/// Only the Spotify import page uses it; it is not part of the player.
class SpotifyAccount extends ChangeNotifier {
  SpotifyAccount({
    Future<SpotifySession?> Function(String cookies)? refresher,
    Future<SpotifySession?> Function()? windowSignIn,
  }) : _refresher = refresher ?? SpotifyLogin.refresh,
       _windowSignIn = windowSignIn ?? SpotifyLogin.signInWithWindow;

  /// The app-wide account, created on first use.
  static final SpotifyAccount instance = SpotifyAccount();

  static const _file = 'spotify_account.json';
  static const _importedKey = 'spotify.imported.v1';

  final Future<SpotifySession?> Function(String cookies) _refresher;
  final Future<SpotifySession?> Function() _windowSignIn;

  SpotifySession? _session;
  String? _name;
  Future<void>? _loading;
  Future<SpotifySession>? _refreshing;
  SpotifyLibraryClient? _client;
  Map<String, DateTime> _imported = {};

  /// True while signing in.
  bool busy = false;

  /// One calm sentence about the last thing that failed, or null.
  String? error;

  bool get isSignedIn => _session != null;

  /// The Spotify display name; null when unknown.
  String? get name => _name;

  /// Reads the saved session once. Never throws.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final file = await PrivateFiles.file(_file);
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map<String, dynamic> && json['session'] is Map<String, dynamic>) {
          final s = SpotifySession.fromJson(json['session'] as Map<String, dynamic>);
          if (s.cookies.isNotEmpty) {
            _session = s;
            _name = json['name'] as String?;
          }
        }
      }
    } catch (e) {
      debugPrint('Spotify: saved account not read: $e');
    }
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_importedKey);
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _imported = {
          for (final e in json.entries)
            if (e.value is int) e.key: DateTime.fromMillisecondsSinceEpoch(e.value as int),
        };
      }
    } catch (e) {
      debugPrint('Spotify: import list not read: $e');
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final file = await PrivateFiles.file(_file);
      await PrivateFiles.write(
        file,
        jsonEncode({if (_session != null) 'session': _session!.toJson(), 'name': _name}),
        secret: true,
      );
    } catch (e) {
      debugPrint('Spotify: account not saved: $e');
    }
  }

  // ── Signing in and out ──────────────────────────────────────────────────

  /// Linux: opens Spotify's sign-in window. False when it was closed or failed
  /// ([error] says why when it failed).
  Future<bool> signInWithWindow() async {
    if (busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final session = await _windowSignIn();
      if (session == null) return false;
      await _adopt(session);
      return true;
    } catch (e) {
      error = _describe(e);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Takes the session the sign-in page produced.
  Future<void> connect(SpotifySession session) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _adopt(session);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _adopt(SpotifySession session) async {
    _session = session;
    _name = null;
    _client?.close();
    _client = null;
    try {
      _name = await client.profileName();
    } catch (e) {
      debugPrint('Spotify: name not read: $e');
    }
    await _save();
  }

  /// Forgets the session, the Spotify cookies and what was imported.
  /// [reason] is shown on the sign-in screen (an expired sign-in).
  Future<void> signOut({String? reason}) async {
    _session = null;
    _name = null;
    _imported = {};
    _client?.close();
    _client = null;
    error = reason;
    notifyListeners();
    try {
      final file = await PrivateFiles.file(_file);
      if (await file.exists()) await PrivateFiles.write(file, '{}', secret: true);
    } catch (e) {
      debugPrint('Spotify: account file not cleared: $e');
    }
    try {
      (await SharedPreferences.getInstance()).remove(_importedKey);
    } catch (_) {}
    await SpotifyLogin.clearWebViewCookies();
  }

  // ── Tokens ──────────────────────────────────────────────────────────────

  /// Tokens for a request: the stored ones until they run out (or [force]),
  /// then a refresh from the cookies. Signs out and throws [SpotifySignedOut]
  /// when Spotify no longer accepts the cookies.
  Future<SpotifyAuth> auth({bool force = false}) async {
    final s = _session;
    if (s == null) throw const SpotifySignedOut();
    if (!force && !s.expired) return _authOf(s);
    final fresh = await (_refreshing ??= _refresh(s).whenComplete(() => _refreshing = null));
    return _authOf(fresh);
  }

  Future<SpotifySession> _refresh(SpotifySession old) async {
    final SpotifySession? next;
    try {
      next = await _refresher(old.cookies);
    } on SpotifyLoginException catch (e) {
      throw PlaylistTransferError(e.message);
    }
    if (next == null) {
      await signOut(reason: SpotifySignedOut.message);
      throw const SpotifySignedOut();
    }
    // Signed out while it refreshed: don't bring the session back.
    if (_session == null) throw const SpotifySignedOut();
    _session = next;
    await _save();
    return next;
  }

  static SpotifyAuth _authOf(SpotifySession s) =>
      (accessToken: s.accessToken, clientToken: s.clientToken, appVersion: s.appVersion);

  /// Reads the library with this account's tokens.
  SpotifyLibraryClient get client => _client ??= SpotifyLibraryClient(auth: auth);

  // ── Imported ────────────────────────────────────────────────────────────

  /// When [uri] was last imported; null if it never was.
  DateTime? importedAt(String uri) => _imported[uri];

  Future<void> markImported(Iterable<String> uris) async {
    final now = DateTime.now();
    for (final u in uris) {
      _imported[u] = now;
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _importedKey,
        jsonEncode({for (final e in _imported.entries) e.key: e.value.millisecondsSinceEpoch}),
      );
    } catch (e) {
      debugPrint('Spotify: import list not saved: $e');
    }
  }

  static String _describe(Object e) => switch (e) {
    SpotifyLoginException(:final message) => message,
    PlaylistTransferError(:final message) => message,
    _ => () {
      debugPrint('Spotify sign-in: $e');
      return 'Couldn\'t sign in to Spotify. Try again.';
    }(),
  };
}
