import 'package:flutter/foundation.dart';

import '../models/track.dart';
import 'playlist_transfer.dart';
import 'spotify_library.dart';
import 'youtube_music_account.dart';

/// How one item of the run ended.
enum SpotifyOutcome {
  /// Songs found in YouTube Music and saved as a playlist.
  playlist,

  /// The album itself was saved to the YouTube Music library.
  albumSaved,

  /// The artist is followed in YouTube Music.
  followed,

  /// An artist YouTube Music doesn't have.
  artistMissing,

  /// None of the songs are on YouTube Music.
  noSongs,

  /// Something went wrong ([SpotifyImportResult.message]).
  failed,
}

class SpotifyImportResult {
  const SpotifyImportResult(
    this.item,
    this.outcome, {
    this.found = 0,
    this.total = 0,
    this.missing = const [],
    this.message,
  });

  final SpotifyItem item;
  final SpotifyOutcome outcome;

  /// Songs saved and songs asked for (playlists).
  final int found;
  final int total;
  final List<ForeignSong> missing;
  final String? message;

  bool get ok =>
      outcome == SpotifyOutcome.playlist || outcome == SpotifyOutcome.albumSaved || outcome == SpotifyOutcome.followed;

  /// One line for the summary.
  String get line => switch (outcome) {
    SpotifyOutcome.playlist => '${item.name}: $found of $total songs',
    SpotifyOutcome.albumSaved => '${item.name}: saved to your library',
    SpotifyOutcome.followed => '${item.name}: followed',
    SpotifyOutcome.artistMissing => '${item.name}: not found on YouTube Music',
    SpotifyOutcome.noSongs => '${item.name}: no songs found on YouTube Music',
    SpotifyOutcome.failed => '${item.name}: ${message ?? 'something went wrong'}',
  };
}

/// Copies chosen Spotify library items into YouTube Music / Riflay, one after
/// the other, and tells its listeners how far it is. Everything it needs from
/// outside comes in as functions, so it runs (and is tested) without a network.
class SpotifyImporter extends ChangeNotifier {
  SpotifyImporter({
    required this.songs,
    required this.search,
    required this.videos,
    required this.save,
    required this.canEdit,
    required this.findAlbum,
    required this.saveAlbum,
    required this.findArtist,
    required this.follow,
    this.onImported,
  });

  /// The songs of a playlist, Liked Songs or album.
  final Future<ForeignPlaylist> Function(SpotifyItem item) songs;
  final Future<List<Track>> Function(String query) search;
  final Future<List<Track>> Function(String query) videos;

  /// Saves matched songs as a playlist.
  final Future<void> Function(String title, List<Track> tracks) save;

  /// Signed in to YouTube Music: albums can be saved and artists followed.
  final bool canEdit;

  /// The YouTube Music id of the same album / artist, or null.
  final Future<String?> Function(SpotifyItem album) findAlbum;
  final Future<String?> Function(SpotifyItem artist) findArtist;

  /// Saves the album to the library; false when YouTube Music wouldn't take it.
  final Future<bool> Function(String browseId) saveAlbum;
  final Future<void> Function(String browseId) follow;

  /// Called with the uri of every item that worked.
  final void Function(String uri)? onImported;

  var _items = const <SpotifyItem>[];
  final results = <SpotifyImportResult>[];
  var _index = 0;
  var _matched = 0;
  var _matchTotal = 0;
  var _running = false;
  var _cancelled = false;
  var _signedOut = false;

  bool get running => _running;
  bool get cancelled => _cancelled;

  /// Spotify refused the sign-in during the run; the run stopped there.
  bool get signedOut => _signedOut;

  /// Position of the item being imported, from 1.
  int get position => _index + 1;
  int get count => _items.length;
  SpotifyItem? get current => _running && _index < _items.length ? _items[_index] : null;

  /// Songs looked up so far in the current playlist, and how many it has.
  int get matched => _matched;
  int get matchTotal => _matchTotal;

  int get succeeded => results.where((r) => r.ok).length;

  /// "Playlist 2 of 7" for the item being imported.
  String get positionLabel {
    final kind = switch (current?.kind) {
      SpotifyItemKind.album => 'Album',
      SpotifyItemKind.artist => 'Artist',
      _ => 'Playlist',
    };
    return '$kind $position of $count';
  }

