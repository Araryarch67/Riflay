// Opt-in real libmpv, local HTTP audio and isolated preferences/storage.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/smart_merge.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Provider implements MergeProvider {
  _Provider(this.uri);
  final Uri uri;
  Completer<void>? hold;
  @override
  String get name => 'Test Monochrome';
  @override
  bool get on => true;
  @override
  Future<List<Track>> search(String query) async => [
    Track(id: 'monochrome:1', uri: uri, title: 'Fixture', artist: 'Test', duration: const Duration(seconds: 200)),
  ];
  @override
  Future<String> stream(Track match) async {
    await hold?.future;
    return uri.toString();
  }
}

class _Original extends ja.StreamAudioSource {
  _Original(this.bytes, Track track) : super(tag: track);
  final List<int> bytes;
  int requests = 0;
  @override
  Future<ja.StreamAudioResponse> request([int? start, int? end]) async {
    requests++;
    final from = (start ?? 0).clamp(0, bytes.length);
    final to = (end ?? bytes.length).clamp(from, bytes.length);
    return ja.StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: to - from,
      offset: from,
      contentType: 'audio/flac',
      stream: Stream.value(bytes.sublist(from, to)),
    );
  }
}

void main() {
  const enabled = bool.fromEnvironment('RIFLAY_TEST_WINDOWS_MPV');
  testWidgets(
    'real merged audio survives shuffle and pause; a failed inner URL falls back to original audio',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.runAsync(() async {
        MediaKit.ensureInitialized(libmpv: File('build/windows/x64/libmpv/libmpv-2.dll').absolute.path);
        JustAudioMediaKit.ensureInitialized(windows: true);
        SharedPreferences.setMockInitialValues({'discord.enabled': false});
        final directory = await Directory.systemTemp.createTemp('riflay-smart-merge-');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
        final bytes = await File('test/fixtures/sine.flac').readAsBytes();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var unavailable = false;
        var requests = 0;
        server.listen((request) async {
          requests++;
          if (unavailable) {
            request.response.statusCode = HttpStatus.serviceUnavailable;
          } else {
            request.response.headers.contentType = ContentType('audio', 'flac');
            request.response.contentLength = bytes.length;
            if (request.method != 'HEAD') request.response.add(bytes);
          }
          await request.response.close();
        });
        final provider = _Provider(Uri.parse('http://127.0.0.1:${server.port}/audio.flac'));
        final merge = SmartMerge(providers: [provider], enabled: () => true);
        final originals = <_Original>[];
        final oldDelays = PlayerController.playbackRetryDelays;
        PlayerController.playbackRetryDelays = List.filled(8, const Duration(milliseconds: 100));
        final c = PlayerController(
          smartMerge: merge,
          youtubeSource: (track) {
            final source = _Original(bytes, track);
            originals.add(source);
            return source;
          },
        );
        c.discord.enabled = false;
        final apply = JustAudioMediaKit.onPlayerCreated;
        JustAudioMediaKit.onPlayerCreated = (player) {
          unawaited((player.platform as NativePlayer).setProperty('ao', 'null').then((_) => apply?.call(player)));
        };
        final errors = <String>[];
        final sub = c.errors.listen(errors.add);
        final tracks = [
          for (final id in ['abcdefghijk', 'bcdefghijkl', 'cdefghijklm'])
            Track.youtube(videoId: id, title: 'Fixture', artist: 'Test', duration: const Duration(seconds: 200)),
        ];
        Future<void> until(bool Function() ready) async {
          final watch = Stopwatch()..start();
          while (!ready() && watch.elapsed < const Duration(seconds: 15)) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          expect(ready(), isTrue);
        }

        try {
          await c.setAutoplay(false);
          await c.playList(tracks, 1);
          await until(() => c.player.playing && c.position > Duration.zero);
          final source = c.player.sequenceState.currentSource! as SmartMergeAudioSource;
          expect(source.from?.name, 'Test Monochrome');
          expect(c.currentTrack, same(tracks[1]));
          expect(originals.fold<int>(0, (sum, source) => sum + source.requests), 0);
          await c.pause();
          await c.seek(const Duration(milliseconds: 250));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final position = c.position;
          expect((position - const Duration(milliseconds: 250)).abs(), lessThan(const Duration(milliseconds: 150)));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final before = requests;
          await c.toggleShuffle();
          expect(c.player.sequenceState.currentSource, same(source));
          expect(c.currentTrack, same(tracks[1]));
          expect(c.player.playing, isFalse);
          await c.toggleShuffle();
          expect(c.queue.map((track) => track.videoId), tracks.map((track) => track.videoId));
          await Future<void>.delayed(const Duration(milliseconds: 250));
          expect(c.player.sequenceState.currentSource, same(source));
          expect((c.position - position).abs(), lessThan(const Duration(milliseconds: 200)));
          expect(requests, before, reason: 'Shuffle must keep the same HTTP stream open');
          await c.play();
          await c.toggleShuffle();
          expect(c.player.sequenceState.currentSource, same(source));
          expect(c.player.playing, isTrue);

          unavailable = true;
          merge.clear();
          await c.playList(tracks, 0);
          await until(() => merge.gaveUpOn(tracks[0].videoId!) && c.player.playing && c.position > Duration.zero);
          expect(originals.fold<int>(0, (sum, source) => sum + source.requests), greaterThan(0));
          expect(c.currentTrack?.id, tracks[0].id);
          expect(c.queue.map((track) => track.id), tracks.map((track) => track.id));
          expect(errors, isEmpty);

          // Pausing a slow initial open cancels play intent, even when resolution finishes later.
          unavailable = false;
          await c.pause();
          merge.clear();
          provider.hold = Completer<void>();
          final opening = c.playList(tracks, 0);
          await until(() => c.isBuffering && c.showsPlaying);
          await c.pause();
          provider.hold!.complete();
          await opening;
          await Future<void>.delayed(const Duration(milliseconds: 300));
          expect(c.player.playing, isFalse);
          expect(errors, isEmpty);

          // Native Monochrome tracks bypass the merge proxy. Preserve their
          // connection and seek clock too, including repeated shuffle toggles.
          final direct = [
            for (var i = 0; i < 3; i++)
              Track(
                id: 'monochrome:tracks:track:$i',
                uri: Uri.parse('http://127.0.0.1:${server.port}/$i.flac'),
                title: 'Direct $i',
                artist: 'Test',
              ),
          ];
          await c.playList(direct, 1);
          await until(() => c.player.playing && c.position > Duration.zero);
          await c.pause();
          await c.seek(const Duration(milliseconds: 250));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final directSource = c.player.sequenceState.currentSource;
          final directPosition = c.position;
          final directRequests = requests;
          for (var i = 0; i < 4; i++) {
            await c.toggleShuffle();
            expect(c.player.sequenceState.currentSource, same(directSource));
            expect(c.player.playing, isFalse);
          }
          await Future<void>.delayed(const Duration(milliseconds: 250));
          expect((c.position - directPosition).abs(), lessThan(const Duration(milliseconds: 100)));
          expect(requests, directRequests);
          expect(errors, isEmpty);
        } finally {
          await sub.cancel();
          await c.player.dispose();
          c.dispose();
          JustAudioMediaKit.onPlayerCreated = apply;
          PlayerController.playbackRetryDelays = oldDelays;
          await server.close(force: true);
          await directory.delete(recursive: true);
        }
      });
    },
    skip: !Platform.isWindows || !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
