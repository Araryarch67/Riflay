import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';

void main() {
  final song = Track.youtube(videoId: 'a', title: 'Song', artist: 'Someone', artworkUrl: 'https://x/song.jpg');
  final photo = Track.youtube(videoId: 'artist-UC1', title: 'Someone', artist: 'Someone', artworkUrl: 'https://x/me.jpg');

  test('a playlist is pictured by its first song', () {
    final p = Collection(kind: CollectionKind.playlist, title: 'Mix', subtitle: '', tracks: [song]);
    expect(p.cover, song);
  });

  test("an artist's photo takes the place of their first song's cover", () {
    final a = Collection(kind: CollectionKind.artist, title: 'Someone', subtitle: '', tracks: [song]).withPicture(photo);
    expect(a.cover, photo);
    expect(a.tracks, [song]);
    expect(a.title, 'Someone');
  });
}
