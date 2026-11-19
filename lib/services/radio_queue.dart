import 'package:flutter/foundation.dart' show setEquals;

import '../models/track.dart';
import 'download_matches.dart';
import 'smart_merge.dart';

/// Matches a radio seed to YouTube Music and arranges its recommendations.
abstract final class RadioQueue {
  static final _videoLabel = RegExp(
    r'\s*[\[(【（]\s*(?:official\s+)?(?:music video|video|mv|audio|lyrics?|lyric video|visualizer)\s*[\])】）]',
    caseSensitive: false,
  );

  static final _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  static String _key(String value) => value.toLowerCase().replaceAll(_separators, '');

  static String _title(Track track) => _key(track.title.replaceAll(_videoLabel, ''));

  static List<String> _artists(Track track) => [
    for (final artist in track.artists)
      if (_key(artist) case final key when key.isNotEmpty) key,
  ];

  /// Recommendations come from YouTube Music even when the seed plays from another source.
  static Future<List<Track>> load(
    Track seed, {
    required Future<List<Track>> Function(String) searchSongs,
    required Future<List<Track>> Function(Track) upNext,
  }) async {
    final known = seed.onYoutube;
    if (known != null) {
      final recommendations = await upNext(known);
      if (recommendations.isNotEmpty) return recommendations;
    }
    if (seed.artists.isEmpty || _title(seed).isEmpty) return const [];
    final results = await searchSongs('${seed.artist} ${seed.title}'.trim());
    final match = _match(seed, results.where((track) => track.youtubeId != known?.youtubeId));
    if (match == null) return const [];
    return (await upNext(match)).where((track) => track.youtubeId != match.youtubeId).toList();
  }

  static Track? _match(Track seed, Iterable<Track> results) {
    final artists = _artists(seed);
    final title = _title(seed);
    final versions = DownloadMatches.versions(seed.title);
    Track? best;
    var bestScore = double.negativeInfinity;
    for (final track in results) {
      if (!track.isRemote || !setEquals(versions, DownloadMatches.versions(track.title))) continue;
      final credits = _artists(track);
      if (credits.isEmpty || !credits.any(artists.contains)) continue;
      final strictMatch = SmartMerge.same(seed, track);
      if (!strictMatch && _title(track) != title) continue;
      final sourceLength = seed.duration;
      final resultLength = track.duration;
      final difference = sourceLength == null || resultLength == null ? null : (sourceLength - resultLength).abs();
      if (difference != null && difference > const Duration(seconds: 8)) continue;
      final score =
          (strictMatch ? 10.0 : 0.0) +
          (credits.first == artists.first ? 4.0 : 0.0) +
          (difference == null ? 0.0 : 2 - difference.inMilliseconds / 4000);
      if (score <= bestScore) continue;
      bestScore = score;
      best = track;
    }
    return best;
  }

  /// Keeps the provider's order when possible, spacing consecutive songs by the same lead artist.
  static List<Track> arrange({
    required Track seed,
    required Iterable<Track> candidates,
    required Iterable<Track> excluded,
    int limit = 25,
  }) {
    final ids = <String>{};
    final byTitle = <String, Set<String>>{};
    bool mark(Track track) {
      final idsForTrack = {track.id, ?track.offlineId, ?track.youtubeId};
      if (idsForTrack.any(ids.contains)) return false;
      ids.addAll(idsForTrack);
      final title = _title(track);
      if (title.isEmpty) return true;
      final knownArtists = byTitle.putIfAbsent(title, () => {});
      final artists = _artists(track);
      final duplicate = artists.any(knownArtists.contains);
      if (!duplicate) knownArtists.addAll(artists);
      return !duplicate;
    }

    for (final track in [seed, ...excluded]) {
      mark(track);
    }
    final remaining = [
      for (final track in candidates)
        if (mark(track)) (track: track, artist: _artists(track).firstOrNull),
    ];
    var previous = _artists(seed).firstOrNull;
    final ordered = <Track>[];
    while (remaining.isNotEmpty && ordered.length < limit) {
      var index = 0;
      if (previous != null && remaining.first.artist == previous) {
        final next = remaining.take(6).toList().indexWhere((item) => item.artist != null && item.artist != previous);
        if (next >= 0) index = next;
      }
      final item = remaining.removeAt(index);
      ordered.add(item.track);
      previous = item.artist;
    }
    return ordered;
  }
}
