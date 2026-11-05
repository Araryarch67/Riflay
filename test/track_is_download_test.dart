import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';

void main() {
  final file = Uri.file('/music/abc.flac');

  test('a file downloaded from YouTube is a download', () {
    final t = Track(id: '$file', uri: file, title: 'S', artist: 'A', sourceUrl: 'https://www.youtube.com/watch?v=abc');
    expect(t.isDownload, isTrue);
  });

  test("a file of one's own is not", () {
    expect(Track(id: '$file', uri: file, title: 'S', artist: 'A').isDownload, isFalse);
  });

  test('a streamed song is not', () {
    expect(Track.youtube(videoId: 'abc', title: 'S', artist: 'A').isDownload, isFalse);
  });
}
