import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/ui/pages/collection_page.dart';
import 'package:riflay/ui/pages/library_page.dart';
import 'package:riflay/ui/pages/youtube_music_page.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/track_selection.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Track> _songs(int n) => [
  for (var i = 0; i < n; i++)
    Track(id: 'id$i', uri: Uri.parse('file:///m/$i.flac'), title: 'Song $i', artist: 'Artist', album: 'Album'),
];

Future<PlayerController> _controller(WidgetTester tester, int n) async {
  SharedPreferences.setMockInitialValues({
    'library.v1': jsonEncode([for (final t in _songs(n)) t.toJson()]),
    'discord.enabled': false,
  });
  final c = PlayerController();
  await tester.runAsync(c.load);
  addTearDown(() => tester.runAsync(() async => c.dispose()));
  return c;
}

Widget _app(PlayerController c, Widget page) => MaterialApp(
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
      child: Scaffold(body: page),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => Directory.systemTemp.path,
  );

  test('picked songs come back in page order, and drop out when gone from it', () {
    final songs = _songs(4);
    final s = TrackSelection()
      ..toggle(songs[3])
      ..toggle(songs[1]);
    expect(s.of(songs).map((t) => t.id), ['id1', 'id3']);
    expect(s.of(songs.take(2).toList()).map((t) => t.id), ['id1']);
    s.toggle(songs[1]);
    expect(s.of(songs).map((t) => t.id), ['id3']);
    s.clear();
    expect(s.active, isFalse);
  });

  testWidgets('playlist removes several selected songs and optional Undo restores their order', (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await _controller(tester, 5);
    final prefs = LayoutPrefs.instance;
    await tester.runAsync(() async {
      await prefs.reset();
      await prefs.setExtraFeature(ExtraFeature.undoRemoval, true);
    });
    addTearDown(prefs.reset);
    final mix = c.createPlaylist('Mix', tracks: c.library);
    final ordered = mix.tracks.map((t) => t.id).toList();
    await tester.pumpWidget(_app(c, CollectionPage(collection: c.playlistCollection(mix))));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Song 1'));
    await tester.pump();
    await tester.tap(find.text('Song 3'));
    await tester.pump();
    await tester.tap(find.byTooltip('Remove from this playlist'));
    await tester.pumpAndSettle();
    expect(c.playlistById(mix.id)!.tracks.map((t) => t.id), ordered.where((id) => id != 'id1' && id != 'id3'));
    expect(c.library.length, 5);
    expect(find.text('2 selected'), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(c.playlistById(mix.id)!.tracks.map((t) => t.id), ordered);
  });

  testWidgets('playlist search is opt-in and filters the displayed songs', (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await _controller(tester, 5);
    final prefs = LayoutPrefs.instance;
    await tester.runAsync(prefs.reset);
    addTearDown(prefs.reset);
    final mix = c.createPlaylist('Mix', tracks: c.library);
    await tester.pumpWidget(_app(c, CollectionPage(collection: c.playlistCollection(mix))));
    await tester.pumpAndSettle();
    expect(find.byType(SearchBar), findsNothing);
    expect(find.byTooltip('Search within playlists'), findsNothing);
    await tester.runAsync(() => prefs.setExtraFeature(ExtraFeature.playlistSearch, true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search within playlists'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(SearchBar), matching: find.byType(EditableText)), 'Song 3');
    await tester.pumpAndSettle();
    expect(find.text('Song 3', findRichText: false), findsNWidgets(2), reason: 'one result and one search field');
    expect(find.text('Song 0'), findsNothing);
    expect(find.byIcon(Icons.drag_handle_rounded), findsNothing);
    expect(c.playlistById(mix.id)!.tracks.length, 5);
  });
  for (final fromLibrary in [true, false]) {
    testWidgets('${fromLibrary ? 'Library' : 'All Songs'} adds all songs to a playlist without selecting rows', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await _controller(tester, 4);
      final mix = c.createPlaylist('Bulk mix');
      final page = fromLibrary ? const LibraryList() : CollectionPage(collection: c.allSongs);
      await tester.pumpWidget(_app(c, page));
      await tester.pump();
      expect(find.textContaining('selected'), findsNothing);
      await tester.tap(find.byTooltip('Add all songs to playlist'));
      await tester.pumpAndSettle();
      final dialog = find.byType(Dialog);
      await tester.tap(find.descendant(of: dialog, matching: find.text('Bulk mix')));
      await tester.pumpAndSettle();
      expect(c.playlistById(mix.id)!.tracks.map((t) => t.id), c.allSongs.tracks.map((t) => t.id));
    });
  }
  testWidgets('Liked Music adds only its own tracks to a playlist', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await _controller(tester, 4);
    final mix = c.createPlaylist('Liked mix');
    final liked = likedCollection(c.library.skip(1).take(2).toList());
    await tester.pumpWidget(_app(c, CollectionPage(collection: liked)));
    await tester.pump();
    await tester.tap(find.byTooltip('Add all songs to playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Liked mix'));
    await tester.pumpAndSettle();
    expect(c.playlistById(mix.id)!.tracks.map((t) => t.id), liked.tracks.map((t) => t.id));
  });
  testWidgets('hold a song to pick it, tap more, then add them to a playlist together', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await _controller(tester, 5);
    final mix = c.createPlaylist('Mix');
    await tester.pumpWidget(_app(c, CollectionPage(collection: c.allSongs)));
    await tester.pump();
    expect(find.byType(TrackSelectionBar), findsOneWidget);
    expect(find.textContaining('selected'), findsNothing);

    await tester.longPress(find.text('Song 0'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);

    // While picking, a tap picks instead of playing.
    await tester.tap(find.text('Song 2'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    expect(c.currentTrack, isNull);

    await tester.tap(find.byTooltip('Add to playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mix'));
    await tester.pumpAndSettle();
    expect(c.playlistById(mix.id)!.tracks.map((t) => t.id), ['id0', 'id2']);
    expect(find.text('Added 2 songs to Mix'), findsOneWidget);
    expect(find.textContaining('selected'), findsNothing, reason: 'done picking');

    await tester.pump(const Duration(seconds: 5)); // the note goes away
    await tester.pumpAndSettle();

    // Select all, then let go of it.
    await tester.longPress(find.text('Song 1'));
    await tester.pump();
    await tester.tap(find.byTooltip('Select all'));
    await tester.pump();
    expect(find.text('5 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel selection'));
    await tester.pump();
    expect(find.textContaining('selected'), findsNothing);
    await tester.tap(find.text('Song 1'));
    await tester.pump();
    expect(c.currentTrack, isNotNull, reason: 'a tap plays again');
    // The song never opens here: stop waiting for it, so its 45 second limit isn't left running.
    c.pause().ignore();
  });
}
