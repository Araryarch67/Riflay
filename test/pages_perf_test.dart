import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/pages/collection_page.dart';
import 'package:riflay/ui/pages/home_page.dart';
import 'package:riflay/ui/pages/search_page.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/track_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Track> _songs(int n) => [
  for (var i = 0; i < n; i++)
    Track(
      id: 'id$i',
      uri: Uri.parse('file:///m/$i.flac'),
      title: 'Song $i',
      artist: 'Artist ${i % 40}',
      album: 'Album ${i % 100}',
    ),
];

/// Loads a controller whose library is [n] songs.
Future<PlayerController> _controller(WidgetTester tester, int n) async {
  SharedPreferences.setMockInitialValues({
    'library.v1': jsonEncode([for (final t in _songs(n)) t.toJson()]),
  });
  final c = PlayerController();
  await tester.runAsync(c.load);
  addTearDown(() => tester.runAsync(() async => c.dispose()));
  return c;
}

Widget _app(PlayerController c, Widget page, {bool compact = false}) => MaterialApp(
  home: PlayerScope(
    controller: c,
    child: ShellScope(
      compact: compact,
      width: compact ? 400 : 1200,
      open: (_, {location}) {},
      openCollection: (_) {},
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
);

// A notification that is not about the library: what play / pause, a new song or a volume change send.
// ignore: invalid_use_of_protected_member
void _unrelatedNotify(PlayerController c) => c.notifyListeners();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => Directory.systemTemp.path,
  );

  group('local search memo', () {
    testWidgets('answers the same as a plain scan, and only scans again for a new query or library', (tester) async {
      final c = await _controller(tester, 500);
      final memo = LocalSearchMemo();
      final before = LocalSearchMemo.scans;

      for (final q in ['', 'song 4', '  SONG 4 ', 'artist 7', 'album 12', 'nothing like it']) {
        final r = memo.of(c, q, 1);
        final t = q.trim().toLowerCase();
        expect(r.songs.map((s) => s.id), c.search(q).map((s) => s.id), reason: 'songs for "$q"');
        expect(
          r.artists.map((a) => a.title),
          (t.isEmpty ? c.artists : c.artists.where((a) => a.title.toLowerCase().contains(t))).map((a) => a.title),
          reason: 'artists for "$q"',
        );
        expect(
          r.albums.map((a) => a.title),
          (t.isEmpty ? const <Collection>[] : c.albums.where((a) => a.title.toLowerCase().contains(t))).map(
            (a) => a.title,
          ),
          reason: 'albums for "$q"',
        );
      }
      // '  SONG 4 ' is the same query as 'song 4': one scan fewer than the questions asked.
      expect(LocalSearchMemo.scans - before, 5);

      final once = memo.of(c, 'song 4', 1);
      final scans = LocalSearchMemo.scans;
      expect(memo.of(c, 'song 4', 1), same(once));
      expect(memo.of(c, 'Song 4 ', 1), same(once));
      expect(LocalSearchMemo.scans, scans);
      memo.of(c, 'song 4', 2); // the library changed
      expect(LocalSearchMemo.scans, scans + 1);
    });

    testWidgets('8000 songs: a repeat is a lookup, not a scan', (tester) async {
      final c = await _controller(tester, 8000);
      final memo = LocalSearchMemo();
      c.search('song 7'); // first use builds the keys
      final scan = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        c.search('song 7');
      }
      scan.stop();
      memo.of(c, 'song 7', 1);
      final hit = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        memo.of(c, 'song 7', 1);
      }
      hit.stop();
      debugPrint('8000 songs, 20 searches: scan ${scan.elapsedMicroseconds} us, memo ${hit.elapsedMicroseconds} us');
      expect(hit.elapsedMicroseconds, lessThan(scan.elapsedMicroseconds));
    });
  });

  group('SearchPage', () {
    testWidgets('typing finds library songs; unrelated notifications and rebuilds do not scan again', (tester) async {
      final c = await _controller(tester, 300);
      final input = SearchInput();
      addTearDown(input.dispose);
      await tester.pumpWidget(_app(c, SearchPage(input: input)));
      await tester.pump();

      input.controller.text = 'song 29';
      await tester.pump(); // the page picks the text up
      await tester.pump(const Duration(milliseconds: 100)); // past the local debounce
      expect(find.text('In your library'), findsOneWidget);
      expect(find.text('Song 29'), findsOneWidget);

      final scans = LocalSearchMemo.scans;
      for (var i = 0; i < 5; i++) {
        _unrelatedNotify(c);
        await tester.pump();
      }
      expect(LocalSearchMemo.scans, scans, reason: 'play / pause / song changes are not about the library');

      // A resize rebuilds the page, not the library's answer.
      tester.view.physicalSize = const Size(900, 1600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(c, SearchPage(input: input), compact: true));
      await tester.pump();
      expect(LocalSearchMemo.scans, scans);
      expect(find.text('Song 29'), findsOneWidget);
    });

    testWidgets('fast typing scans once after the pause, not per key', (tester) async {
      final c = await _controller(tester, 300);
      final input = SearchInput();
      addTearDown(input.dispose);
      await tester.pumpWidget(_app(c, SearchPage(input: input)));
      await tester.pump();
      final start = LocalSearchMemo.scans;
      for (final text in ['s', 'so', 'son', 'song', 'song ', 'song 1']) {
        input.controller.text = text;
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pump(const Duration(milliseconds: 120));
      // 's' at once, then 'song 1' after the pause.
      expect(LocalSearchMemo.scans - start, 2);
      expect(find.text('Song 1'), findsWidgets);
    });
  });

  group('HomePage', () {
    testWidgets('is not rebuilt by play / pause or song changes, only by the library', (tester) async {
      final c = await _controller(tester, 50);
      await tester.pumpWidget(_app(c, const HomePage()));
      await tester.pump();
      final builds = HomePage.debugBuilds;
      expect(builds, greaterThan(0));

      for (var i = 0; i < 10; i++) {
        _unrelatedNotify(c);
        await tester.pump();
      }
      expect(HomePage.debugBuilds, builds);

      c.createPlaylist('Mix', tracks: _songs(2));
      await tester.pump();
      expect(HomePage.debugBuilds, greaterThan(builds));
    });
  });

  group('TrackRow', () {
    testWidgets('hovering redraws only the hover leaves, not the row', (tester) async {
      final c = await _controller(tester, 3);
      final track = c.library.first;
      await tester.pumpWidget(
        _app(
          c,
          ListView(
            children: [TrackRow(track: track, index: 1, onTap: () {})],
          ),
        ),
      );
      await tester.pump();
      final rows = TrackRow.debugRowBuilds;
      final hovers = TrackRow.debugHoverBuilds;

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(TrackRow)));
      await tester.pump();
      expect(TrackRow.debugRowBuilds, rows, reason: 'the row (cover, texts, menu button) is not rebuilt');
      expect(TrackRow.debugHoverBuilds - hovers, inInclusiveRange(1, 3));

      // Still shows what hover shows: the play icon in place of the number, and the menu button.
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(of: find.byType(PopupMenuButton<void>), matching: find.byType(Opacity)).first,
            )
            .opacity,
        1,
      );

      await mouse.moveTo(const Offset(700, 500));
      await tester.pump();
      await tester.pump();
      expect(TrackRow.debugRowBuilds, rows);
      expect(find.text('1'), findsOneWidget);
    });
  });

  group('CollectionPage', () {
    testWidgets('a long list of equal rows is laid out from one measured row', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await _controller(tester, 2000);
      await tester.pumpWidget(_app(c, CollectionPage(collection: c.allSongs)));
      await tester.pump();
      expect(find.byType(SliverPrototypeExtentList), findsOneWidget);
      expect(find.byType(TrackRow), findsWidgets);
      // Far fewer rows are alive than songs exist.
      expect(find.byType(TrackRow).evaluate().length, lessThan(40));
      expect(tester.takeException(), isNull);
    });
  });
}
