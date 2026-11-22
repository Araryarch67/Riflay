import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/soundcloud.dart';
import 'package:riflay/services/monochrome.dart';
import 'package:riflay/services/sources/music_sources.dart';
import 'package:riflay/ui/pages/search/soundcloud_results.dart';
import 'package:riflay/ui/pages/search_page.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/controls.dart';
import 'package:riflay/ui/widgets/track_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _track(int id, String title) => {
  'kind': 'track',
  'id': id,
  'title': title,
  'duration': 200000,
  'policy': 'ALLOW',
  'user': {'id': 3, 'username': 'Lofi Girl'},
  'media': {
    'transcodings': [
      {
        'url': 'https://api-v2.soundcloud.com/media/$id/aac_160k/stream/hls',
        'preset': 'aac_160k',
        'format': {'protocol': 'hls', 'mime_type': 'audio/mp4'},
      },
    ],
  },
};

http.Response _answer(http.Request r) => switch (r.url.path) {
  '/search/tracks' => http.Response(
    jsonEncode({
      'collection': [_track(1, 'Night Drive'), _track(2, 'Rain')],
    }),
    200,
  ),
  '/search/users' => http.Response(
    jsonEncode({
      'collection': [
        {'kind': 'user', 'id': 3, 'username': 'Lofi Girl'},
      ],
    }),
    200,
  ),
  '/search/playlists' => http.Response(
    jsonEncode({
      'collection': [
        {
          'kind': 'playlist',
          'id': 9,
          'title': 'Study Mix',
          'user': {'username': 'Lofi Girl'},
        },
      ],
    }),
    200,
  ),
  _ => http.Response('', 404),
};

