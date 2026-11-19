import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/daily_mix.dart';

Track song(String id, String title, String artist) => Track.youtube(videoId: id, title: title, artist: artist);

void main() {
  final day = DateTime(2026, 11, 20);

  test('mix uses actual credits, alternates familiar and related tracks, and deduplicates sources', () {
    final favorite = song('a', 'One', 'Artist');
    final recent = [favorite, song('b', 'Two', 'Artist, Another artist')];
    final available = [
      song('copy', 'ONE', 'artist'),
      song('c', 'Three', 'Another artist'),
      song('d', 'Four', 'Artist'),
      song('e', 'Unrelated', 'Someone else'),
    ];
    final mix = buildDailyMix(recent: recent, available: available, day: day);
    expect(mix.map((track) => track.videoId), unorderedEquals(['a', 'b', 'c', 'd']));
    expect(mix.first, isIn(recent));
    expect(mix[1], isNot(isIn(recent)));
    expect(buildDailyMix(recent: recent.reversed, available: available.reversed, day: day), mix);
    expect(buildDailyMix(recent: const [], available: available, day: day), isEmpty);
  });

  test('artist sections use the credit list and leave unknown credits out', () {
    final solo = song('solo', 'One', 'Artist');
    final collab = song('collab', 'Two', 'Another artist; ARTIST');
    final uncredited = song('none', 'Three', Track.unknownArtist);
    final sections = artistSongSections('artist', [solo, collab, uncredited]);
    expect(sections.solo, [solo]);
    expect(sections.collaborations, [collab]);
  });
}
