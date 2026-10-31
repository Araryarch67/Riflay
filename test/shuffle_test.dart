import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/shuffle.dart';

Track song(String artist, int n) =>
    Track(id: 'file:///m/$artist$n.mp3', uri: Uri.parse('file:///m/$artist$n.mp3'), title: '$n', artist: artist);

List<String> artists(List<Track> order) => [for (final t in order) t.artist];

int clashes(List<Track> order) => [
  for (var i = 1; i < order.length; i++)
    if (order[i].artist == order[i - 1].artist && order[i].artist != Track.unknownArtist) i,
].length;

void main() {
  test('no artist twice in a row when the others can separate them; same songs, first one kept', () {
    final random = Random(7);
    final library = [
      for (var i = 0; i < 6; i++) song('A', i),
      for (var i = 0; i < 4; i++) song('B', i),
      for (var i = 0; i < 3; i++) song('C', i),
    ];
    for (var run = 0; run < 200; run++) {
      final shuffled = [...library]..shuffle(random);
      final out = spreadArtists(shuffled);
      expect(out.first, shuffled.first);
      expect(out.toSet(), library.toSet());
      expect(clashes(out), 0, reason: artists(out).join());
    }
  });

  test('when one artist has too many songs, what is left over stays together at the end', () {
    final out = spreadArtists([song('A', 0), song('A', 1), song('A', 2), song('A', 3), song('B', 0)]);
    expect(artists(out), ['A', 'B', 'A', 'A', 'A']);
  });

  test('songs with no artist never count as a clash, and an artist is matched ignoring case', () {
    final none = [song(Track.unknownArtist, 0), song(Track.unknownArtist, 1), song('x', 0)];
    expect(spreadArtists(none), none);
    expect(artists(spreadArtists([song('Band', 0), song('band', 1), song('Other', 0)])), ['Band', 'Other', 'band']);
  });
}
