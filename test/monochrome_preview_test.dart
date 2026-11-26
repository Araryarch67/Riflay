import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PlayerController> playing(Track track) async {
    SharedPreferences.setMockInitialValues({
      'library.v1': '[]',
      'autoplay.v1': false,
      'discord.enabled': false,
      'playback.queue.v1': jsonEncode({
        'tracks': [track.toJson()],
        'index': 0,
        'positionMs': 0,
      }),
    });
    final c = PlayerController();
    addTearDown(c.dispose);
    await c.load();
    return c;
  }

  test('a Monochrome song plays only its first minute until it is downloaded', () async {
    final song = Track(
      id: 'monochrome:42',
      uri: Uri.parse('https://example.invalid/42'),
      title: 'Song',
      artist: 'Artist',
    );
    final c = await playing(song);
    expect(c.canQueue(song), isTrue, reason: 'it can be previewed');
    final messages = <String>[];
    final sub = c.errors.listen(messages.add);
    addTearDown(sub.cancel);

    c.endPreviewAt(const Duration(seconds: 59));
    await Future<void>.delayed(Duration.zero);
    expect(messages, isEmpty);

    c.endPreviewAt(PlayerController.previewLength);
    await Future<void>.delayed(Duration.zero);
    expect(messages, hasLength(1));
  });

  test('other songs are not cut off at a minute', () async {
    final c = await playing(Track(id: 'local', uri: Uri.file('/music/local.wav'), title: 'Local', artist: 'Artist'));
    final messages = <String>[];
    final sub = c.errors.listen(messages.add);
    addTearDown(sub.cancel);
    c.endPreviewAt(const Duration(minutes: 3));
    await Future<void>.delayed(Duration.zero);
    expect(messages, isEmpty);
  });
}
