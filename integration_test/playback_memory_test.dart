// Profile/release integration measurement of the real app, mpv playback,
// reactive animation and a real Listen Together LAN connection. Audio goes to
// mpv's clocked null output; no speakers, public broker or YouTube required.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:riflay/main.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/beta_features.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/listen_together/lan.dart';
import 'package:riflay/services/listen_together/listen_together.dart';
import 'package:riflay/services/listen_together/protocol.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/rendering_memory.dart';
import 'package:riflay/ui/player/full_screen_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, double> memory() {
  final out = <String, double>{'rssMiB': ProcessInfo.currentRss / (1 << 20)};
  final file = File('/proc/self/smaps_rollup');
  if (file.existsSync()) {
    final data = file.readAsStringSync();
    double field(String key) => int.parse(RegExp('^$key:\\s+(\\d+) kB', multiLine: true).firstMatch(data)![1]!) / 1024;
    out['pssMiB'] = field('Pss');
    out['privateMiB'] = field('Private_Clean') + field('Private_Dirty');
  }
  return out;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Standalone release builds have no VM service for flutter drive.
  if (const bool.fromEnvironment('MEMORY_EXIT')) {
    binding.allTestsPassed.future.then((passed) => exit(passed ? 0 : 1));
  }
  testWidgets('real playback and Listen Together memory', (tester) async {
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
    await RenderingMemory.configure();
    final dir = Directory.systemTemp.createTempSync('riflay-playback-memory-');
    final audio = File('${dir.path}/Memory - Song.flac');
    final cover = '${dir.path}/Memory - Song.jpg';
    Future<void> ffmpeg(List<String> args) async {
      final result = await Process.run('ffmpeg', ['-loglevel', 'error', '-y', ...args]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    await ffmpeg(['-f', 'lavfi', '-i', 'color=c=0x447799:s=2048x2048', '-frames:v', '1', cover]);
    await ffmpeg(['-f', 'lavfi', '-i', 'anoisesrc=c=pink:a=0.1:d=180:r=48000', '-ac', '2', audio.path]);
    final track = Track.fromUri(audio.uri).copyWith(tagged: true);
    SharedPreferences.setMockInitialValues({
      'source.v1': 'local',
      'library.v1': jsonEncode([track.toJson()]),
      'discord.enabled': false,
      'autoplay.v1': false,
      'youtube.visitor.v1': '${DateTime.now().millisecondsSinceEpoch} memory-fixture',
    });
    await Appearance.instance.load();
    await LayoutPrefs.instance.load();
    await BetaFeatures.instance.reload();
    await BetaFeatures.instance.set(BetaFeature.audioVisualizer, true);
    await LayoutPrefs.instance.setMotion(Motion.full);
    await LayoutPrefs.instance.setVisualizer(true);
    await LayoutPrefs.instance.setVisualizerStyle(VisualizerStyle.pulse);
    await Appearance.instance.setNowPlaying(NowPlayingBackground.aurora);
    await Appearance.instance.setReactiveBackground(true);
    final controller = PlayerController();
    final original = JustAudioMediaKit.onPlayerCreated!;
    JustAudioMediaKit.onPlayerCreated = (player) {
      original(player);
      final ready = (player.platform as NativePlayer).setProperty('ao', 'null');
      (player.platform as NativePlayer).onLoadHooks.add(() => ready);
    };
    await controller.load();
    await controller.setAutoplay(false);
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 1.6;
    await tester.pumpWidget(RiflayApp(controller: controller));
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final results = <String, Map<String, double>>{};
    Future<void> sample(String label, int seconds) async {
      var peak = ProcessInfo.currentRss;
      final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (ProcessInfo.currentRss > peak) peak = ProcessInfo.currentRss;
      });
      try {
        await Future<void>.delayed(Duration(seconds: seconds));
        results[label] = {...memory(), 'samplePeakRssMiB': peak / (1 << 20)};
        debugPrint('PLAYBACK_MEMORY $label ${jsonEncode(results[label])}');
      } finally {
        timer.cancel();
      }
    }

    final transport = LanHostTransport(name: 'Memory host');
    final listen = ListenTogether(controller, hostTransport: (_, _) => transport);
    WebSocket? guest;
    var states = 0;
    try {
      await sample('idle', 3);
      await controller.playList([track], 0);
      await sample('playing', 10);
      expect(controller.player.position, greaterThan(const Duration(seconds: 3)));
      fullScreenPlayer.value = true;
      await sample('playing_animated', 10);
      expect(controller.audio.visualizerActive, isTrue);
      expect(controller.audio.visualizerLevels.value.any((v) => v > 0), isTrue);
      await listen.host(mode: ListenMode.wifi, name: 'Memory host');
      guest = await WebSocket.connect('ws://127.0.0.1:${transport.port}/listen/${transport.code}');
      guest.listen((text) {
        if (ListenMessage.decode(text as String) is PlaybackState) states++;
      });
      guest.add(const Hello(name: 'Memory guest', guestId: 'memoryguest1').encode());
      await sample('playing_animated_listen', 30);
      expect(listen.listeners, contains('Memory guest'));
      expect(states, greaterThan(3), reason: 'real periodic state messages must reach the guest');
      for (var i = 0; i < 15; i++) {
        await controller.seek(Duration(seconds: 10 + i * 2));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      await sample('after_seeks', 10);
      await listen.leave();
      await controller.pause();
      await sample('paused_session_closed', 5);
      final out = File(
        'build/perf/playback-memory-${Platform.operatingSystem}-${kReleaseMode ? 'release' : 'profile'}.json',
      );
      out.parent.createSync(recursive: true);
      out.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'mode': kReleaseMode
              ? 'release'
              : kProfileMode
              ? 'profile'
              : 'debug',
          'audio': 'local 48 kHz stereo FLAC, mpv null output',
          'session': 'LAN host + loopback WebSocket guest; no guest decoder',
          ...results,
        }),
      );
    } finally {
      await guest?.close();
      await listen.leave();
      listen.dispose();
      fullScreenPlayer.value = false;
      await controller.player.stop();
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      tester.view.reset();
      dir.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
