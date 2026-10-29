import 'package:youtube_explode_dart/youtube_explode_dart.dart' show Video, VideoSearchList, YoutubeExplode;

import '../models/track.dart';

/// Plain YouTube search (not YouTube Music): any video can be played like a song.
/// Holds the paging state of the latest [search]; use one instance per search box.
class YoutubeVideoSearch {
  YoutubeVideoSearch({YoutubeExplode? client}) : _yt = client ?? YoutubeExplode(), _ownsClient = client == null;

  final YoutubeExplode _yt;
  final bool _ownsClient;
  VideoSearchList? _page;
  final _seen = <String>{};
  int _generation = 0;

  /// Videos this short are taken for Shorts and left out.
  static const shortsMaxLength = Duration(seconds: 60);

  /// Pages skipped over while looking for something playable, so a page of only Shorts or live streams isn't the end.
  static const _maxEmptyPages = 3;

  /// Whether [more] may have something.
  bool get hasMore => _page != null;

  /// First page of results for [query]; resets paging.
  Future<List<Track>> search(String query) async {
    final generation = ++_generation;
    _seen.clear();
    _page = null;
    final first = await _yt.search.search(query);
    if (generation != _generation) return const [];
    return _take(first);
  }

  /// The next page, or empty when there are no more (or a newer [search] began meanwhile).
  Future<List<Track>> more() async {
    final generation = _generation;
    var page = _page;
    for (var i = 0; i < _maxEmptyPages && page != null; i++) {
      final next = await page.nextPage();
      if (generation != _generation) return const [];
      if (next == null) {
        _page = null;
        return const [];
      }
      final tracks = _take(next);
      if (tracks.isNotEmpty) return tracks;
      page = next;
    }
    return const [];
  }

  List<Track> _take(VideoSearchList page) {
    _page = page;
    return [
      for (final t in toTracks(page))
        if (_seen.add(t.videoId!)) t,
    ];
  }

  /// What YouTube suggests while typing [query].
  Future<List<String>> suggestions(String query) async {
    try {
      return await _yt.search.getQuerySuggestions(query);
    } catch (_) {
      return const [];
    }
  }

  void dispose() {
    _generation++;
    if (_ownsClient) _yt.close();
  }

  /// Search hits as songs: live streams and Shorts (and anything without a length) are dropped.
  static List<Track> toTracks(Iterable<Video> videos) => [
    for (final v in videos)
      if (!v.isLive && v.duration != null && v.duration! > shortsMaxLength)
        Track.youtube(
          videoId: v.id.value,
          title: v.title,
          artist: v.author,
          duration: v.duration,
          artworkUrl: 'https://i.ytimg.com/vi/${v.id.value}/hqdefault.jpg',
        ),
  ];
}
