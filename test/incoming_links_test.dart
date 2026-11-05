import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/incoming_links.dart';
import 'package:riflay/services/youtube_links.dart';

const id = 'dQw4w9WgXcQ';
const pl = 'PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf';
const album = 'OLAK5uy_kRWydTZEDa2pW7rlr8ldEbH1QBhrHYOZc';

void main() {
  group('the link in shared text', () {
    final cases = <String, YoutubeLink>{
      // "Open with": the link alone.
      'https://music.youtube.com/watch?v=$id': const VideoLink(id),
      'https://music.youtube.com/watch?v=$id&si=AbCdEfGh': const VideoLink(id),
      'https://youtu.be/$id?si=AbCdEfGh': const VideoLink(id),
      'https://www.youtube.com/shorts/$id?feature=share': const VideoLink(id),
      'https://m.youtube.com/watch?v=$id&t=1m30s': const VideoLink(id, startAt: Duration(seconds: 90)),
      // The YouTube app's Share sheet, and messages from chats.
      'Check this out https://youtu.be/$id': const VideoLink(id),
      'lagu ini enak bgt 😭 https://music.youtube.com/watch?v=$id&si=xyz dengerin deh': const VideoLink(id),
      'Never Gonna Give You Up\nhttps://youtu.be/$id': const VideoLink(id),
      '(https://youtu.be/$id).': const VideoLink(id),
      // A song opened from a playlist plays the song.
      'https://music.youtube.com/watch?v=$id&list=$pl': const VideoInPlaylistLink(id, pl),
      // Playlists and albums.
      'Listen to my playlist: https://music.youtube.com/playlist?list=$pl&si=abc': const PlaylistLink(pl),
      'https://youtube.com/playlist?list=$album': const PlaylistLink(album),
      'https://music.youtube.com/browse/VL$pl': const PlaylistLink(pl),
      'https://music.youtube.com/browse/MPREb_BQZvl3BFGay': const AlbumLink('MPREb_BQZvl3BFGay'),
    };
    for (final MapEntry(key: text, value: link) in cases.entries) {
      test(text, () => expect(IncomingLinks.read(text), link));
    }
  });

  group('nothing to open', () {
    for (final text in [
      '',
      'just some words',
      // An 11-letter word is not a video when it is shared, only when it is pasted.
      'dQw4w9WgXcQ',
      'https://example.com/watch?v=$id',
      'https://notyoutube.com/watch?v=$id',
      'https://www.youtube.com/@somechannel',
      'https://music.youtube.com/browse/FEmusic_home',
    ]) {
      test(text.isEmpty ? '(empty)' : text, () => expect(IncomingLinks.read(text), isNull));
    }
  });

  test('links that came before anyone listened wait for the first listener', () {
    final links = IncomingLinks.instance;
    final got = <String>[];
    void handler(String text) => got.add(text);
    links.add('https://youtu.be/$id');
    links.add('  ');
    expect(got, isEmpty);
    links.listen(handler);
    expect(got, ['https://youtu.be/$id']);
    links.add('https://music.youtube.com/playlist?list=$pl');
    expect(got, hasLength(2));
    links.stopListening(handler);
    links.add('later');
    expect(got, hasLength(2));
  });
}
