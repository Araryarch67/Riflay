// Real libmpv, local generated audio and the standalone CLI; run only in headless Weston with isolated data.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:riflay/models/track.dart';
import 'package:riflay/platform/cli_server.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/private_files.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wav_util.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true, macOS: true);

  testWidgets('standalone CLI controls real playback and exact queue occurrences', (tester) async {
    const executable = String.fromEnvironment('RIFLAY_CLI_TEST_BINARY');
    expect(executable, isNotEmpty, reason: 'Compile cli/bin/riflay_cli.dart and pass RIFLAY_CLI_TEST_BINARY.');
    final directory = await Directory.systemTemp.createTemp('riflay-cli-audio-');
    final songs = [
      for (final name in ['A', 'B', 'C'])
        Track.fromUri(writeWav('${directory.path}/Artist - $name.wav', 48000 * 30, (_) => (0.0, 0.0)).uri),
    ];
    SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(songs.map((t) => t.toJson()).toList())});
    final player = PlayerController();
    final apply = JustAudioMediaKit.onPlayerCreated!;
    JustAudioMediaKit.onPlayerCreated = (p) async {
      await (p.platform as NativePlayer).setProperty('ao', 'null');
      apply(p);
    };
    await tester.runAsync(() async {
      try {
        await player.load();
        await player.setAutoplay(false);
        await DesktopCli.start(player);
        final endpoint = '${(await PrivateFiles.dir()).path}/cli/endpoint.json';
        final discovery = await Process.run(executable, ['status']);
        expect(discovery.exitCode, 0, reason: '${discovery.stdout}\n${discovery.stderr}');
        Future<dynamic> run(List<String> args) async {
          final process = await Process.run(executable, ['--endpoint', endpoint, '--timeout', '10', ...args]);
          expect(process.exitCode, 0, reason: '${args.join(' ')}: ${process.stdout}\n${process.stderr}');
          final response = jsonDecode(process.stdout as String);
          expect(response['ok'], true);
          return response['result'];
        }

        expect((await run(['search', 'Artist', '--source', 'library']))['total'], 3);
        await run(['play', songs[0].id]);
        expect(player.currentTrack?.id, songs[0].id);
        await run(['queue', 'add', songs[1].id]);
        await run(['queue', 'next', songs[2].id]);
        await run(['queue', 'add', songs[0].id]);
        expect(player.queue.map((t) => t.id), [songs[0].id, songs[2].id, songs[1].id, songs[0].id]);
        await run(['queue', 'play', '3']);
        expect(player.player.currentIndex, 3, reason: 'play the selected occurrence of a duplicated track');
        final queue = await run(['queue']);
        expect((queue['items'] as List).where((dynamic t) => t['current'] == true).length, 1);
        expect(queue['items'][3]['current'], true);
        await run(['queue', 'remove', '0']);
        expect(player.queue.map((t) => t.id), [songs[2].id, songs[1].id, songs[0].id]);
        expect(player.currentTrack?.id, songs[0].id);
        await run(['pause']);
        expect((await run(['status']))['playing'], false);
        await run(['seek', '4.5']);
        expect(player.position.inMilliseconds, closeTo(4500, 200));
        await run(['volume', '25']);
        expect((await run(['status']))['volume'], 25);
        await run(['repeat', 'one']);
        await run(['repeat', 'one']);
        expect(player.loopMode.name, 'one');
        await run(['shuffle', 'on']);
        expect(player.shuffle, true);
        await run(['shuffle', 'off']);
        await run(['play']);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect((await run(['status']))['playing'], true);
        await run(['stop']);
        expect((await run(['queue']))['total'], 0);
      } finally {
        await DesktopCli.close();
        await player.pause();
        player.dispose();
        JustAudioMediaKit.onPlayerCreated = apply;
        await directory.delete(recursive: true);
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}
