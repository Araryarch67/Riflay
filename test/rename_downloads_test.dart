import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('old downloads named by id get "Artist - Title", with their lyrics, and playlists follow', () async {
    final dir = await Directory.systemTemp.createTemp('riflay-rename-');
    addTearDown(() => dir.delete(recursive: true));
    final song = await File(p.join(dir.path, 'mono_123.flac')).writeAsString('a');
    await File(p.join(dir.path, 'mono_123.lrc')).writeAsString('[00:01]hi');
    final yt = await File(p.join(dir.path, 'dQw4w9WgXcQ.opus')).writeAsString('b');
    // Already a song name, and a file of the person's own: both left alone.
    final named = await File(p.join(dir.path, 'Someone - Else.flac')).writeAsString('c');
    final own = await File(p.join(dir.path, 'mono_9.flac')).writeAsString('d');

    Track download(File f, String artist, String title) => Track(
      id: Uri.file(f.path).toString(),
      uri: Uri.file(f.path),
      title: title,
      artist: artist,
      sourceUrl: 'https://example.com/$title',
    );
    final tracks = [
      download(song, 'Kanaria', 'KING'),
      download(yt, 'Rick Astley', 'Never Gonna Give You Up'),
      download(named, 'Someone', 'Else'),
      Track.fromUri(Uri.file(own.path)),
    ];
    SharedPreferences.setMockInitialValues({
      'library.v1': jsonEncode([for (final t in tracks) t.toJson()]),
    });
    final c = PlayerController();
    await c.load();
    c.createPlaylist('Mine', tracks: [c.library.first]);

    expect(await c.renameDownloads(), 2);
    final names = c.library.map((t) => p.basename(t.path!)).toSet();
    expect(names, {
      'Kanaria - KING.flac',
      'Rick Astley - Never Gonna Give You Up.opus',
      'Someone - Else.flac',
      'mono_9.flac',
    });
    expect(await File(p.join(dir.path, 'Kanaria - KING.lrc')).readAsString(), '[00:01]hi');
    expect(await song.exists(), isFalse);
    expect(p.basename(c.playlists.single.tracks.single.path!), 'Kanaria - KING.flac');
    expect(
      c.library.firstWhere((t) => t.title == 'KING').id,
      Uri.file(p.join(dir.path, 'Kanaria - KING.flac')).toString(),
    );

    // A second run finds nothing left to do.
    expect(await c.renameDownloads(), 0);
  });
}
