// Opt-in real libmpv, local HTTP audio and isolated preferences/storage.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/merged_download.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/smart_merge.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Provider implements MergeProvider {
  _Provider(this.uri);
  final Uri uri;
  Completer<void>? hold;

  /// Holds the catalogue's answer: the slow part of a real lookup.
  Completer<void>? searching;
  @override
  String get name => 'Test Monochrome';
  @override
  TrackSource get source => TrackSource.monochrome;
  @override
  bool get on => true;
  @override
  Future<List<Track>> search(String query) async => [
    if (searching != null) ...await searching!.future.then((_) => const <Track>[]),
    Track(id: 'monochrome:1', uri: uri, title: 'Fixture', artist: 'Test', duration: const Duration(seconds: 200)),
  ];
  @override
  Future<String> stream(Track match) async {
    await hold?.future;
    return uri.toString();
  }
}

class _Original extends ja.StreamAudioSource {
  _Original(this.bytes, Track track, [this.type = 'audio/flac']) : super(tag: track);
  final List<int> bytes;
  final String type;
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
      contentType: type,
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
        // The better sound's download reaches the local server (flutter_test answers every request with 400).
        final overrides = HttpOverrides.current;
        HttpOverrides.global = null;
        addTearDown(() => HttpOverrides.global = overrides);
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
        // The address played as it is: this is about the player's handling of the merged source.
        final merge = SmartMerge(providers: [provider], enabled: () => true, downloads: false);
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

  /// A player with Smart merge on a local server that serves [bytes] (a WAV), and the song it plays.
  Future<void> withPlayer(
    WidgetTester tester,
    Future<void> Function(PlayerController c, Track song, void Function(int seconds, {Future<void>? until}) stallAt)
    body,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.runAsync(() async {
      // The better sound's download reaches the local server, and nothing else (flutter_test answers every
      // request with 400; the real YouTube isn't for tests).
      final overrides = HttpOverrides.current;
      HttpOverrides.global = _LocalOnly();
      addTearDown(() => HttpOverrides.global = overrides);
      MediaKit.ensureInitialized(libmpv: File('build/windows/x64/libmpv/libmpv-2.dll').absolute.path);
      JustAudioMediaKit.ensureInitialized(windows: true);
      SharedPreferences.setMockInitialValues({'discord.enabled': false});
      final directory = await Directory.systemTemp.createTemp('riflay-smart-merge-download-');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => directory.path,
      );
      final bytes = _wav(const Duration(seconds: 60));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      int? stall;
      Future<void>? resume;
      server.listen((request) => _serve(request, bytes, stallAt: stall, resume: resume));
      final merge = SmartMerge(
        providers: [_Provider(Uri.parse('http://127.0.0.1:${server.port}/audio.wav'))],
        enabled: () => true,
      );
      final c = PlayerController(smartMerge: merge, youtubeSource: (track) => _Original(bytes, track, 'audio/wav'));
      c.discord.enabled = false;
      final apply = JustAudioMediaKit.onPlayerCreated;
      JustAudioMediaKit.onPlayerCreated = (player) {
        unawaited((player.platform as NativePlayer).setProperty('ao', 'null').then((_) => apply?.call(player)));
      };
      final song = Track.youtube(
        videoId: 'abcdefghijk',
        title: 'Fixture',
        artist: 'Test',
        duration: const Duration(seconds: 200), // as the source answers it
      );
      try {
        await c.setAutoplay(false);
        await body(c, song, (seconds, {until}) {
          stall = 44 + seconds * 8000 * 2;
          resume = until;
        });
      } finally {
        await c.player.dispose();
        c.dispose();
        MergedDownload.forgetAll();
        JustAudioMediaKit.onPlayerCreated = apply;
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    });
  }

  Future<void> until(bool Function() ready, {Duration limit = const Duration(seconds: 15)}) async {
    final watch = Stopwatch()..start();
    while (!ready() && watch.elapsed < limit) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(ready(), isTrue);
  }

