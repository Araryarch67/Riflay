// Opt in: flutter test --dart-define=RIFLAY_TEST_WINDOWS_MPV=true test/monochrome_windows_playback_test.dart
// Uses the real Windows libmpv with ao=null, isolated temporary files and no app account/storage.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:media_kit/media_kit.dart';
import 'package:riflay/services/monochrome.dart';
import 'package:riflay/services/monochrome_download.dart';

void main() {
  const enabled = bool.fromEnvironment('RIFLAY_TEST_WINDOWS_MPV');
  testWidgets('Windows libmpv plays and seeks FLAC, then plays its downloaded copy offline', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.runAsync(() async {
      final dll = File('build/windows/x64/libmpv/libmpv-2.dll');
      expect(dll.existsSync(), isTrue, reason: 'Run flutter build windows first.');
      MediaKit.ensureInitialized(libmpv: dll.absolute.path);
      final player = Player();
      final errors = <String>[];
      final subscription = player.stream.error.listen(errors.add);
      final directory = await Directory.systemTemp.createTemp('riflay-monochrome-windows-');
      final audio = await File('test/fixtures/sine.flac').readAsBytes();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) async {
        requests++;
        final range = request.headers.value(HttpHeaders.rangeHeader);
        final match = range == null ? null : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
        final start = match == null ? 0 : int.parse(match[1]!);
        final end = match == null || match[2]!.isEmpty
            ? audio.length - 1
            : int.parse(match[2]!).clamp(0, audio.length - 1);
        if (start >= audio.length) {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        } else {
          request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
          request.response.headers.contentType = ContentType('audio', 'flac');
          if (match != null) {
            request.response.statusCode = HttpStatus.partialContent;
            request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${audio.length}');
          }
          request.response.contentLength = end - start + 1;
          if (request.method != 'HEAD') request.response.add(audio.sublist(start, end + 1));
        }
        await request.response.close();
      });
      Future<void> until(bool Function() ready) async {
        final watch = Stopwatch()..start();
        while (!ready() && watch.elapsed < const Duration(seconds: 15)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(ready(), isTrue, reason: 'libmpv state: ${player.state}; errors: $errors');
      }

      try {
        await (player.platform as NativePlayer).setProperty('ao', 'null');
        await player.open(Media('http://127.0.0.1:${server.port}/track.flac'), play: false);
        await until(() => player.state.duration > Duration.zero);
        final duration = player.state.duration;
        expect(requests, greaterThan(0));
        await player.seek(Duration(milliseconds: duration.inMilliseconds ~/ 3));
        await player.play();
        await until(() => player.state.position > Duration.zero);
        await player.stop();

        final source = Monochrome.track({
          'trackId': '155102871061270528',
          'title': 'Windows test',
          'artistNames': ['Riflay'],
        }, native: true)!;
        final local = await MonochromeDownload.save(
          source,
          directory,
          client: MockClient((_) async => http.Response.bytes(audio, 200)),
        );
        await server.close(force: true);
        await player.open(Media(local.path!), play: false);
        await until(() => player.state.duration > Duration.zero);
        expect(player.state.duration, duration);
        await player.play();
        await until(() => player.state.position > Duration.zero);
        expect(errors, isEmpty);
      } finally {
        await subscription.cancel();
        await player.dispose();
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    });
  }, skip: !Platform.isWindows || !enabled);
}
