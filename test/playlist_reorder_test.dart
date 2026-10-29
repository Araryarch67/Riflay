import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
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
}
