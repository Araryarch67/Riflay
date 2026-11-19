import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starting radio for the current song preserves its source and position even with autoplay off', () async {
    Track song(String id) => Track(id: id, uri: Uri.file('/music/$id.wav'), title: id, artist: 'Artist');
    final current = song('current'), upcoming = song('upcoming'), similar = song('similar');
    SharedPreferences.setMockInitialValues({
      'library.v1': '[]',
      'autoplay.v1': false,
      'discord.enabled': false,
      'playback.queue.v1': jsonEncode({
        'tracks': [current.toJson(), upcoming.toJson()],
        'index': 0,
        'positionMs': 32122,
      }),
    });
    final seeds = <String>[];
    final c = PlayerController(
      radioLookup: (track) async {
        seeds.add(track.id);
        return [current, similar, similar];
      },
    );
    addTearDown(c.dispose);
    await c.load();
    final source = c.player.sequenceState.currentSource;
    final station = await c.startRadio(current);
    expect(station?.kind, CollectionKind.radio);
    expect(station?.tracks.map((track) => track.id), [current.id, similar.id]);
    expect(c.playingFrom, station?.title);
    expect(c.playlists, isEmpty);
    expect(seeds, [current.id]);
    expect(c.autoplay, isFalse);
    expect(c.player.sequenceState.currentSource, same(source));
    expect(c.position, const Duration(milliseconds: 32122));
    expect(c.queue.map((track) => track.id), [current.id, similar.id]);
    expect(c.isAutoplayed(similar), isTrue);
  });

  test('clearing upcoming tracks keeps the current occurrence and persists the retained order', () async {
    Track song(String id) => Track(id: id, uri: Uri.file('/music/$id.wav'), title: id, artist: 'Artist');
    final a = song('a'), b = song('b'), c = song('c');
    const key = 'playback.queue.v1';
    SharedPreferences.setMockInitialValues({
      'library.v1': '[]',
      'discord.enabled': false,
      'autoplay.v1': false,
      key: jsonEncode({
        'tracks': [b.toJson(), a.toJson(), c.toJson(), a.toJson()],
        'ordered': [a.toJson(), a.toJson(), b.toJson(), c.toJson()],
        'index': 1,
        'positionMs': 12345,
        'shuffled': true,
      }),
    });
    final controller = PlayerController();
    addTearDown(controller.dispose);
    await controller.load();
    final current = controller.player.sequenceState.currentSource;
    await controller.clearUpcomingQueue();
    expect(controller.queue.map((t) => t.id), ['b', 'a']);
    expect(controller.upNext, isEmpty);
    expect(controller.player.sequenceState.currentSource, same(current));
    expect(controller.position, const Duration(milliseconds: 12345));
    final prefs = await SharedPreferences.getInstance();
    final snapshot = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
    expect((snapshot['tracks'] as List).map((t) => t['id']), ['b', 'a']);
    expect((snapshot['ordered'] as List).map((t) => t['id']), ['a', 'b']);
    await controller.toggleShuffle();
    expect(controller.queue.map((t) => t.id), ['a', 'b']);
    expect(controller.upNext.map((t) => t.id), ['b']);
    expect(controller.player.sequenceState.currentSource, same(current));
  });

  test('restores a shuffled queue paused at the exact duplicate occurrence and clears it on close', () async {
    final first = Track(id: 'a', uri: Uri.file('/music/a.wav'), title: 'First', artist: 'Artist');
    final second = Track(id: 'b', uri: Uri.file('/music/b.wav'), title: 'Second', artist: 'Artist');
    const key = 'playback.queue.v1';
    SharedPreferences.setMockInitialValues({
      'library.v1': '[]',
      'discord.enabled': false,
      'autoplay.v1': false,
      key: jsonEncode({
        'tracks': [first.toJson(), second.toJson(), first.toJson()],
        'ordered': [first.toJson(), first.toJson(), second.toJson()],
        'index': 2,
        'positionMs': 12345,
        'shuffled': true,
        'from': 'Playlist',
      }),
    });

    final controller = PlayerController();
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.queue.map((track) => track.id), ['a', 'b', 'a']);
    expect(controller.queueIndex, 2);
    expect(controller.position, const Duration(milliseconds: 12345));
    expect(controller.playingFrom, 'Playlist');
    expect(controller.shuffle, isTrue);
    expect(controller.isPlaying, isFalse);
    expect(controller.seekStepSeconds, 5);
    await controller.seekByStep(forward: false);
    expect(controller.position, const Duration(milliseconds: 7345));
    await controller.setSeekStepSeconds(15);
    await controller.seekByStep(forward: false);
    expect(controller.position, Duration.zero);

    await controller.toggleShuffle();
    expect(controller.queue.map((track) => track.id), ['a', 'a', 'b']);
    expect(controller.isPlaying, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('playback.seekStepSeconds'), 15);
    expect((jsonDecode(prefs.getString(key)!) as Map)['shuffled'], isFalse);
    await controller.seek(const Duration(seconds: 12));
    await controller.setSeekStepSeconds(0);
    await controller.seekByStep(forward: false);
    expect(controller.position, const Duration(seconds: 12));
    expect(prefs.getInt('playback.seekStepSeconds'), 0);

    await controller.closePlayer();
    expect(prefs.containsKey(key), isFalse);
  });
}
