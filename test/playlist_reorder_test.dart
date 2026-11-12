import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/pages/collection_page.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track _yt(String id) => Track.youtube(videoId: id, title: id, artist: 'Artist');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => Directory.systemTemp.path,
  );

  test('dragging a playlist song moves it and the order is kept', () async {
    SharedPreferences.setMockInitialValues({});
    final c = PlayerController();
    await c.load();
    final p = c.createPlaylist('Mix', tracks: [_yt('a'), _yt('b'), _yt('c'), _yt('d')]);
    List<String> order(PlayerController x) => x.playlists.single.tracks.map((t) => t.title).toList();

    c.movePlaylistTrack(p.id, 0, 2); // a dropped between c and d
    expect(order(c), ['b', 'c', 'a', 'd']);
    c.movePlaylistTrack(p.id, 3, 0); // d to the top
    expect(order(c), ['d', 'b', 'c', 'a']);
    c.movePlaylistTrack(p.id, 1, 3); // b to the very end
    expect(order(c), ['d', 'c', 'a', 'b']);
    c.movePlaylistTrack(p.id, 1, 1); // dropped where it already is
    expect(order(c), ['d', 'c', 'a', 'b']);
    c.movePlaylistTrack(p.id, 9, 0); // out of range is ignored
    c.movePlaylistTrack('nope', 0, 1);
    expect(order(c), ['d', 'c', 'a', 'b']);

    await Future<void>.delayed(Duration.zero);
    final again = PlayerController();
    await again.load();
    expect(order(again), ['d', 'c', 'a', 'b']);
  });

  testWidgets('a finger drags a playlist song to a new place on a phone', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final c = PlayerController();
    await tester.runAsync(c.load);
    final p = c.createPlaylist('Mix', tracks: [_yt('a'), _yt('b'), _yt('c'), _yt('d')]);
    List<String> order() => c.playlists.single.tracks.map((t) => t.title).toList();
    // The shell's scopes sit above the page's navigator, whose overlay also holds the row being dragged.
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: ShellScope(
          compact: true,
          width: 400,
          open: (_, {location}) {},
          openCollection: (_) {},
          openQueue: () {},
          openNowPlaying: () {},
          openLyrics: () {},
          openDownloads: () {},
          importFromYoutube: ({url}) {},
          addFiles: () {},
          addFolder: null,
          child: MaterialApp(
            home: Scaffold(body: CollectionPage(collection: c.playlistById(p.id)!)),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final handles = find.byIcon(Icons.drag_handle_rounded);
    expect(handles, findsNWidgets(4));
    final gesture = await tester.startGesture(tester.getCenter(handles.first), kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(order(), isNot(['a', 'b', 'c', 'd']));
    expect(order().first, 'b');
    expect(p.id, c.playlists.single.id);
  });
}
