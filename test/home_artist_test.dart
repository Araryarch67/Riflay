import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/debug_switches.dart';
import 'package:riflay/ui/pages/home_page.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track _file(String name, String artist, {String? videoId, String? artistId}) => Track(
  id: Uri.file('/m/$name.opus').toString(),
  uri: Uri.file('/m/$name.opus'),
  title: name,
  artist: artist,
  tagged: true,
  sourceUrl: videoId == null ? null : 'https://music.youtube.com/watch?v=$videoId',
  artistId: artistId,
);

Collection _artist(String name, List<Track> tracks) =>
    Collection(kind: CollectionKind.artist, title: name, subtitle: '', tracks: tracks);

/// One downloaded song of Kobo's (it remembers its video and her channel), and two files of Bach's own.
final _library = [
  _file('Downloaded', 'Kobo Kanaeru', videoId: 'vid1', artistId: 'UCkobo'),
  _file('Fugue', 'Bach'),
  _file('Toccata', 'Bach'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => Directory.systemTemp.path,
  );
  tearDown(() => DebugSwitches.localHomeArtists = false);

  group('youtubeSongOf', () {
    test('none for an artist known from files alone', () {
      expect(youtubeSongOf(_artist('Bach', [_file('Fugue', 'Bach')])), isNull);
    });

    test('one download among files of their own is enough', () {
      final download = _file('D', 'Kobo', videoId: 'v', artistId: 'UC1');
      expect(youtubeSongOf(_artist('Kobo', [_file('Own', 'Kobo'), download])), same(download));
    });

    test('prefers a song that names them first and knows their channel', () {
      final featured = _file('F', 'Other, Kobo', videoId: 'a', artistId: 'UCother');
      final unknown = _file('U', 'Kobo', videoId: 'b');
      final known = _file('K', 'Kobo, Other', videoId: 'c', artistId: 'UCkobo');
      expect(youtubeSongOf(_artist('Kobo', [featured, unknown, known])), same(known));
      expect(youtubeSongOf(_artist('Kobo', [featured, unknown])), same(unknown));
      expect(youtubeSongOf(_artist('Kobo', [featured])), same(featured));
    });
  });

  Future<({List<String?> pages, List<Collection> collections})> home(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'library.v1': jsonEncode([for (final t in _library) t.toJson()]),
    });
    final c = PlayerController();
    await tester.runAsync(c.load);
    addTearDown(() => tester.runAsync(() async => c.dispose()));
    // Tall enough for the Artists shelf to be built.
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pages = <String?>[];
    final collections = <Collection>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScope(
          controller: c,
          child: ShellScope(
            compact: false,
            width: 1200,
            open: (_, {location}) => pages.add(location),
            openCollection: collections.add,
            openQueue: () {},
            openNowPlaying: () {},
            openLyrics: () {},
            openDownloads: () {},
            importFromYoutube: () {},
            addFiles: () {},
            addFolder: null,
            child: const Scaffold(body: HomePage()),
          ),
        ),
      ),
    );
    await tester.pump();
    // Home asks YouTube Music for its shelves (refused under test); what that leaves on the fake clock runs out.
    await tester.pump(const Duration(seconds: 1));
    return (pages: pages, collections: collections);
  }

  /// The card of [name] on the Artists shelf (a song's card names its artist too, as its subtitle).
  Finder artistCard(String name) => find.byWidgetPredicate((w) => w is MediaCard && w.title == name && w.circle);

  testWidgets('Home: an artist with one downloaded song opens their YouTube Music page', (tester) async {
    final opened = await home(tester);
    await tester.tap(artistCard('Kobo Kanaeru'));
    await tester.pump();
    expect(opened.pages, ['playlist:UCkobo'], reason: 'the channel the download remembers');
    expect(opened.collections, isEmpty, reason: 'not the library page holding only the download');
  });

  testWidgets('Home: an artist known from files alone opens the library artist', (tester) async {
    final opened = await home(tester);
    await tester.tap(artistCard('Bach'));
    await tester.pump();
    expect(opened.pages, isEmpty);
    expect(opened.collections.single.title, 'Bach');
    expect(opened.collections.single.tracks, hasLength(2));
  });

  testWidgets('RIFLAY_LOCAL_HOME_ARTISTS opens the library artist for a downloaded one too', (tester) async {
    DebugSwitches.localHomeArtists = true;
    final opened = await home(tester);
    await tester.tap(artistCard('Kobo Kanaeru'));
    await tester.pump();
    expect(opened.pages, isEmpty);
    expect(opened.collections.single.title, 'Kobo Kanaeru');
  });
}
