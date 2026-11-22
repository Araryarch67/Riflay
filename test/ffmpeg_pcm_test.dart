import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riflay/models/track.dart';
import 'package:riflay/services/audio_analysis.dart';
import 'package:riflay/services/ffmpeg.dart';
import 'package:riflay/services/pcm_decoder.dart';

import 'support/environment.dart';

void main() {
  test('Windows: ffmpeg decodes a file to stereo PCM at its own rate, capped by maxRate', () async {
    if (!Platform.isWindows) return markTestSkipped('ffmpeg PCM is the Windows path');
    if (!hasCommand('ffmpeg', ['-version'])) return markTestSkipped('ffmpeg is not on the PATH here');
    await Ffmpeg.probe();
    expect(FfmpegPcm.supported, isTrue);
    final dir = await Directory.systemTemp.createTemp('riflay-ffpcm-');
    addTearDown(() => dir.delete(recursive: true));
    Future<String> tone(int rate) async {
      final out = p.join(dir.path, 'tone-$rate.flac');
      final r = await Process.run('ffmpeg', [
        '-v', 'error', '-f', 'lavfi', '-i', 'sine=f=440:r=$rate:d=2', '-ac', '1', '-c:a', 'flac', out, //
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return out;
    }

    Future<(int, int)> decode(String path, {int? maxRate}) async {
      final pcm = await FfmpegPcm.decode(path, maxRate: maxRate, bits: 32);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in pcm.data) {
        bytes.add(chunk);
      }
      await pcm.cancel();
      expect(pcm.channels, 2);
      return (pcm.rate, bytes.length);
    }

    // Two seconds of a 44.1 kHz mono file: stereo, 32-bit, its own rate.
    final (rate, length) = await decode(await tone(44100), maxRate: 192000);
    expect(rate, 44100);
    expect(length, closeTo(2 * 44100 * 2 * 4, 44100 * 8 * 0.05));
    // 96 kHz under a 48 kHz cap comes down to 48 kHz.
    final (capped, _) = await decode(await tone(96000), maxRate: 48000);
    expect(capped, 48000);
  });

  test('Windows: a song is measured through ffmpeg, its waveform for the seek bar included', () async {
    if (!Platform.isWindows) return markTestSkipped('ffmpeg PCM is the Windows path');
    if (!hasCommand('ffmpeg', ['-version'])) return markTestSkipped('ffmpeg is not on the PATH here');
    TestWidgetsFlutterBinding.ensureInitialized();
    await Ffmpeg.probe();
    expect(AudioAnalysis.supported, isTrue);
    final dir = await Directory.systemTemp.createTemp('riflay-ffwave-');
    addTearDown(() => dir.delete(recursive: true));
    final song = p.join(dir.path, 'song.flac');
    final r = await Process.run('ffmpeg', [
      '-v', 'error', '-f', 'lavfi', '-i', 'sine=f=220:r=44100:d=6', '-ac', '2', '-c:a', 'flac', song, //
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final report = await AudioAnalysis.of(Track.fromUri(Uri.file(song)), waveform: true);
    expect(report, isNotNull);
    expect(report!.waveform, isNotNull);
    expect(report.waveform, isNotEmpty);
  });
}
