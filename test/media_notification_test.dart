import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/media_session.dart';
import 'package:riflay/services/media_session/media_session_service.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a moment with no song while a new queue opens keeps the notification and its song', () async {
    final song = Track(id: 'a', uri: Uri.file('/music/a.wav'), title: 'Song', artist: 'Artist');
    SharedPreferences.setMockInitialValues({
      'library.v1': '[]',
      'discord.enabled': false,
      'playback.queue.v1': jsonEncode({
        'tracks': [song.toJson()],
        'index': 0,
        'positionMs': 0,
      }),
    });
    final c = PlayerController();
    addTearDown(c.dispose);
    await c.load();
    final session = MediaSession.test(c, (_) {});
    const info = MediaTrackInfo(id: 'a', title: 'Song', artist: 'Artist');
    session.show(const MediaSessionState(track: info, playing: true, processing: MediaProcessing.ready));
    expect(session.mediaItem.value?.title, 'Song');

    session.show(const MediaSessionState(playing: true, processing: MediaProcessing.loading));
    expect(session.mediaItem.value?.title, 'Song');
    expect(session.playbackState.value.processingState, isNot(AudioProcessingState.idle));

    // Nothing left at all (the queue was cleared, not playing): then it is over.
    session.show(const MediaSessionState());
    expect(session.playbackState.value.processingState, AudioProcessingState.idle);
  });
}
