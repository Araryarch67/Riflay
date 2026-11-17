// Opt-in real libmpv (RIFLAY_TEST_WINDOWS_MPV): a song whose better sound is found after Smart merge's patience
// starts from YouTube and moves over to it where it has got to.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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
      contentType: 'audio/wav',
      stream: Stream.value(bytes.sublist(from, to)),
    );
  }
}

class _Slow implements MergeProvider {
  _Slow(this.uri);
  final Uri uri;
  @override
  String get name => 'Slow Monochrome';
  @override
  TrackSource get source => TrackSource.monochrome;
  @override
  bool get on => true;
  @override
  Future<List<Track>> search(String query) async {
    await Future<void>.delayed(const Duration(seconds: 3));
    return [
      Track(
        id: 'monochrome:1',
        uri: uri,
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        duration: const Duration(seconds: 120),
      ),
    ];
  }

  @override
  Future<String> stream(Track match) async => uri.toString();
}

List<int> _wav(int seconds, {double tone = 0.0627}) {
  const rate = 44100;
  final n = rate * seconds;
  final b = ByteData(44 + n * 2);
  void str(int o, String t) {
    for (var i = 0; i < t.length; i++) {
      b.setUint8(o + i, t.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    b.setInt16(44 + i * 2, (3000 * math.sin(i * tone)).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}

void main() {
  const enabled = bool.fromEnvironment('RIFLAY_TEST_WINDOWS_MPV');
  testWidgets(
    'a better sound found late takes the song over on its first play',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.runAsync(() async {
        HttpOverrides.global = null;
        MediaKit.ensureInitialized(libmpv: File('build/windows/x64/libmpv/libmpv-2.dll').absolute.path);
        JustAudioMediaKit.ensureInitialized(windows: true);
        SharedPreferences.setMockInitialValues({'discord.enabled': false});
        final directory = await Directory.systemTemp.createTemp('riflay-first-');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
        final bytes = _wav(120);
        final better = _wav(120, tone: 0.09);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((r) async {
          final m = RegExp(r'bytes=(\d+)-').firstMatch(r.headers.value('range') ?? '');
          final from = m == null ? 0 : int.parse(m[1]!);
          r.response.statusCode = 206;
          r.response.headers.set('content-range', 'bytes $from-${better.length - 1}/${better.length}');
          r.response.contentLength = better.length - from;
          // About 4x the speed it plays.
          for (var at = from; at < better.length; at += 64 << 10) {
            r.response.add(better.sublist(at, math.min(at + (64 << 10), better.length)));
            await r.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 40));
          }
          await r.response.close();
        });
        final provider = _Slow(Uri.parse('http://127.0.0.1:${server.port}/better.flac'));
        final merge = SmartMerge(
          providers: [provider],
          enabled: () => true,
          patience: const Duration(milliseconds: 500),
        );
        final originals = <_Original>[];
        final c = PlayerController(
          smartMerge: merge,
          youtubeSource: (t) {
            final s = _Original(bytes, t);
            originals.add(s);
            return s;
          },
        );
        c.discord.enabled = false;
        final apply = JustAudioMediaKit.onPlayerCreated;
        JustAudioMediaKit.onPlayerCreated = (player) {
          unawaited((player.platform as NativePlayer).setProperty('ao', 'null').then((_) => apply?.call(player)));
        };
        final songs = [
          Track.youtube(
            videoId: 'aaaaaaaaaaa',
            title: 'Blinding Lights',
            artist: 'The Weeknd',
            duration: const Duration(seconds: 120),
          ),
          Track.youtube(
            videoId: 'bbbbbbbbbbb',
            title: 'Idol',
            artist: 'YOASOBI',
            duration: const Duration(seconds: 213),
          ),
          Track.youtube(
            videoId: 'ccccccccccc',
            title: 'Kick Back',
            artist: 'Kenshi Yonezu',
            duration: const Duration(seconds: 193),
          ),
        ];
        await c.setAutoplay(false);
        try {
          await c.playList(songs, 0);
          final watch = Stopwatch()..start();
          SmartMergeAudioSource current() => c.player.sequenceState.currentSource! as SmartMergeAudioSource;
          while (!(c.player.playing && c.position > Duration.zero) && watch.elapsed < const Duration(seconds: 15)) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          expect(current().from, isNull, reason: 'the lookup outlasted the patience: it starts from YouTube');
          expect(originals.first.requests, greaterThan(0));
          while (current().from == null && watch.elapsed < const Duration(seconds: 20)) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          expect(current().from?.name, 'Slow Monochrome');
          final moved = c.position;
          expect(
            moved,
            greaterThan(const Duration(seconds: 2)),
            reason: 'it carries on where it was, not from the top',
          );
          await Future<void>.delayed(const Duration(seconds: 2));
          expect(c.player.playing, isTrue);
          expect(c.position - moved, greaterThan(const Duration(milliseconds: 1500)));
        } finally {
          await c.pause();
          c.dispose();
          await server.close(force: true);
        }
      });
    },
    skip: !Platform.isWindows || !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
