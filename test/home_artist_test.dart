import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/language.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_presets.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/debug_switches.dart';
import 'package:riflay/ui/pages/collection_page.dart';
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

  Future<({List<String?> pages, List<Collection> collections})> home(
    WidgetTester tester, {
    bool carousel = false,
    bool compact = false,
    bool withMix = false,
    Widget page = const HomePage(),
  }) async {
    SharedPreferences.setMockInitialValues({
      'library.v1': jsonEncode([for (final t in _library) t.toJson()]),
      if (withMix) 'recent.v1': [_library[1].id],
    });
    final c = PlayerController();
    await tester.runAsync(c.load);
    if (carousel) {
      await tester.runAsync(() => PlayerPreset.liquidKawaii.apply(LayoutPrefs.instance));
      addTearDown(() => tester.runAsync(LayoutPrefs.instance.reset));
    }
    addTearDown(() => tester.runAsync(() async => c.dispose()));
    // Tall enough for the Artists shelf to be built.
    final width = compact ? 356.0 : 1200.0;
    await tester.binding.setSurfaceSize(Size(width, compact ? 760 : 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pages = <String?>[];
    final collections = <Collection>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScope(
          controller: c,
          child: ShellScope(
            compact: compact,
            width: width,
            open: (_, {location}) => pages.add(location),
            openCollection: collections.add,
            openQueue: () {},
            openNowPlaying: () {},
            openLyrics: () {},
            openDownloads: () {},
            importFromYoutube: () {},
            addFiles: () {},
            addFolder: null,
            child: Scaffold(body: page),
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

  testWidgets('Liquid Kawaii shows a Material carousel and lets Home hide its sections', (tester) async {
    await home(tester, carousel: true);
    expect(find.byType(CarouselView), findsOneWidget);
    expect(find.text(tr.speedDial), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip(tr.customizeHome));
    await tester.pumpAndSettle();
    expect(find.text(tr.homeStyle), findsOneWidget);
    final toggle = find.byKey(const ValueKey(HomeSection.quickPicks));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr.done));
    await tester.pumpAndSettle();
    expect(find.byType(CarouselView), findsNothing);
  });

  testWidgets('Liquid Kawaii can scroll its artwork carousel on a narrow phone', (tester) async {
    await home(tester, carousel: true, compact: true);
    final carousel = find.byType(CarouselView);
    final scroll = tester.state<ScrollableState>(
      find.descendant(of: carousel, matching: find.byType(Scrollable)).first,
    );
    final before = scroll.position.pixels;
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    await tester.fling(carousel, const Offset(-260, 0), 1000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(scroll.position.pixels, greaterThan(before));
    expect(find.byTooltip(tr.customizeHome), findsOneWidget);
  });

  testWidgets('Home opens a daily mix with real related songs', (tester) async {
    final opened = await home(tester, withMix: true);
    await tester.tap(find.text(tr.dailyMix));
    await tester.pump();
    expect(opened.collections.single.title, tr.dailyMix);
    expect(opened.collections.single.tracks.map((track) => track.title), ['Fugue', 'Toccata']);
  });

  testWidgets('an artist page shows separate music video, solo, and collaboration shelves', (tester) async {
    final artist = Collection(
      kind: CollectionKind.remoteArtist,
      title: 'Bach',
      subtitle: '',
      tracks: [_file('Solo song', 'Bach'), _file('Joint song', 'Bach, Another artist')],
      artistVideos: [Track.youtube(videoId: 'mv', title: 'An MV', artist: 'Bach')],
    );
    await home(tester, page: CollectionPage(collection: artist));
    expect(find.text(tr.artistMusicVideos), findsOneWidget);
    expect(find.text(tr.artistSoloSongs), findsOneWidget);
    expect(find.text(tr.artistCollaborations), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