  testWidgets(
    'a song plays its better sound from the start, from its download, and a seek lands at once',
    (tester) => withPlayer(tester, (c, song, _) async {
      final opening = Stopwatch()..start();
      await c.playList([song], 0);
      await until(() => c.player.playing && c.position > Duration.zero);
      debugPrint('Opened from the download after ${opening.elapsedMilliseconds} ms');
      final source = c.player.sequenceState.currentSource! as SmartMergeAudioSource;
      expect(source.from?.name, 'Test Monochrome', reason: 'from the start, not from YouTube');
      await until(() => c.position > const Duration(seconds: 2));
      final seeking = Stopwatch()..start();
      await c.seek(const Duration(seconds: 40));
      await until(() => (c.position - const Duration(seconds: 40)).abs() < const Duration(seconds: 1));
      final at = c.position;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(c.position, greaterThan(at), reason: 'it plays on from there');
      debugPrint('Sought after ${seeking.elapsedMilliseconds} ms');
      expect(seeking.elapsed, lessThan(const Duration(seconds: 3)));
    }),
    skip: !Platform.isWindows || !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'a download that stops coming takes the song back to YouTube once it has waited a while',
    (tester) => withPlayer(tester, (c, song, stallAt) async {
      stallAt(15); // the connection dies 15 s into the song
      await c.playList([song], 0);
      await until(() => c.player.playing && c.position > Duration.zero);
      expect((c.player.sequenceState.currentSource! as SmartMergeAudioSource).from, isNotNull);
      var silentFor = 0, longest = 0;
      double? last;
      final listening = Stopwatch()..start();
      while (listening.elapsed < const Duration(seconds: 30)) {
        final at = double.tryParse(await c.audio.debugProperty('time-pos') ?? '');
        final moving = at != null && (last == null || at > last + 0.001);
        if (at != null) last = at;
        silentFor = moving ? 0 : silentFor + 1;
        longest = math.max(longest, silentFor);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final now = c.player.sequenceState.currentSource;
      expect(now is SmartMergeAudioSource && now.from != null, isFalse, reason: 'back on YouTube');
      expect(c.player.playing, isTrue);
      expect(last, greaterThan(18), reason: 'the song went on past where the download stopped');
      // A short lag is waited out; a dead connection is given up on after [PlayerController]'s 8 s.
      expect(longest * 50, lessThan(11000), reason: 'not left waiting for long');
    }),
    skip: !Platform.isWindows || !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'a short lag in the download is waited out: the song stays on its better sound',
    (tester) => withPlayer(tester, (c, song, stallAt) async {
      final lag = Completer<void>();
      stallAt(10, until: lag.future); // the connection pauses 10 s into the song
      await c.playList([song], 0);
      await until(() => c.player.playing && c.position > const Duration(seconds: 2));
      // The song runs into the pause and waits on it a few seconds; then the rest comes.
      await until(() => c.position > const Duration(seconds: 9));
      await Future<void>.delayed(const Duration(seconds: 5));
      lag.complete();
      await until(() => c.position > const Duration(seconds: 16), limit: const Duration(seconds: 20));
      final now = c.player.sequenceState.currentSource;
      expect(now is SmartMergeAudioSource && now.from != null, isTrue, reason: 'still on the better sound');
    }),
    skip: !Platform.isWindows || !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'a download that dies before the song gets going plays it from YouTube within seconds',
    (tester) => withPlayer(tester, (c, song, stallAt) async {
      stallAt(1);
      await c.playList([song], 0);
      final waiting = Stopwatch()..start();
      await until(() {
        final now = c.player.sequenceState.currentSource;
        return c.player.playing && c.position > Duration.zero && !(now is SmartMergeAudioSource && now.from != null);
      }, limit: const Duration(seconds: 20));
      debugPrint('On YouTube after ${waiting.elapsedMilliseconds} ms');
      expect(waiting.elapsed, lessThan(const Duration(seconds: 14)));
    }),
    skip: !Platform.isWindows || !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// [length] of a quiet tone as 16-bit mono WAV at 8 kHz.
List<int> _wav(Duration length) {
  const rate = 8000;
  final samples = rate * length.inMilliseconds ~/ 1000;
  final data = ByteData(44 + samples * 2);
  void text(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    data.setInt16(44 + i * 2, (2000 * math.sin(2 * math.pi * 440 * i / rate)).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

/// Serves [bytes] with byte ranges, as a streaming service does.
/// [stallAt]: past this byte the stream stops sending, as a dropped connection does; until [resume] completes,
/// when there is one.
Future<void> _serve(HttpRequest request, List<int> bytes, {int? stallAt, Future<void>? resume}) async {
  final response = request.response
    ..headers.contentType = ContentType('audio', 'wav')
    ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
  final range = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
  var from = 0, to = bytes.length - 1;
  if (range != null) {
    from = int.parse(range[1]!);
    if (range[2]!.isNotEmpty) to = math.min(int.parse(range[2]!), bytes.length - 1);
    response
      ..statusCode = HttpStatus.partialContent
      ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $from-$to/${bytes.length}');
  }
  response.contentLength = to - from + 1;
  if (request.method == 'HEAD') return response.close();
  if (stallAt != null && to >= stallAt) {
    if (from < stallAt) response.add(bytes.sublist(from, stallAt));
    await response.flush();
    if (resume == null) return; // never closed: the client waits for the rest
    await resume;
    response.add(bytes.sublist(math.max(from, stallAt), to + 1));
    await response.close();
    return;
  }
  response.add(bytes.sublist(from, to + 1));
  await response.close();
}

/// Real connections to the local test server only.
class _LocalOnly extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (uri, proxyHost, proxyPort) {
          if (uri.host != InternetAddress.loopbackIPv4.address) {
            return Future.error(SocketException('Only the local test server: ${uri.host}'));
          }
          return Socket.startConnect(uri.host, uri.port);
        };
}
