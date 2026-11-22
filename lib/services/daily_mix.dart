import 'dart:math';

import '../models/track.dart';

/// A daily selection from playable tracks, using recent artists as the starting point.
/// Both inputs are already available on Home, so composing a mix makes no requests.
List<Track> buildDailyMix({
  required Iterable<Track> recent,
  required Iterable<Track> available,
  required DateTime day,
}) {
  String artistKey(String name) => name.trim().toLowerCase();
  String songKey(Track track) => '${artistKey(track.artist)}|${track.title.trim().toLowerCase()}';
  final familiar = <String, Track>{};
  final artists = <String>{};
  for (final track in recent.take(40)) {
    familiar.putIfAbsent(songKey(track), () => track);
    artists.addAll(track.artists.map(artistKey));
  }
  if (artists.isEmpty) return const [];

  final related = <String, Track>{};
  for (final track in available) {
    final key = songKey(track);
    if (!familiar.containsKey(key) && track.artists.any((name) => artists.contains(artistKey(name)))) {
      related.putIfAbsent(key, () => track);
    }
  }
  final random = Random(day.year * 10000 + day.month * 100 + day.day);
  List<Track> shuffle(Map<String, Track> pool) {
    final keys = pool.keys.toList()..sort();
    return [for (final key in keys) pool[key]!]..shuffle(random);
  }

  final old = shuffle(familiar).iterator;
  final other = shuffle(related).iterator;
  final tracks = <Track>[];
  while (tracks.length < 24) {
    final addedFamiliar = old.moveNext();
    final addedRelated = other.moveNext();
    if (!addedFamiliar && !addedRelated) break;
    if (addedFamiliar) tracks.add(old.current);
    if (addedRelated && tracks.length < 24) tracks.add(other.current);
  }
  return tracks.length < 2 ? const [] : tracks;
}

/// What a mix is made from, for its title and description.
enum MixKind { daily, artist, discovery }

typedef HomeMix = ({MixKind kind, String id, String? artist, List<Track> tracks});

/// Home's "Made for you": the [buildDailyMix], a mix for each of the artists played most lately (their songs and
/// those played next to them), and one of the artists not played lately. Fixed for the day; no requests.
List<HomeMix> buildHomeMixes({
  required Iterable<Track> recent,
  required Iterable<Track> available,
  required DateTime day,
  int artistMixes = 4,
}) {
  String artistKey(String name) => name.trim().toLowerCase();
  String songKey(Track track) => '${artistKey(track.artist)}|${track.title.trim().toLowerCase()}';
  final mixes = <HomeMix>[];
  final daily = buildDailyMix(recent: recent, available: available, day: day);
  if (daily.isNotEmpty) mixes.add((kind: MixKind.daily, id: 'daily-mix', artist: null, tracks: daily));

  final played = recent.take(80).toList();
  final pool = <String, Track>{};
  for (final track in [...played, ...available]) {
    pool.putIfAbsent(songKey(track), () => track);
  }
  // Most played lately first; among equals, the one played last.
  final score = <String, double>{};
  final names = <String, String>{};
  for (final (i, track) in played.indexed) {
    for (final name in track.artists) {
      final key = artistKey(name);
      if (key.isEmpty) continue;
      score[key] = (score[key] ?? 0) + 1 + (played.length - i) / (played.length * 10);
      names.putIfAbsent(key, () => name.trim());
    }
  }
  final top = score.keys.toList()..sort((a, b) => score[b]!.compareTo(score[a]!));
  final seed = day.year * 10000 + day.month * 100 + day.day;
  List<Track> shuffled(Iterable<Track> tracks, int salt) {
    final byKey = {for (final t in tracks) songKey(t): t};
    final keys = byKey.keys.toList()..sort();
    return [for (final key in keys) byKey[key]!]..shuffle(Random(seed + salt));
  }

  for (final artist in top.take(artistMixes)) {
    bool by(Track t) => t.artists.any((name) => artistKey(name) == artist);
    final own = shuffled(pool.values.where(by), artist.hashCode);
    final next = <Track>[];
    for (final (i, track) in played.indexed) {
      if (!by(track)) continue;
      for (final j in [i - 1, i + 1]) {
        if (j >= 0 && j < played.length && !by(played[j])) next.add(played[j]);
      }
    }
    final around = shuffled(next, artist.hashCode + 1).iterator;
    final tracks = <Track>[];
    final seen = <String>{};
    for (final track in own.take(16)) {
      if (seen.add(songKey(track))) tracks.add(track);
      // Every third song, one played next to them.
      if (tracks.length % 3 == 2 && around.moveNext() && seen.add(songKey(around.current))) tracks.add(around.current);
    }
    if (tracks.length >= 4) {
      mixes.add((kind: MixKind.artist, id: 'artist-mix:$artist', artist: names[artist], tracks: tracks));
    }
  }

  final known = score.keys.toSet();
  final fresh = shuffled(
    available.where((t) => t.artists.isNotEmpty && !t.artists.any((name) => known.contains(artistKey(name)))),
    7,
  ).take(24).toList();
  if (fresh.length >= 4) mixes.add((kind: MixKind.discovery, id: 'discovery-mix', artist: null, tracks: fresh));
  return mixes;
}
