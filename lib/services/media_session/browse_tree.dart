import 'package:audio_service/audio_service.dart';

import '../../models/track.dart';
import '../language.dart' show tr;

/// What the car's browser can list. Riflay's is [PlayerControllerLibrary]; tests use a fake.
abstract class BrowseLibrary {
  List<Collection> get playlists;
  List<Track> get recent;

  /// Liked music; empty when YouTube Music is not signed in.
  Future<List<Track>> liked();
}

/// A song picked in the car: the list it was in and where, so playing it queues the whole list.
typedef BrowsePick = ({List<Track> tracks, int index, String from});

/// The folders Android Auto (and any other MediaBrowser client) shows under Riflay: Playlists, Liked music and
/// Recently played. It answers [BaseAudioHandler.getChildren] on the same audio_service session as the
/// notification; there is no second service.
class BrowseTree {
  BrowseTree(this._lib);

  final BrowseLibrary _lib;

  static const playlistsId = 'playlists';
  static const likedId = 'liked';

  /// audio_service's own id for the "last played" entry that cars ask for on start.
  static const recentId = AudioService.recentRootId;
  static const _playlistPrefix = 'playlist:';
  static const _sep = '\u001f';

  /// Cars show a few screens at most and drivers don't scroll; also keeps one reply well under Binder's 1 MB limit.
  // shortcut: first 100 only, page with `options` when a library needs more.
  static const maxItems = 100;

  Future<List<MediaItem>> children(String parentId) async {
    switch (parentId) {
      case AudioService.browsableRootId:
        return [
          _folder(playlistsId, tr.playlists),
          _folder(likedId, tr.likedMusic),
          _folder(recentId, tr.recentlyPlayed),
        ];
      case playlistsId:
        return [
          for (final p in _lib.playlists.take(maxItems))
            _folder('$_playlistPrefix${p.id}', p.title, subtitle: p.subtitle),
        ];
    }
    final tracks = await _tracks(parentId);
    return [for (final t in (tracks ?? const <Track>[]).take(maxItems)) _song(parentId, t)];
  }

  /// The list a song id from [children] was in, with the song's place in it; null when it is gone (the playlist
  /// was deleted or the song removed since the car listed it).
  Future<BrowsePick?> resolve(String mediaId) async {
    final cut = mediaId.indexOf(_sep);
    if (cut < 0) return null;
    final listId = mediaId.substring(0, cut), trackId = mediaId.substring(cut + 1);
    final tracks = await _tracks(listId);
    final i = tracks?.indexWhere((t) => t.id == trackId) ?? -1;
    if (tracks == null || i < 0) return null;
    return (tracks: tracks, index: i, from: _title(listId));
  }

  Future<List<Track>?> _tracks(String listId) async {
    if (listId == likedId) return _lib.liked();
    if (listId == recentId) return _lib.recent;
    if (!listId.startsWith(_playlistPrefix)) return null;
    final id = listId.substring(_playlistPrefix.length);
    return _lib.playlists.where((p) => p.id == id).firstOrNull?.tracks;
  }

  String _title(String listId) => switch (listId) {
    likedId => tr.likedMusic,
    recentId => tr.recentlyPlayed,
    _ => _lib.playlists.where((p) => '$_playlistPrefix${p.id}' == listId).firstOrNull?.title ?? tr.playlists,
  };

  static MediaItem _folder(String id, String title, {String? subtitle}) =>
      MediaItem(id: id, title: title, album: subtitle, playable: false);

  static MediaItem _song(String listId, Track t) => MediaItem(
    id: '$listId$_sep${t.id}',
    title: t.title,
    artist: t.artist,
    album: t.album,
    duration: t.duration,
    artUri: t.streams && t.artworkUrl != null ? Uri.tryParse(t.artworkUrl!) : null,
  );
}
