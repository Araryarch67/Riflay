import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_audio_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Play on a restored queue opens the song on screen, even after a seek', () async {
    JustAudioPlatform.instance = FakeAudioPlatform();
    Track song(String id) => Track(id: id, uri: Uri.file('/music/$id.wav'), title: id, artist: 'Artist');
    SharedPreferences.setMockInitialValues({
      'library.v1': '[]',
      'autoplay.v1': false,
      'discord.enabled': false,
      'playback.queue.v1': jsonEncode({
        'tracks': [song('first').toJson(), song('shown').toJson()],
        'index': 1,
        'positionMs': 5000,
      }),
    });
    final c = PlayerController();
    addTearDown(c.dispose);
    await c.load();
    expect(c.currentTrack?.id, 'shown');
    await c.seek(const Duration(seconds: 8));
    unawaited(c.play());
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(FakePlayer.loads.last.initialIndex, 1, reason: 'the song on screen, not the first in the queue');
    expect(c.currentTrack?.id, 'shown');
  });
}
