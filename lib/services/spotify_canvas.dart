import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import 'spotify_account.dart';
import 'spotify_library.dart';

/// Spotify Canvas: the short looping video Spotify shows behind a song, shown by Video mode in place of the music
/// video. Read with the signed-in Spotify account (Spotify › Canvas), as the web player reads it: the song is found
/// in Spotify's search by its names, then its Canvas asked for. Off until turned on; nothing is asked of Spotify
/// while it is off or signed out.
class SpotifyCanvas extends ChangeNotifier {
  SpotifyCanvas({SpotifyAccount? account, this.client}) : _account = account ?? SpotifyAccount.instance;

  static final instance = SpotifyCanvas();

  static const _key = 'spotify.canvas.v1';

  final SpotifyAccount _account;

  /// Tests answer for Spotify.
  final SpotifyLibraryClient Function()? client;

  bool enabled = false;
  bool _loaded = false;

  /// Each song's Canvas (null: it has none), by [Track.id].
  final _found = <String, Uri?>{};
  final _asking = <String>{};

  bool get active => enabled && _account.isSignedIn;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    enabled = (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    notifyListeners();
  }

  Future<void> setEnabled(bool v) async {
    enabled = v;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_key, v);
  }

  /// [track]'s Canvas, once looked up; null before, or when it has none.
  Uri? of(Track? track) => !active || track == null ? null : _found[track.id];

  /// Whether [track] was looked up already.
  bool knows(Track track) => _found.containsKey(track.id);

  /// Looks [track]'s Canvas up once; [done] runs when the answer is in.
  void lookUp(Track? track, {VoidCallback? done}) {
    if (track == null || !enabled || track.title.trim().isEmpty || knows(track) || !_asking.add(track.id)) return;
    () async {
          // The saved session is read once, at the first look.
          await _account.load();
          if (!_account.isSignedIn) return (signedOut: true, url: null);
          final spotify = client?.call() ?? _account.client;
          final uri = await spotify.findTrack(track.title, track.artist, duration: track.duration);
          return (signedOut: false, url: uri == null ? null : await spotify.canvasUrl(uri));
        }()
        .then(
          // Signed out: asked again once signed in.
          (r) => r.signedOut ? null : _found[track.id] = r.url,
          onError: (Object e) {
            debugPrint('Spotify Canvas: ${track.title}: $e');
            _found[track.id] = null;
          },
        )
        .whenComplete(() {
          _asking.remove(track.id);
          while (_found.length > 128) {
            _found.remove(_found.keys.first);
          }
          notifyListeners();
          done?.call();
        });
  }

  @visibleForTesting
  void reset() {
    _loaded = false;
    enabled = false;
    _found.clear();
    _asking.clear();
  }
}
