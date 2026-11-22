import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/language.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_presets.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/youtube_music_account.dart';
import 'package:riflay/ui/debug_switches.dart';
import 'package:riflay/ui/pages/collection_page.dart';
import 'package:riflay/ui/pages/home_page.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/theme.dart';
import 'package:riflay/ui/widgets/controls.dart';
import 'package:riflay/ui/widgets/page_scaffold.dart';
import 'package:riflay/ui/widgets/shelf.dart';
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

class _HomeAccount extends YoutubeMusicAccount {
  YoutubeMusicLibrary? _snapshot;

  @override
  bool get isSignedIn => _snapshot != null;

  @override
  YoutubeMusicLibrary? get libraryNow => _snapshot;

  @override
  List<RemoteShelf> discovered = [];

  void show(List<RemotePlaylist>? artists) {
    _snapshot = artists == null ? null : YoutubeMusicLibrary(liked: [], playlists: [], recent: [], artists: artists);
    notifyListeners();
  }
}

class _HomePlayer extends PlayerController {
  final _account = _HomeAccount();

  @override
  _HomeAccount get ytMusic => _account;

  final played = <Track>[];

  @override
  Future<void> playList(List<Track> tracks, int index, {String? from, bool shuffled = false}) async {
    played.add(tracks[index]);
  }
}

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

  Future<({List<String?> pages, List<Widget> opened, List<Collection> collections})> home(
    WidgetTester tester, {
    bool carousel = false,
    bool compact = false,
    bool withMix = false,
    double? viewportWidth,
    PlayerController? player,
    Widget page = const HomePage(),
  }) async {
    SharedPreferences.setMockInitialValues({
      'library.v1': jsonEncode([for (final t in _library) t.toJson()]),
      if (withMix) 'recent.v1': [_library[1].id],
    });
    final c = player ?? PlayerController();
    await tester.runAsync(c.load);
    if (carousel) {
      await tester.runAsync(() => PlayerPreset.liquidKawaii.apply(LayoutPrefs.instance));
      addTearDown(() => tester.runAsync(LayoutPrefs.instance.reset));
    }
    addTearDown(() => tester.runAsync(() async => c.dispose()));
    // Tall enough for the Artists shelf to be built.
    final width = viewportWidth ?? (compact ? 356.0 : 1200.0);
    await tester.binding.setSurfaceSize(Size(width, compact ? 760 : 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pages = <String?>[];
    final opened = <Widget>[];
    final collections = <Collection>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScope(
          controller: c,
          child: ShellScope(
            compact: compact,
            width: width,
            open: (page, {location}) {
              opened.add(page);
              pages.add(location);
            },
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
    return (pages: pages, opened: opened, collections: collections);
  }

  /// The card of [name] on the Artists shelf (a song's card names its artist too, as its subtitle).
  Finder artistCard(String name) => find.byWidgetPredicate((w) => w is MediaCard && w.title == name && w.circle);

  testWidgets('Home follows the cover only when the theme or cover mode calls for it', (tester) async {
    final look = Appearance.instance;
    addTearDown(() => tester.runAsync(look.reset));
    await home(tester, withMix: true);
    await tester.runAsync(look.reset);
    await tester.pump();

    Color? gradient() => tester.widget<PageScaffold>(find.byType(PageScaffold)).gradientColor;

    expect(gradient(), isNot(AppColors.elevated));
    await tester.runAsync(() => look.setTheme(ThemeChoice.nord));
    await tester.pump();
    expect(gradient(), AppColors.elevated);

    await tester.runAsync(() => look.setCoverMode(CoverColorMode.app));
    await tester.pump();
    expect(gradient(), isNot(AppColors.elevated));
  });

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

  testWidgets('Home opens followed artists and includes the entire list in Show all', (tester) async {
    final player = _HomePlayer();
    player.ytMusic.show([
      const RemotePlaylist(id: 'UCkobo', browseId: 'UCkobo', title: 'Kobo Kanaeru', count: 0),
      for (var i = 1; i <= 12; i++) RemotePlaylist(id: 'UC$i', browseId: 'UC$i', title: 'Followed $i', count: 0),
    ]);
    final navigation = await home(tester, player: player);
    final shelf = find.byWidgetPredicate((w) => w is Shelf && w.title == tr.artists);
    expect(artistCard('Kobo Kanaeru'), findsOneWidget);
    expect(tester.widget<MediaCard>(artistCard('Kobo Kanaeru')).online, isTrue);
    await tester.tap(artistCard('Followed 1'));
    expect(navigation.pages, ['playlist:UC1']);
    await tester.tap(find.descendant(of: shelf, matching: find.text(tr.showAll)));
    final grid = navigation.opened.last as CardGridPage;
    expect(grid.count, 14);
    expect((grid.card(12) as MediaCard).title, 'Followed 12');
    expect((grid.card(13) as MediaCard).title, 'Bach');

    player.ytMusic.show(null);
    await tester.pump();
    expect(artistCard('Followed 1'), findsNothing);
    expect(tester.widget<MediaCard>(artistCard('Kobo Kanaeru')).online, isFalse);
  });

  testWidgets('Home hides trending shelves and keeps other YouTube Music shelves', (tester) async {
    final player = _HomePlayer();
    player.ytMusic.discovered = [
      RemoteShelf(title: 'Trending now', tracks: [_library[0]]),
      RemoteShelf(title: 'New music', tracks: [_library[1]]),
    ];
    await home(tester, player: player);
    expect(find.text('Trending now'), findsNothing);
    expect(find.text('New music'), findsOneWidget);
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
    expect(find.byTooltip(tr.customizeHome), findsNothing);
    await tester.runAsync(() => LayoutPrefs.instance.setShowHomeToolbar(true));
    await tester.pump();
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
    expect(tester.widget<CarouselView>(carousel).flexWeights, [8, 2, 1]);
    final scroll = tester.state<ScrollableState>(
      find.descendant(of: carousel, matching: find.byType(Scrollable)).first,
    );
    final before = scroll.position.pixels;
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    await tester.fling(carousel, const Offset(-260, 0), 1000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(scroll.position.pixels, greaterThan(before));
    expect(find.byTooltip(tr.customizeHome), findsNothing);
  });

  testWidgets('dragging a Quick Picks card with a mouse scrolls without playing it', (tester) async {
    final player = _HomePlayer();
    await home(tester, carousel: true, viewportWidth: 600, player: player);
    final carousel = find.byType(CarouselView);
    expect(tester.widget<CarouselView>(carousel).flexWeights, [6, 3, 1]);
    final scroll = tester.state<ScrollableState>(
      find.descendant(of: carousel, matching: find.byType(Scrollable)).first,
    );
    final play = find.descendant(of: carousel, matching: find.byType(PlayButton)).first;
    final cardLabels = find.descendant(
      of: carousel,
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && _library.any((track) => widget.properties.label == track.title),
      ),
    );
    final secondTitle = tester.widget<Semantics>(cardLabels.at(1)).properties.label;
    final secondCard = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == secondTitle,
    );
    final previewWidth = tester.getSize(secondCard).width;
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    final start = scroll.position.pixels;
    await tester.fling(play, const Offset(-200, 0), 750, deviceKind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(start));
    expect(tester.getSize(secondCard).width, greaterThan(previewWidth));
    expect(player.played, isEmpty);

    await tester.fling(carousel, const Offset(200, 0), 750, deviceKind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, closeTo(start, 1));
    await tester.tap(play, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(player.played, hasLength(1));
  });

  testWidgets('Home separates headings from cards without extra space below Speed Dial', (tester) async {
    final player = _HomePlayer();
    player.ytMusic.show([]);
    await home(tester, carousel: true, compact: true, withMix: true, player: player);
    final carousel = find.byType(CarouselView);
    final speedDial = find.byWidgetPredicate((w) => w is Shelf && w.title == tr.speedDial);
    final row = find.descendant(of: speedDial, matching: find.byType(ListView));
    expect(
      tester.getTopLeft(carousel).dy - tester.getBottomLeft(find.text(tr.quickPicks)).dy,
      greaterThanOrEqualTo(10),
    );
    expect(tester.getTopLeft(find.text(tr.madeForYou)).dy - tester.getBottomLeft(row).dy, closeTo(16, 1));
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
