import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/download_files.dart';

void main() {
  test('downloads are named "Artist - Title", with what file systems refuse taken out', () {
    expect(readableDownloadName(artist: 'Kobo Kanaeru', title: 'Oh! Asmara'), 'Kobo Kanaeru - Oh! Asmara');
    expect(readableDownloadName(artist: 'AC/DC', title: 'T.N.T.'), 'AC DC - T.N.T');
    expect(readableDownloadName(artist: 'A', title: 'What? <Live>: "1"'), 'A - What Live 1');
    expect(readableDownloadName(artist: Track.unknownArtist, title: 'KING'), 'KING');
    expect(readableDownloadName(artist: '', title: ''), 'Song');
    expect(readableDownloadName(artist: '', title: 'con'), 'con song');
    expect(readableDownloadName(artist: 'x' * 200, title: 'y').length, lessThanOrEqualTo(150));
  });

  test('a download moves to its song name, numbered when the name is taken', () async {
    final dir = await Directory.systemTemp.createTemp('riflay-names-');
    addTearDown(() => dir.delete(recursive: true));
    final first = await File(p.join(dir.path, 'mono_abc.flac')).writeAsString('a');
    final named = await nameDownload(first, artist: 'Kanaria', title: 'KING');
    expect(p.basename(named.path), 'Kanaria - KING.flac');
    expect(await named.readAsString(), 'a');
    expect(await first.exists(), isFalse);

    final second = await File(p.join(dir.path, 'dQw4w9WgXcQ.opus')).writeAsString('b');
    final again = await File(p.join(dir.path, 'other.flac')).writeAsString('c');
    expect(p.basename((await nameDownload(again, artist: 'Kanaria', title: 'KING')).path), 'Kanaria - KING (2).flac');
    expect(p.basename((await nameDownload(second, artist: 'Kanaria', title: 'KING')).path), 'Kanaria - KING.opus');
  });
}
