import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/library_views.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track download(String path, String video, {String title = 'Kyapi'}) => Track(
  id: Uri.file(path).toString(),
  uri: Uri.file(path),
  title: title,
  artist: 'Houshou Marine',
  sourceUrl: 'https://music.youtube.com/watch?v=$video',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('one entry per downloaded video: the newest whose file is there', () {
    final old = download('/dl/v1.opus', 'v1');
    final again = download('/dl/v1.flac', 'v1');
    final other = download('/dl/v2.opus', 'v2', title: 'Other');
    final mine = Track(id: 'file:///m/a.flac', uri: Uri.file('/m/a.flac'), title: 'Kyapi', artist: 'X');
    // The old file is gone, the new one is there.
    expect(LibraryViews.withoutRepeatedDownloads([old, other, again, mine], (t) => t != old), [other, again, mine]);
    // The newer file is the one missing: the older, still there, stays.
    expect(LibraryViews.withoutRepeatedDownloads([old, again], (t) => t == old), [old]);
    // A single entry is kept even when its file can't be seen (a card unreadable for now).
    expect(LibraryViews.withoutRepeatedDownloads([other], (_) => false), [other]);
  });

  test(
    'loading a library with a song downloaded twice keeps the playable one, in the library and in playlists',
    () async {
      final dir = Directory.systemTemp.createTempSync('riflay-dupes');
      addTearDown(() => dir.deleteSync(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => dir.path,
      );
      final kept = File('${dir.path}/v1.flac')..writeAsBytesSync([0]);
      final stale = download('${dir.path}/v1.opus', 'v1'); // its file is gone
      final fresh = download(kept.path, 'v1');
      SharedPreferences.setMockInitialValues({
        'library.v1': jsonEncode([stale.toJson(), fresh.toJson()]),
        'playlists.v1': jsonEncode([
          UserPlaylist(id: 'p', name: 'Code and Chill', tracks: [stale], createdAt: 0).toJson(),
        ]),
      });
      final c = PlayerController();
      await c.load();
      expect(c.library.map((t) => t.id), [fresh.id], reason: 'shown once, the playable one');
      expect(c.playlists.single.tracks.single.id, fresh.id, reason: 'the playlist plays the file that is there');
      expect(c.downloadedCopy(Track.youtube(videoId: 'v1', title: 'Kyapi', artist: 'Houshou Marine'))?.id, fresh.id);
      c.dispose();
    },
  );
}