  /// Stops after the song being looked up; what was saved stays.
  void cancel() {
    if (!_running) return;
    _cancelled = true;
    notifyListeners();
  }

  /// Imports [items] in order. One failing never stops the rest; a
  /// [SpotifySignedOut] or [cancel] does.
  Future<void> run(List<SpotifyItem> items) async {
    if (_running) return;
    _items = items;
    results.clear();
    _cancelled = false;
    _signedOut = false;
    _running = true;
    for (_index = 0; _index < items.length && !_cancelled; _index++) {
      final item = items[_index];
      _matched = 0;
      _matchTotal = 0;
      notifyListeners();
      try {
        final r = await _import(item);
        if (r != null) results.add(r);
        if (r != null && r.ok) onImported?.call(item.uri);
      } on SpotifySignedOut {
        _signedOut = true;
        break;
      } catch (e) {
        if (_cancelled) break;
        debugPrint('Spotify import of ${item.name}: $e');
        results.add(SpotifyImportResult(item, SpotifyOutcome.failed, message: _describe(e)));
      }
    }
    _running = false;
    notifyListeners();
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// The YouTube Music album that is [album]: same title, and an artist of
  /// the Spotify album named in its subtitle. Null when none is.
  static String? pickAlbum(SpotifyItem album, List<RemotePlaylist> hits) {
    final title = _norm(album.name);
    final artists = [
      for (final a in (album.subtitle ?? '').split(RegExp(r'\s*,\s*|\s+&\s+')))
        if (_norm(a).isNotEmpty) _norm(a),
    ];
    for (final h in hits) {
      if (h.browseId == null || _norm(h.title) != title) continue;
      final sub = _norm(h.subtitle ?? '');
      if (artists.isEmpty || artists.any(sub.contains)) return h.browseId;
    }
    return null;
  }

  /// The YouTube Music artist with the same name as [artist], or null.
  static String? pickArtist(SpotifyItem artist, List<RemotePlaylist> hits) {
    final name = _norm(artist.name);
    for (final h in hits) {
      if (h.browseId != null && _norm(h.title) == name) return h.browseId;
    }
    return null;
  }

  static String _describe(Object e) => switch (e) {
    PlaylistTransferError(:final message) => message,
    _ => YoutubeMusicAccount.describe(e),
  };

  Future<SpotifyImportResult?> _import(SpotifyItem item) async {
    switch (item.kind) {
      case SpotifyItemKind.artist:
        if (!canEdit) {
          return SpotifyImportResult(item, SpotifyOutcome.failed, message: 'sign in to YouTube Music first');
        }
        final id = await findArtist(item);
        if (_cancelled) return null;
        if (id == null) return SpotifyImportResult(item, SpotifyOutcome.artistMissing);
        await follow(id);
        return SpotifyImportResult(item, SpotifyOutcome.followed);
      case SpotifyItemKind.album:
        if (canEdit) {
          String? id;
          try {
            id = await findAlbum(item);
          } on SpotifySignedOut {
            rethrow;
          } catch (e) {
            debugPrint('Spotify import: album ${item.name} not looked up: $e');
          }
          if (_cancelled) return null;
          if (id != null) {
            try {
              if (await saveAlbum(id)) return SpotifyImportResult(item, SpotifyOutcome.albumSaved);
            } catch (e) {
              debugPrint('Spotify import: album ${item.name} not saved: $e');
            }
            if (_cancelled) return null;
          }
        }
        return _playlist(item);
      case SpotifyItemKind.liked:
      case SpotifyItemKind.playlist:
        return _playlist(item);
    }
  }

  Future<SpotifyImportResult?> _playlist(SpotifyItem item) async {
    final list = await songs(item);
    if (_cancelled) return null;
    _matchTotal = list.songs.length;
    notifyListeners();
    final r = await PlaylistTransfer.match(
      list.songs,
      search,
      videos: videos,
      cancelled: () => _cancelled,
      onProgress: (n) {
        _matched = n;
        notifyListeners();
      },
    );
    if (_cancelled) return null;
    if (r.found.isEmpty) {
      return SpotifyImportResult(item, SpotifyOutcome.noSongs, total: list.songs.length, missing: r.missing);
    }
    await save(item.name, r.found);
    return SpotifyImportResult(
      item,
      SpotifyOutcome.playlist,
      found: r.found.length,
      total: list.total,
      missing: r.missing,
    );
  }
}
