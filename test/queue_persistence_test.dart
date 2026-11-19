import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    await controller.closePlayer();
    expect(prefs.containsKey(key), isFalse);
  });
}
