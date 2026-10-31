import '../models/track.dart';

/// [order] with songs by the same artist moved apart where it can be done, so a shuffle doesn't play two of theirs
/// in a row (a random order does that far more often than it feels random). The first song stays first; the rest
/// keep their shuffled order apart from the moves. When one artist has more songs than the others can separate,
/// the ones left over stay together at the end.
///
/// Pure. A clash is fixed by the next song by someone else; songs left over at the end, all by one artist, are moved
/// back into gaps between others.
List<Track> spreadArtists(List<Track> order) {
  final out = List.of(order);
  for (var i = 1; i < out.length; i++) {
    final before = _artist(out[i - 1]);
    if (before == null || _artist(out[i]) != before) continue;
    var j = i + 1;
    while (j < out.length && _artist(out[j]) == before) {
      j++;
    }
    // Everything after this point is by the same artist: the rest go into gaps earlier on.
    if (j == out.length) return _tuckIn(out, i);
    final t = out[i];
    out[i] = out[j];
    out[j] = t;
  }
  return out;
}

/// From [from] on, [out] is one artist's songs only. Each is moved back to the first gap between two songs by
/// others (never before the first song), while there is one.
List<Track> _tuckIn(List<Track> out, int from) {
  final artist = _artist(out[from]);
  // The gaps before one that was filled were no use, and filling it makes no new one there: each search goes on
  // from the last, so this stays one pass.
  var k = 1;
  for (var i = from; i < out.length; i++) {
    if (_artist(out[i - 1]) != artist) continue;
    while (k < i && (_artist(out[k - 1]) == artist || _artist(out[k]) == artist)) {
      k++;
    }
    if (k >= i) break; // no gap left: these stay together
    out.insert(k, out.removeAt(i));
    k++;
  }
  return out;
}

/// Who a song is by, for telling artists apart; null for songs with no artist, which never clash.
String? _artist(Track t) {
  final a = t.artist.trim().toLowerCase();
  return a.isEmpty || a == Track.unknownArtist.toLowerCase() ? null : a;
}
