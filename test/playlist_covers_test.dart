import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/library_views.dart';
import 'package:riflay/services/metadata.dart';
import 'package:riflay/services/playlist_covers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory folder;
  late List<int> jpeg;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('riflay_playlist_covers_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => folder.path,
    );
    SharedPreferences.setMockInitialValues({});
    jpeg = img.encodeJpg(img.Image(width: 8, height: 8));
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await folder.delete(recursive: true);
  });

  test('a picked picture is kept, found again on the next launch, and removed', () async {
    final covers = PlaylistCovers.instance;
    await covers.load();
    final key = PlaylistCovers.playlistKey('pl1');

    await covers.setCover(key, Uint8List.fromList(jpeg));
    expect(covers.has(key), isTrue);
    final cover = covers.coverOf(key)!;
    expect(cover.path, isNotNull);
    expect(File(cover.path!).existsSync(), isTrue, reason: 'the picture is copied into the app folder');
    expect(covers.coverOr(key, null), isNotNull);

    // The next launch reads the same choice back from the settings.
    await covers.load();
    expect(covers.coverOf(key)?.path, cover.path);

    await covers.removeCover(key);
    expect(covers.has(key), isFalse);
    expect(covers.coverOf(key), isNull);
    expect(File(cover.path!).existsSync(), isFalse);
  });

  test('a cover kept in the settings as a data URL is drawn like any other', () async {
    final url = 'data:image/jpeg;base64,${base64Encode(jpeg)}';
    final cover = Track(
      id: 'cover:web-test',
      uri: Uri.parse(url),
      title: '',
      artist: '',
      tagged: true,
      artworkUrl: url,
    );
    expect(await Metadata.artwork(cover), isNotEmpty);
  });

  test('All songs, Liked music and YouTube Music playlists have their own cover keys', () {
    expect(PlaylistCovers.allSongsKey, isNot(PlaylistCovers.likedKey));
    expect(PlaylistCovers.allSongsKey, isNot(PlaylistCovers.remoteKey('LM')));
    expect(PlaylistCovers.likedKey, isNot(PlaylistCovers.remoteKey('LM')));
    expect(PlaylistCovers.playlistKey('pl1'), isNot(PlaylistCovers.remoteKey('pl1')));
    expect(LibraryViews(const [], 0).allSongs.coverKey, PlaylistCovers.allSongsKey);
  });
}
