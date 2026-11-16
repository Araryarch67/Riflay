// Opt-in real libmpv: a YouTube Music song plays from the same recording's lossless file in the library.
// Run with: flutter test test/smart_merge_local_windows_test.dart --dart-define=RIFLAY_TEST_WINDOWS_MPV=true
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:path/path.dart' as p;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/smart_merge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The song's own YouTube stream: counts what is asked of it.
class _YouTube extends ja.StreamAudioSource {
  _YouTube(this.bytes, Track track) : super(tag: track);
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

  /// A library song as Riflay keeps it: a SpotiFLAC (Tidal) download of "Kyapi", at [file].
  Map<String, Object?> kyapi(File file) => {
    'id': file.uri.toString(),
    'uri': file.uri.toString(),
    'title': 'Kyapi',
    'artist': 'Houshou Marine',
    'album': 'Kyapi',
    'durationMs': 200200,
    'tagged': true,
    'sourceUrl': 'spotiflac://tidal-web/tidal:550520501',
    'audioQuality': 'FLAC · 16-bit / 44.1 kHz',
    'extensionData': {'isrc': 'JPA3C2600219', 'duration_ms': 200000, 'name': 'Kyapi', 'artists': 'Houshou Marine'},
  };

  Future<void> withPlayer(
    WidgetTester tester,
    Future<void> Function(PlayerController c, SmartMerge merge, List<_YouTube> youtube, File flac) body,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.runAsync(() async {
      MediaKit.ensureInitialized(libmpv: File('build/windows/x64/libmpv/libmpv-2.dll').absolute.path);
      JustAudioMediaKit.ensureInitialized(windows: true);
      final directory = await Directory.systemTemp.createTemp('riflay-smart-merge-local-');
      final flac = await File('test/fixtures/sine.flac').copy(p.join(directory.path, 'Houshou Marine - Kyapi.flac'));
      SharedPreferences.setMockInitialValues({
        'discord.enabled': false,
        'library.v1': jsonEncode([kyapi(flac)]),
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => directory.path,
      );
      final bytes = await File('test/fixtures/sine.flac').readAsBytes();
      final youtube = <_YouTube>[];
      // No streaming source: only the library's file can stand in for YouTube.
      final merge = SmartMerge(providers: const [], enabled: () => true, downloads: false);
      final c = PlayerController(
        smartMerge: merge,
        youtubeSource: (track) {
          final source = _YouTube(bytes, track);
          youtube.add(source);
          return source;
        },
      );
      c.discord.enabled = false;
      final apply = JustAudioMediaKit.onPlayerCreated;
      JustAudioMediaKit.onPlayerCreated = (player) {
        unawaited((player.platform as NativePlayer).setProperty('ao', 'null').then((_) => apply?.call(player)));
      };
      try {
        await c.load();
        expect(c.library.map((t) => t.title), ['Kyapi'], reason: 'the library holds the FLAC');
        await c.setAutoplay(false);
        await body(c, merge, youtube, flac);
      } finally {
        await c.player.dispose();
        c.dispose();
        JustAudioMediaKit.onPlayerCreated = apply;
        await directory.delete(recursive: true);
      }
    });
  }

  Future<void> until(bool Function() ready) async {
    final watch = Stopwatch()..start();
    while (!ready() && watch.elapsed < const Duration(seconds: 15)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(ready(), isTrue);
  }

  testWidgets(
    '"きゃぴ - Kyapi" from YouTube Music plays the library\'s FLAC of "Kyapi"',
    (tester) => withPlayer(tester, (c, merge, youtube, flac) async {
      final song = Track.youtube(
        videoId: 'kyapiVideo1',
        title: 'きゃぴ - Kyapi',
        artist: 'Houshou Marine',
        duration: const Duration(seconds: 199),
      );
      await c.playList([song], 0);
      await until(() => c.player.playing && c.position > Duration.zero);
      final source = c.player.sequenceState.currentSource!;
      expect(source is SmartMergeAudioSource, isFalse, reason: 'not the streaming merge');
      expect(source is ja.UriAudioSource ? File.fromUri(source.uri).path : null, flac.path, reason: 'the FLAC plays');
      expect(c.currentTrack?.videoId, 'kyapiVideo1', reason: 'the song stays the YouTube Music one');
      expect(merge.soundFrom('kyapiVideo1')?.source, TrackSource.device, reason: 'its badge shows the library file');
      expect(youtube.fold<int>(0, (sum, s) => sum + s.requests), 0, reason: 'YouTube is never asked');
    }),
    skip: !Platform.isWindows || !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'another song by the same artist still plays from YouTube',
    (tester) => withPlayer(tester, (c, merge, youtube, flac) async {
      final song = Track.youtube(
        videoId: 'ahoyVideo01',
        title: 'Ahoy!! 我ら宝鐘海賊団☆',
        artist: 'Houshou Marine',
        duration: const Duration(seconds: 200),
      );
      await c.playList([song], 0);
      await until(() => c.player.playing && c.position > Duration.zero);
      expect(merge.soundFrom('ahoyVideo01'), isNull);
      expect(youtube.fold<int>(0, (sum, s) => sum + s.requests), greaterThan(0), reason: 'played from YouTube');
    }),
    skip: !Platform.isWindows || !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
