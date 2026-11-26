import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/radio_queue.dart';

Track song(String id, String title, String artist, {int? seconds}) => Track.youtube(
  videoId: id,
  title: title,
  artist: artist,
  duration: seconds == null ? null : Duration(seconds: seconds),
);

void main() {
  test('a seed from SoundCloud uses YouTube Music and picks the recording rather than the first result', () async {
    final seed = Track.soundcloud(
      trackId: 'source',
      title: 'Silhouette',
      artist: 'KANA-BOON',
      duration: const Duration(seconds: 240),
    );
    final same = song('match', seed.title, seed.artist, seconds: 240);
    final next = song('related', 'Another song', seed.artist);
    final results = await RadioQueue.load(
      seed,
      searchSongs: (query) async {
        expect(query, 'KANA-BOON Silhouette');
        return [
          song('wrong-artist', seed.title, 'Different artist', seconds: 240),
          song('live', '${seed.title} (Live)', seed.artist, seconds: 240),
          song('different-length', seed.title, seed.artist, seconds: 290),
          same,
        ];
      },
      upNext: (track) async {
        expect(track, same);
        return [same, next];
      },
    );
    expect(results, [next]);
  });

  test('a known YouTube identity bypasses search, and unmatched local music cannot seed unrelated radio', () async {
    final known = song('known', 'Known', 'Artist');
    await RadioQueue.load(
      known,
      searchSongs: (_) async => fail('Should use the known YouTube identity'),
      upNext: (track) async {
        expect(track, same(known));
        return [song('related', 'Related', 'Artist')];
      },
    );
    final local = Track(id: 'local', uri: Uri.file('/music/title.mp3'), title: 'Title', artist: 'Artist');
    final results = await RadioQueue.load(
      local,
      searchSongs: (_) async => [song('cover', 'Title', 'Cover artist')],
      upNext: (_) async => fail('The unrelated artist must never seed radio'),
    );
    expect(results, isEmpty);
  });

  test('a local song whose artist YouTube Music writes another way still gets its radio', () async {
    final local = Track(
      id: 'king',
      uri: Uri.file('/music/king.flac'),
      title: 'KING',
      artist: 'ときのそら',
      duration: const Duration(milliseconds: 138453),
    );
    final match = song('ihREuw5PKs4', 'KING', 'TOKINOSORA', seconds: 139);
    final related = song('related', 'Diva', 'TOKINOSORA');
    final results = await RadioQueue.load(
      local,
      searchSongs: (_) async => [song('other-king', 'KING', 'Kanaria', seconds: 150), match],
      upNext: (track) async => track == match ? [match, related] : fail('only the same title and length'),
    );
    expect(results, [related]);
  });

  test('an empty video queue retries the same recording under a different YouTube Music ID', () async {
    final video = song('video', 'Title', 'Artist', seconds: 210);
    final audio = song('audio', 'Title', 'Artist', seconds: 210);
    final related = song('related', 'Related', 'Other artist');
    final seeds = <String?>[];
    final results = await RadioQueue.load(
      video,
      searchSongs: (_) async => [video, audio],
      upNext: (track) async {
        seeds.add(track.videoId);
        return track.videoId == audio.videoId ? [related] : [];
      },
    );
    expect(seeds, ['video', 'audio']);
    expect(results, [related]);
  });

  test('radio filters library and video duplicates, and spaces out lead artists within the provider order', () {
    final seed = song('seed', 'Origin', 'Artist A');
    final one = song('1', 'One', 'Artist A');
    final two = song('2', 'Two', 'Artist A');
    final three = song('3', 'Three', 'Artist B');
    final four = song('4', 'Four', 'Artist C');
    final recent = song('recent', 'Recently played', 'Artist D');
    final tracks = RadioQueue.arrange(
      seed: seed,
      excluded: [recent],
      candidates: [
        one,
        song('mv', 'One [Official MV]', 'Artist A'),
        song('new-id', 'Recently played (Official Music Video)', 'Artist D'),
        two,
        seed,
        three,
        four,
      ],
    );
    expect(tracks, [three, one, four, two]);
  });
}
