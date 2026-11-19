import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/sources/music_sources.dart';
import 'package:riflay/services/youtube_audio_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('RIFLAY_TEST_LIVE_RADIO');
  const playNext = bool.fromEnvironment('RIFLAY_TEST_LIVE_RADIO_PLAYBACK');

  test(
    'YouTube Music radio fills a real libmpv queue without restarting the current track',
    () async {
      final previousHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final directory = await Directory.systemTemp.createTemp('riflay-live-radio-');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
      SharedPreferences.setMockInitialValues({'discord.enabled': false, 'sources.smartMerge.v1': false});
      await MusicSources.instance.load();
      MediaKit.ensureInitialized(
        libmpv: File(
          const String.fromEnvironment('RIFLAY_TEST_MPV_DLL', defaultValue: 'build/windows/x64/libmpv/libmpv-2.dll'),
        ).absolute.path,
      );
      JustAudioMediaKit.ensureInitialized(windows: true);
      final player = PlayerController();
      final apply = JustAudioMediaKit.onPlayerCreated;
      JustAudioMediaKit.onPlayerCreated = (engine) {
        final native = engine.platform as NativePlayer;
        unawaited(native.setProperty('ao', 'null').then((_) => apply?.call(engine)));
      };
      final errors = <String>[];
      final notifications = player.errors.listen(errors.add);

      try {
        final file = File('${directory.path}/radio-seed.wav');
        await file.writeAsBytes(_silentWave());
        final seed = Track(
          id: file.uri.toString(),
          uri: file.uri,
          title: 'Shelter',
          artist: 'Porter Robinson, Madeon',
          downloadYoutubeId: 'HQnUHyG79M4',
        );
        await player.setAutoplay(false);
        await player.playList([seed], 0);
        await player.seek(const Duration(milliseconds: 1800));
        final current = player.player.sequenceState.currentSource;
        await player.startRadio(seed);

        expect(player.player.sequenceState.currentSource, same(current));
        expect(player.position, greaterThanOrEqualTo(const Duration(milliseconds: 1700)));
        expect(player.upNext.length, greaterThanOrEqualTo(3), reason: errors.join(', '));
        expect(player.upNext.every((song) => song.isRemote && song.youtubeId != seed.youtubeId), isTrue);
        stdout.writeln(
          'Live YouTube Music returned ${player.upNext.length} radio tracks: '
          '${player.upNext.take(3).map((song) => song.title).join(', ')}',
        );
        if (playNext) {
          final recommended = player.upNext.take(5).map((track) => track.id).toSet();
          await player.next().timeout(const Duration(seconds: 40));
          final deadline = DateTime.now().add(const Duration(seconds: 30));
          bool playingRecommendation() =>
              recommended.contains(player.currentTrack?.id) && player.isPlaying && player.position > Duration.zero;
          while (!playingRecommendation() && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(playingRecommendation(), isTrue, reason: errors.join(', '));
          stdout.writeln('Playing radio recommendation: ${player.currentTrack!.title}');
        }
      } finally {
        await notifications.cancel();
        await player.player.dispose();
        await YoutubeAudioSource.clearCache();
        player.dispose();
        messenger.setMockMethodCallHandler(paths, null);
        HttpOverrides.global = previousHttpOverrides;
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: !enabled || !Platform.isWindows ? 'requires Windows libmpv and RIFLAY_TEST_LIVE_RADIO=true' : false,
  );
}

Uint8List _silentWave() {
  const audioLength = 8000 * 2 * 60;
  final bytes = Uint8List(44 + audioLength);
  final header = ByteData.sublistView(bytes);
  bytes.setAll(0, 'RIFF'.codeUnits);
  header.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setAll(8, 'WAVEfmt '.codeUnits);
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 8000, Endian.little);
  header.setUint32(28, 16000, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  bytes.setAll(36, 'data'.codeUnits);
  header.setUint32(40, audioLength, Endian.little);
  return bytes;
}
