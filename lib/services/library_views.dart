import 'dart:collection';

import '../models/track.dart';
import 'language.dart';

/// What the UI reads from one version of the library, each part worked out on
/// first use. A new library gets a new one. Songs whose tags were filled in
/// place are folded in by [patched], which keeps what was already worked out
/// instead of sorting and grouping the whole library again.
class LibraryViews {
  LibraryViews(this.tracks, this.edits);

  LibraryViews._(this.tracks, this.edits);

  final List<Track> tracks;
  final int edits;

  /// Parts worked out so far; each is filled by its getter, or carried over by [patched].
  Map<String, Track>? _byId;
  List<String>? _searchKeys;
  Collection? _allSongs;
  List<Track>? _recentlyAdded;
  Collection? _youtubeDownloads;
  bool _youtubeDone = false;
  Map<String, Track>? _downloads;
  List<Collection>? _albums;
  List<Collection>? _artists;
  Map<String, Collection>? _artistByName;
  List<Collection>? _albumsAndArtists;
  Map<String, Collection>? _albumOfTrack;

  /// The same library after [changed] (by id: the song's new version) replaced songs in place.
  /// [old] holds the versions they replaced.
  LibraryViews patched(int edits, Map<String, Track> changed, Map<String, Track> old) {
    final next = LibraryViews._(tracks, edits);
    // The tags that decide where a song sits or which group it joins.
    var sameShape = true;
    var sameTitles = true;
    for (final e in changed.entries) {
      final a = old[e.key];
      final b = e.value;
      if (a == null) {
        sameShape = sameTitles = false;
        break;
      }
      if (a.title != b.title) sameTitles = false;
      if (a.title != b.title ||
          a.artist != b.artist ||
          a.album != b.album ||
          a.trackNumber != b.trackNumber ||
          a.discNumber != b.discNumber ||
          a.addedAt != b.addedAt ||
          a.sourceUrl != b.sourceUrl) {
        sameShape = false;
      }
    }
    final byId = _byId;
    if (byId != null) next._byId = {...byId, ...changed};
    final keys = _searchKeys;
    if (keys != null) {
      // Keys follow the library's order; the library list was edited in place, so an id's place is found by scanning once.
      final fresh = List<String>.of(keys);
      var left = changed.length;
      for (var i = 0; i < tracks.length && left > 0; i++) {
        if (changed[tracks[i].id] case final t?) {
          fresh[i] = _keyOf(t);
          left--;
        }
      }
      next._searchKeys = fresh;
    }
    List<Track> swap(List<Track> l) => [for (final t in l) changed[t.id] ?? t];
    Collection swapped(Collection c) =>
        Collection(kind: c.kind, id: c.id, title: c.title, subtitle: c.subtitle, tracks: swap(c.tracks));
    final all = _allSongs;
    if (all != null && sameTitles) next._allSongs = swapped(all);
    if (sameShape) {
      next._recentlyAdded = _recentlyAdded == null ? null : swap(_recentlyAdded!);
      next._youtubeDone = _youtubeDone;
      next._youtubeDownloads = _youtubeDownloads == null ? null : swapped(_youtubeDownloads!);
      next._downloads = _downloads == null
          ? null
          : {for (final e in _downloads!.entries) e.key: changed[e.value.id] ?? e.value};
      next._albums = _albums == null ? null : [for (final a in _albums!) swapped(a)];
      next._artists = _artists == null ? null : [for (final a in _artists!) swapped(a)];
      // Derived maps hang off the lists above, so they are worked out again on first use.
    }
    return next;
  }

  static String _keyOf(Track t) => '${t.title}\u0000${t.artist}\u0000${t.album ?? ''}'.toLowerCase();

  List<Track>? _library;
  List<Track> get library => _library ??= UnmodifiableListView(tracks);

  Map<String, Track> get byId => _byId ??= {for (final t in tracks) t.id: t};

  /// Title, artist and album of each song in lower case, for search.
  List<String> get searchKeys => _searchKeys ??= [for (final t in tracks) _keyOf(t)];

  Collection get allSongs => _allSongs ??= Collection(
    kind: CollectionKind.allSongs,
    title: tr.allSongs,
    subtitle: tr.songsPlural(tracks.length),
    tracks: _sortedBy(tracks, (t) => t.title.toLowerCase()),
  );