void main() {
  setUp(() => MusicSources.instance.reset());
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => Directory.systemTemp.path,
  );

  testWidgets('SoundCloud search lists its songs, artists and playlists, each with its mark', (tester) async {
    SharedPreferences.setMockInitialValues({
      'search.source.v1': 'soundcloud',
      'soundcloud.clientId.v1': 'id',
      'sources.soundcloud.v1': true,
    });
    SearchSource.reset();
    addTearDown(SearchSource.reset);
    final c = PlayerController();
    await tester.runAsync(c.load);
    addTearDown(() => tester.runAsync(() async => c.dispose()));
    final prefs = await SharedPreferences.getInstance();
    c.soundcloud = SoundcloudClient(prefs: prefs, client: MockClient((r) async => _answer(r)));
    final input = SearchInput();
    addTearDown(input.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScope(
          controller: c,
          child: ShellScope(
            compact: false,
            width: 1200,
            open: (_, {location}) {},
            openCollection: (_) {},
            openQueue: () {},
            openNowPlaying: () {},
            openLyrics: () {},
            openDownloads: () {},
            importFromYoutube: () {},
            addFiles: () {},
            addFolder: null,
            child: Scaffold(body: SearchPage(input: input)),
          ),
        ),
      ),
    );
    // The saved choice loads: its file checks finish outside the test's clock, a step each round.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    input.controller.text = 'lofi';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // past the debounce
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // results fade in

    expect(find.text('Videos'), findsNothing, reason: 'YouTube-only controls are left out');
    expect(find.text('Night Drive'), findsOneWidget);
    expect(find.text('Rain'), findsOneWidget);
    final marks = tester.widgetList<SourceMark>(
      find.descendant(of: find.byType(TrackRow), matching: find.byType(SourceMark)),
    );
    expect(marks.where((m) => m.source.name == 'soundcloud'), isNotEmpty);
    expect(marks.where((m) => m.source.name == 'youtubeMusic'), isEmpty);
    await tester.scrollUntilVisible(find.text('Study Mix'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Artists on SoundCloud'), findsOneWidget);
    expect(find.text('Playlists on SoundCloud'), findsOneWidget);
  });

  testWidgets('a SoundCloud track is saved to the library and taken out again', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = PlayerController();
    await tester.runAsync(c.load);
    addTearDown(() => tester.runAsync(() async => c.dispose()));
    final track = SoundcloudClient.parseTrack(_track(1, 'Night Drive'))!;
    expect(c.inLibrary(track), isFalse);
    expect(c.isOffline(track), isFalse, reason: 'it streams');
    await tester.runAsync(() => c.saveToLibrary([track, track]));
    expect(c.inLibrary(track), isTrue);
    expect(c.allSongs.tracks.where((t) => t.id == track.id), hasLength(1));
    expect(c.search('night drive').single.soundcloudId, '1');
    await tester.runAsync(() => c.removeTrack(track));
    expect(c.inLibrary(track), isFalse);
  });

  testWidgets('the source switch selects and remembers all three services', (tester) async {
    SharedPreferences.setMockInitialValues({'sources.soundcloud.v1': true, 'sources.monochrome.v1': true});
    SearchSource.reset();
    addTearDown(SearchSource.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: SearchSourceButton())),
      ),
    );
    await tester.pump();
    expect(SearchSource.current.value, SearchSource.youtubeMusic);
    Future<void> select(String name) async {
      await tester.tap(find.byKey(const ValueKey('search-source-menu')));
      await tester.pumpAndSettle();
      final current = find.byKey(ValueKey('search-source-${SearchSource.current.value.name}'));
      expect(find.descendant(of: current, matching: find.byIcon(Icons.check_rounded)), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('search-source-$name')));
      await tester.pumpAndSettle();
    }

    await select('soundcloud');
    expect(SearchSource.current.value, SearchSource.soundcloud);
    await select('monochrome');
    expect(SearchSource.current.value, SearchSource.monochrome);
    expect((await SharedPreferences.getInstance()).getString('search.source.v1'), 'monochrome');
    await select('youtubeMusic');
    expect(SearchSource.current.value, SearchSource.youtubeMusic);
  });

  testWidgets('selecting Monochrome searches its catalog without calling SoundCloud', (tester) async {
    SharedPreferences.setMockInitialValues({
      'search.source.v1': 'youtubeMusic',
      'soundcloud.clientId.v1': 'id',
      'sources.monochrome.v1': true,
      'sources.soundcloud.v1': true,
    });
    SearchSource.reset();
    addTearDown(SearchSource.reset);
    final c = PlayerController();
    await tester.runAsync(c.load);
    addTearDown(() => tester.runAsync(() async => c.dispose()));
    var monochromeQueries = 0;
    String? askedQuery;
    var soundcloudQueries = 0;
    c.monochrome = Monochrome(
      client: MockClient((r) async {
        monochromeQueries++;
        askedQuery = r.url.queryParameters['q'];
        return http.Response(
          jsonEncode({
            'tracks': [
              {
                'trackId': '155102871061270528',
                'title': 'One More Time',
                'artistNames': ['Daft Punk'],
              },
            ],
          }),
          200,
        );
      }),
    );
    c.soundcloud = SoundcloudClient(
      prefs: await SharedPreferences.getInstance(),
      client: MockClient((r) async {
        soundcloudQueries++;
        return _answer(r);
      }),
    );
    final input = SearchInput();
    addTearDown(input.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScope(
          controller: c,
          child: ShellScope(
            compact: false,
            width: 1200,
            open: (_, {location}) {},
            openCollection: (_) {},
            openQueue: () {},
            openNowPlaying: () {},
            openLyrics: () {},
            openDownloads: () {},
            importFromYoutube: () {},
            addFiles: () {},
            addFolder: null,
            child: Scaffold(body: SearchPage(input: input)),
          ),
        ),
      ),
    );
    await tester.pump();
    input.controller.text = ':mc discovery';
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(monochromeQueries, 1);
    expect(askedQuery, 'discovery');
    expect(SearchSource.current.value, SearchSource.monochrome);
    expect(soundcloudQueries, 0);
    expect(find.text('One More Time'), findsOneWidget);
    expect(find.byType(TrackRow), findsOneWidget);
    expect(find.text('Videos'), findsNothing);
    expect(find.text('No YouTube results.'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the menu shows enabled services and falls back when the active one is disabled', (tester) async {
    SharedPreferences.setMockInitialValues({'sources.monochrome.v1': true, 'sources.soundcloud.v1': false});
    SearchSource.reset();
    addTearDown(SearchSource.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: SearchSourceButton())),
      ),
    );
    await tester.pump();
    Future<void> openMenu() async {
      await tester.tap(find.byKey(const ValueKey('search-source-menu')));
      await tester.pumpAndSettle();
    }

    await openMenu();
    expect(find.byKey(const ValueKey('search-source-monochrome')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-source-soundcloud')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('search-source-monochrome')));
    await tester.pumpAndSettle();
    expect(SearchSource.current.value, SearchSource.monochrome);
    await MusicSources.instance.setMonochrome(false);
    await tester.pump();
    expect(SearchSource.current.value, SearchSource.youtubeMusic);
    await openMenu();
    expect(find.byKey(const ValueKey('search-source-youtubeMusic')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-source-monochrome')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('search-source-youtubeMusic')));
    await tester.pumpAndSettle();
    await MusicSources.instance.setSoundcloud(true);
    await tester.pump();
    await openMenu();
    expect(find.byKey(const ValueKey('search-source-soundcloud')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-source-monochrome')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('search-source-youtubeMusic')));
    await tester.pumpAndSettle();
    MusicSources.instance.reset();
    await MusicSources.instance.load();
    expect(MusicSources.instance.soundcloud, isTrue);
    expect(MusicSources.instance.monochrome, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
