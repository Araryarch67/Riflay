import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/connection.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_audio_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('going offline, and pressing play on a streamed song while offline, say why it cannot play', () async {
    JustAudioPlatform.instance = FakeAudioPlatform();
    SharedPreferences.setMockInitialValues({'library.v1': '[]', 'discord.enabled': false, 'autoplay.v1': false});
    final c = PlayerController();
    addTearDown(c.dispose);
    addTearDown(() => Connection.instance.online.value = true);
    await c.load();
    final messages = <String>[];
    final sub = c.errors.listen(messages.add);
    addTearDown(sub.cancel);

    Connection.instance.online.value = false;
    await Future<void>.delayed(Duration.zero);
    expect(messages.single, startsWith("You're offline"));

    c.playList([Track.youtube(videoId: 'abcdefghijk', title: 'Song', artist: 'Artist')], 0).ignore();
    await Future<void>.delayed(Duration.zero);
    expect(messages, hasLength(2));

    Connection.instance.online.value = true;
    await Future<void>.delayed(Duration.zero);
    expect(messages.last, 'Back online.');
  });

  test('no network is offline at once; a Wi-Fi without internet is found by looking; back online after', () async {
    final changes = StreamController<List<ConnectivityResult>>();
    var internet = true;
    var looks = 0;
    final c = Connection(
      changes: changes.stream,
      reach: () async {
        looks++;
        return internet;
      },
    )..start();
    addTearDown(c.dispose);

    changes.add([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);
    expect(c.online.value, isFalse);
    expect(looks, 0, reason: 'the system already said so');

    internet = false;
    changes.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);
    expect(c.online.value, isFalse, reason: 'connected to Wi-Fi, but no internet behind it');

    internet = true;
    expect(await c.check(), isTrue);
    expect(c.online.value, isTrue);
  });
}