  List<Track> get recentlyAdded => _recentlyAdded ??= ([...tracks]..sort((a, b) => b.addedAt.compareTo(a.addedAt)));

  Collection? get youtubeDownloads {
    if (_youtubeDone) return _youtubeDownloads;
    _youtubeDone = true;
    final downloaded = tracks.where((t) => t.sourceUrl != null).toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    if (downloaded.isEmpty) return null;
    return _youtubeDownloads = Collection(
      kind: CollectionKind.youtube,
      title: tr.downloaded,
      subtitle: tr.songsPlural(downloaded.length),
      tracks: downloaded,
    );
  }

  /// Video id → the newest library file downloaded from it (an older one may be gone: a format since changed).
  Map<String, Track> get downloads {
    final cached = _downloads;
    if (cached != null) return cached;
    final out = <String, Track>{};
    for (final t in tracks) {
      if (youtubeVideoIdOf(t.sourceUrl) case final id?) out[id] = t;
    }
    return _downloads = out;
  }

  /// [library] with one entry per downloaded video. A song downloaded again (another format, after a delete)
  /// used to be added beside the first, which may point at a file that is gone: it showed twice, and the stale
  /// one wouldn't play. Of the entries of one video, the newest whose file [exists] stays (the newest, if none
  /// does); a video with a single entry is never touched, so a card that is only unreadable for now loses nothing.
  static List<Track> withoutRepeatedDownloads(List<Track> library, bool Function(Track t) exists) {
    final byVideo = <String, List<int>>{};
    for (final (i, t) in library.indexed) {
      if (youtubeVideoIdOf(t.sourceUrl) case final id? when t.path != null) (byVideo[id] ??= []).add(i);
    }
    final drop = <int>{};
    for (final at in byVideo.values) {
      if (at.length < 2) continue;
      final present = at.where((i) => exists(library[i])).toList();
      final keep = (present.isEmpty ? at : present).last;
      drop.addAll(at.where((i) => i != keep));
    }
    if (drop.isEmpty) return library;
    return [
      for (final (i, t) in library.indexed)
        if (!drop.contains(i)) t,
    ];
  }

  List<Collection> get albums {
    final cached = _albums;
    if (cached != null) return cached;
    final groups = <String, List<Track>>{};
    for (final t in tracks) {
      final key = t.albumKey;
      if (key != null) (groups[key] ??= []).add(t);
    }
    final albums = [
      for (final group in groups.values)
        Collection(
          kind: CollectionKind.album,
          title: group.first.album!,
          subtitle: group.first.artist,
          tracks: group..sort(compareAlbumOrder),
        ),
    ];
    return _albums = _sortedBy(albums, (a) => a.title.toLowerCase());
  }

  List<Collection> get artists {
    final cached = _artists;
    if (cached != null) return cached;
    final groups = <String, List<Track>>{};
    for (final t in tracks) {
      // A song by several artists is on each one's page.
      for (final name in t.artists) {
        (groups[name] ??= []).add(t);
      }
    }
    return _artists = [
      for (final e in groups.entries)
        Collection(
          kind: CollectionKind.artist,
          title: e.key,
          subtitle: tr.songsPlural(e.value.length),
          tracks: e.value
            ..sort((a, b) {
              final byAlbum = (a.album ?? '').compareTo(b.album ?? '');
              return byAlbum != 0 ? byAlbum : compareAlbumOrder(a, b);
            }),
        ),
    ]..sort((a, b) => b.tracks.length.compareTo(a.tracks.length));
  }

  Map<String, Collection> get artistByName => _artistByName ??= {for (final a in artists) a.title: a};

  List<Collection> get albumsAndArtists =>
      _albumsAndArtists ??= _sortedBy([...albums, ...artists], (c) => c.title.toLowerCase());

  Map<String, Collection> get albumOfTrack => _albumOfTrack ??= {
    for (final a in albums)
      for (final t in a.tracks) t.id: a,
  };

  /// [items] sorted by [key], each key computed once; equal keys keep their order.
  static List<T> _sortedBy<T>(List<T> items, String Function(T) key) {
    final keys = [for (final i in items) key(i)];
    final order = List<int>.generate(items.length, (i) => i)
      ..sort((a, b) {
        final c = keys[a].compareTo(keys[b]);
        return c != 0 ? c : a - b;
      });
    return [for (final i in order) items[i]];
  }
}
