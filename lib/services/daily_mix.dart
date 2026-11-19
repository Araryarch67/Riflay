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
