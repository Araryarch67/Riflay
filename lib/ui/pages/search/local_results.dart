import 'package:flutter/foundation.dart';

import '../../../models/track.dart';
import '../../../services/player_controller.dart';

/// What the library holds for a typed query: songs, artists and albums.
@immutable
class LocalResults {
  const LocalResults({required this.songs, required this.artists, required this.albums});

  final List<Track> songs;
  final List<Collection> artists;
  final List<Collection> albums;
}

/// The library's answer to the last query, kept until the query or the library
/// changes. The page rebuilds for reasons that have nothing to do with the
/// library (a filter chip, a result arriving, a window resize); each used to
/// scan every song again.
class LocalSearchMemo {
  /// Library scans so far, for tests: an unrelated rebuild must not add to it.
  @visibleForTesting
  static int scans = 0;

  PlayerController? _c;
  String? _query;
  int? _revision;
  LocalResults? _results;

  /// Results for [query] in the library as of [revision] ([PlayerController.libraryRevision]).
  LocalResults of(PlayerController c, String query, int revision) {
    final q = query.trim().toLowerCase();
    final cached = _results;
    if (cached != null && identical(c, _c) && q == _query && revision == _revision) return cached;
    scans++;
    final results = LocalResults(
      songs: c.search(q),
      artists: q.isEmpty ? c.artists : c.artists.where((a) => a.title.toLowerCase().contains(q)).toList(),
      albums: q.isEmpty ? const [] : c.albums.where((a) => a.title.toLowerCase().contains(q)).toList(),
    );
    _c = c;
    _query = q;
    _revision = revision;
    return _results = results;
  }
}
