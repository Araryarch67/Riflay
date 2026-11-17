// Real H.264 decoding through the cache. No account, speakers or desktop window.
// flutter test test/video_stream_cache_windows_test.dart --dart-define=RIFLAY_TEST_WINDOWS_MPV=true
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:media_kit/media_kit.dart';
import 'package:riflay/services/video_stream_cache.dart';
import 'package:riflay/services/ytdlp.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real libmpv decodes and seeks cached H.264, then reopens it with zero upstream bytes',
    () async {
      final dir = await Directory.systemTemp.createTemp('riflay-video-cache-mpv-');
      VideoStreamCache? cache;
      Player? player;
      var fetchedBytes = 0;
      try {
        final clip = File('${dir.path}/clip.mp4');
        final generated = await Process.run('ffmpeg', [
          '-hide_banner',
          '-loglevel',
          'error',
          '-f',
          'lavfi',
          '-i',
          'testsrc2=size=160x90:rate=10',
          '-t',
          '8',
          '-c:v',
          'libx264',
          '-pix_fmt',
          'yuv420p',
          '-movflags',
          '+faststart',
          '-an',
          clip.path,
        ]);
        expect(generated.exitCode, 0, reason: generated.stderr.toString());
        final bytes = await clip.readAsBytes();
        http.Client upstream() => MockClient((request) async {
          final range = VideoStreamCache.parseRange(request.headers['Range'], bytes.length)!;
          fetchedBytes += range.$2 - range.$1;
          return http.Response.bytes(
            bytes.sublist(range.$1, range.$2),
            206,
            headers: {'content-range': 'bytes ${range.$1}-${range.$2 - 1}/${bytes.length}'},
          );
        });
        cache = VideoStreamCache(
          directory: () async => Directory('${dir.path}/cache'),
          client: upstream(),
          chunkSize: 4096,
        );
        ResolvedVideo stream(String token) => ResolvedVideo(
          url: Uri.parse('https://video.example/clip?itag=137&lmt=123&token=$token'),
          size: bytes.length,
          height: 90,
          codec: 'avc1',
          formatId: '137',
        );
        MediaKit.ensureInitialized(libmpv: File('build/windows/x64/runner/Release/libmpv-video-2.dll').absolute.path);

        Future<Player> open(Uri url) async {
          final p = Player(configuration: const PlayerConfiguration(muted: true));
          player = p;
          final native = p.platform as NativePlayer;
          await native.setProperty('vo', 'null');
          await native.setProperty('ao', 'null');
          await native.setProperty('aid', 'no');
          await native.setProperty('vid', 'auto');
          await p.open(Media(url.toString()));
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          while (p.state.position < const Duration(milliseconds: 500) && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          expect(p.state.position, greaterThanOrEqualTo(const Duration(milliseconds: 500)));
          expect(await native.getProperty('video-codec'), contains('h264'));
          await p.pause();
          return p;
        }

        final first = await open(await cache.open('mv', stream('first')));
        await first.seek(const Duration(seconds: 4));
        await first.seek(const Duration(seconds: 1));
        expect(fetchedBytes, greaterThan(0));
        final coldBytes = fetchedBytes;
        await first.dispose();
        player = null;
        await cache.close();
        cache = VideoStreamCache(
          directory: () async => Directory('${dir.path}/cache'),
          client: upstream(),
          chunkSize: 4096,
        );
        await open(await cache.open('mv', stream('refreshed')));
        expect(fetchedBytes, coldBytes, reason: 'replaying the cached MV downloads no more original bytes');
        stdout.writeln('MV cache: first play $coldBytes bytes; replay ${fetchedBytes - coldBytes} bytes from upstream');
      } finally {
        await player?.dispose();
        await cache?.close();
        await dir.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows || !const bool.fromEnvironment('RIFLAY_TEST_WINDOWS_MPV'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
