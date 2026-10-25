import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/ios_folders.dart';

void main() {
  Track song(String path) => Track.fromUri(Uri.file(path));

  test('songs under a moved folder follow it', () {
    final out = IosFolders.repoint(
      [song('/old/Music/a/one.flac'), song('/other/two.flac')],
      {'/old/Music': '/new/Music'},
    );
    expect(out[0].path, '/new/Music/a/one.flac');
    expect(out[1].path, '/other/two.flac');
  });

  test('a folder with the same name prefix is left alone', () {
    final out = IosFolders.repoint([song('/old/Music2/x.flac')], {'/old/Music': '/new/Music'});
    expect(out.single.path, '/old/Music2/x.flac');
  });

  test('nothing moved changes nothing', () {
    final tracks = [song('/a/b.flac')];
    expect(IosFolders.repoint(tracks, {'/a': '/a'}), same(tracks));
    expect(IosFolders.repoint(tracks, const {}), same(tracks));
  });

  test('streamed songs are untouched', () {
    final t = Track(id: 'yt1', uri: Uri.parse('https://example.com/x'), title: 't', artist: 'a', videoId: 'v');
    expect(IosFolders.repoint([t], {'/a': '/b'}).single.uri, t.uri);
  });
}
