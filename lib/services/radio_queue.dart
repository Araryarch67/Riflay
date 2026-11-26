import 'dart:math';

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
      final sameArtist = credits.any(artists.contains);
      final strictMatch = SmartMerge.same(seed, track);
      if (!strictMatch && _title(track) != title) continue;
      final sourceLength = seed.duration;
      final resultLength = track.duration;
      final difference = sourceLength == null || resultLength == null ? null : (sourceLength - resultLength).abs();
      if (difference != null && difference > const Duration(seconds: 8)) continue;
      // The artist written another way (ときのそら on the file, TOKINOSORA on YouTube Music): the same title and
      // length still name the song.
      if (!sameArtist &&
          (_title(track) != title || difference == null || difference > const Duration(seconds: 3))) {
        continue;
      }
      final score =
          (strictMatch ? 10.0 : 0.0) +
          (sameArtist ? 6.0 : 0.0) +
          (sameArtist && credits.first == artists.first ? 4.0 : 0.0) +
          (difference == null ? 0.0 : 2 - difference.inMilliseconds / 4000);
      if (score <= bestScore) continue;
      bestScore = score;
      best = track;
    }
    return best;
  }

  /// Songs from the person's own library to play after [seed], for a radio that needs no internet. Only songs that
  /// play from this device count (not saved streams). Closest first: the seed's album, then any song credited to one
  /// of its artists, then everything else; each group shuffled with [random]. Songs in [excluded] (recent plays,
  /// what is already queued) never come back, nor other copies of [seed].
  static List<Track> fromLibrary({
    required Track seed,
    required Iterable<Track> library,
    Iterable<Track> excluded = const [],
    int limit = 25,
    Random? random,
  }) {
    random ??= Random();
    final skip = <String>{};
    for (final track in [seed, ...excluded]) {
      skip.addAll({track.id, ?track.offlineId});
    }
    final seedTitle = _title(seed);
    final seedArtists = _artists(seed).toSet();
    final seedAlbum = seed.album == null ? null : _key(seed.album!);
    final groups = [<Track>[], <Track>[], <Track>[]];
    final seen = <String>{};
    for (final track in library) {
      if (track.streams || skip.contains(track.id) || (track.offlineId != null && skip.contains(track.offlineId))) {
        continue;
      }
      if (!seen.add(track.id)) continue;
      final artists = _artists(track);
      final sharesArtist = artists.any(seedArtists.contains);
      // Another copy of the seed itself (a download beside the original file, say).
      if (sharesArtist && seedTitle.isNotEmpty && _title(track) == seedTitle) continue;
      final sameAlbum =
          seedAlbum != null && seedAlbum.isNotEmpty && track.album != null && _key(track.album!) == seedAlbum;
      groups[sameAlbum && (sharesArtist || seedArtists.isEmpty)
              ? 0
              : sharesArtist
              ? 1
              : 2]
          .add(track);
    }
    return [for (final group in groups) ...(group..shuffle(random))].take(limit).toList();
  }

  /// [first] and [second] taken in turn, so neither crowds the other out of a capped queue.
  static List<Track> interleave(List<Track> first, List<Track> second) => [
    for (var i = 0; i < max(first.length, second.length); i++) ...[
      if (i < first.length) first[i],
      if (i < second.length) second[i],
    ],
  ];

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
