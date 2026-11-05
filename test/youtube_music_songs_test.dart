import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/youtube_music_account.dart';
import 'package:riflay/ui/ytmusic_edit.dart';

void main() {
  final file = Uri.file('/music/abc.flac');
  final download = Track(
    id: '$file',
    uri: file,
    title: 'Song',
    artist: 'Artist',
    duration: const Duration(minutes: 3),
    sourceUrl: 'https://www.youtube.com/watch?v=abc',
  );
  final ownFile = Track(id: '/music/own.flac', uri: Uri.file('/music/own.flac'), title: 'Own', artist: 'Me');
  final streamed = Track.youtube(videoId: 'xyz', title: 'S', artist: 'A');

  group('which songs are on YouTube', () {
    test('a download knows the video it came from', () {
      expect(download.youtubeId, 'abc');
      expect(Track(id: 'b', uri: file, title: 'S', artist: 'A', sourceUrl: 'https://youtu.be/def').youtubeId, 'def');
    });

    test("a streamed song is its own video, a file of one's own is none", () {
      expect(streamed.youtubeId, 'xyz');
      expect(ownFile.youtubeId, isNull);
      expect(ownFile.onYoutube, isNull);
    });

    test('a download goes to YouTube Music as the streamed song', () {
      final song = download.onYoutube!;
      expect((song.id, song.videoId, song.isRemote), ('yt:abc', 'abc', true));
      expect((song.title, song.artist, song.duration), ('Song', 'Artist', const Duration(minutes: 3)));
      expect(identical(streamed.onYoutube, streamed), isTrue);
    });
  });

  group('adding many to a YouTube Music playlist', () {
    test('keeps the ones on YouTube and counts the rest', () {
      final r = YoutubeMusicAccount.youtubeSongs([download, ownFile, streamed, ownFile]);
      expect(r.songs.map((t) => t.videoId), ['abc', 'xyz']);
      expect(r.skipped, 2);
    });

    test('says how many were skipped', () {
      expect(
        addedMessage(name: 'Gym', tracks: 4, added: 2, skipped: 2),
        'Added 2 songs to Gym. 2 not on YouTube Music, skipped',
      );
      expect(addedMessage(name: 'Gym', tracks: 3, added: 3), 'Added 3 songs to Gym');
      expect(addedMessage(name: 'Gym', tracks: 1, added: 1), 'Added to Gym');
      expect(addedMessage(name: 'Gym', tracks: 1, added: 0), 'Already in Gym');
    });

    test('a local-only song says it is not on YouTube Music', () {
      expect(addedMessage(name: 'Gym', tracks: 1, added: 0, skipped: 1), "This song isn't on YouTube Music");
      expect(addedMessage(name: 'Gym', tracks: 2, added: 0, skipped: 2), 'None of these songs are on YouTube Music');
    });
  });
}
