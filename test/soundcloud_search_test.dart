import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/soundcloud.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => Directory.systemTemp.path,
  );

  testWidgets('SoundCloud search lists its songs, artists and playlists, each with its mark', (tester) async {
    SharedPreferences.setMockInitialValues({'search.source.v1': 'soundcloud', 'soundcloud.clientId.v1': 'id'});
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
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50))); // the saved choice loads
    await tester.pump();

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

  testWidgets('the source switch flips between YouTube Music and SoundCloud, one at a time', (tester) async {
    SharedPreferences.setMockInitialValues({});
    SearchSource.reset();
    addTearDown(SearchSource.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: SearchSourceToggle())),
      ),
    );
    await tester.pump();
    expect(SearchSource.current.value, SearchSource.youtubeMusic);
    await tester.tap(find.byType(SearchSourceToggle));
    await tester.pump();
    expect(SearchSource.current.value, SearchSource.soundcloud);
    await tester.tap(find.byType(SearchSourceToggle));
    await tester.pump();
    expect(SearchSource.current.value, SearchSource.youtubeMusic);
  });
}
