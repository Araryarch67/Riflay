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

  test('Made for you holds several mixes: the daily one, the artists played most, and new artists', () {
    final recent = [
      for (var i = 0; i < 6; i++) song('a$i', 'A $i', 'Alpha'),
      for (var i = 0; i < 4; i++) song('b$i', 'B $i', 'Beta'),
    ];
    final available = [
      for (var i = 6; i < 10; i++) song('a$i', 'A $i', 'Alpha'),
      for (var i = 4; i < 8; i++) song('b$i', 'B $i', 'Beta'),
      for (var i = 0; i < 6; i++) song('n$i', 'N $i', 'Newcomer'),
    ];
    final mixes = buildHomeMixes(recent: recent, available: available, day: day);
    expect(mixes.map((m) => m.kind), [MixKind.daily, MixKind.artist, MixKind.artist, MixKind.discovery]);
    expect(mixes[1].artist, 'Alpha', reason: 'the artist played most comes first');
    expect(mixes[2].artist, 'Beta');
    expect(mixes[1].tracks.every((t) => t.artist == 'Alpha' || t.artist == 'Beta'), isTrue);
    expect(
      mixes.last.tracks.every((t) => t.artist == 'Newcomer'),
      isTrue,
      reason: 'Discovery leaves played artists out',
    );
    expect(mixes.map((m) => m.id).toSet(), hasLength(mixes.length));
    final again = buildHomeMixes(recent: recent, available: available, day: day);
    expect([for (final m in again) m.tracks], [for (final m in mixes) m.tracks], reason: 'the same all day');
    expect(
      buildHomeMixes(recent: const [], available: available, day: day).map((m) => m.kind),
      isNot(contains(MixKind.artist)),
    );
  });
}
