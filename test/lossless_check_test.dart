import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/audio_analysis_core.dart';
import 'package:riflay/services/download_prefs.dart';
import 'package:riflay/services/ffmpeg.dart';
import 'package:riflay/services/flac_convert.dart';
import 'package:riflay/services/youtube_importer.dart';

Track file(String name) => Track(id: name, uri: Uri.file('/music/$name'), title: name, artist: 'A');

void main() {
  group('bits used', () {
    AudioReport analyse(List<int> samples, {int? stored}) {
      final a = AudioAnalyzer(rate: 44100, channels: 1);
      var mask = 0;
      for (final s in samples) {
        mask |= s;
      }
      a.addBits(mask);
      return a.finish(spectrogram: false).withStoredBits(stored);
    }

    test('a 16-bit file stored as 24-bit is padded', () {
      // 24-bit in s32: the low 8 bits are always zero; padded 16-bit: the low 16.
      final r = analyse([0x12340000, -0x56780000, 0x00010000], stored: 24);
      expect(r.usedBits, 16);
      expect(r.paddedBits, isTrue);
      expect(r.suspicious, isTrue);
    });

    test('a real 24-bit file is not', () {
      final r = analyse([0x12345600, -0x00000100], stored: 24);
      expect(r.usedBits, 24);
      expect(r.paddedBits, isFalse);
    });

    test('a 16-bit file is never padded, and silence says nothing', () {
      expect(analyse([0x12340000], stored: 16).paddedBits, isFalse);
      expect(analyse([0, 0], stored: 24).usedBits, isNull);
      expect(analyse([0x12340000]).paddedBits, isFalse); // lossy: no stored depth
    });

    test('kept between runs; old reports are told apart', () {
      final r = analyse([0x12350000], stored: 24);
      final back = AudioReport.fromJson(r.toJson());
      expect((back.usedBits, back.storedBits, back.paddedBits), (16, 24, true));
      expect(AudioReport.lacksBits(r.toJson()), isFalse);
      expect(AudioReport.lacksBits({'peak': -1.0, 'rate': 44100}), isTrue);
    });
  });

  test('the check looks at PCM lossless files only', () {
    expect(FlacConvert.isLosslessFile(file('a.flac')), isTrue);
    expect(FlacConvert.isLosslessFile(file('a.wav')), isTrue);
    expect(FlacConvert.isLosslessFile(file('a.mp3')), isFalse);
    expect(FlacConvert.isLosslessFile(file('a.dsf')), isFalse);
  });

  group('Convert to FLAC', () {
    test('resamples with SoX and dithers to 16 bits', () {
      final args = YoutubeImporter.flacArgs('in.mp3', 'out.flac', FlacQuality.standard, soxr: true);
      final filter = args[args.indexOf('-af') + 1];
      expect(filter, contains('resampler=soxr'));
      expect(filter, contains('osr=48000'));
      expect(filter, contains('osf=s16'));
      expect(filter, contains('dither_method=triangular_hp'));
      expect(args, isNot(contains('-bits_per_raw_sample')));
    });

    test('24-bit keeps 24 bits, and without SoX uses libswresample at its best', () {
      final args = YoutubeImporter.flacArgs('in.mp3', 'out.flac', FlacQuality.hiRes, soxr: false);
      final filter = args[args.indexOf('-af') + 1];
      expect(filter, isNot(contains('soxr')));
      expect(filter, contains('filter_size=64'));
      expect(filter, contains('osf=s32'));
      expect(args.sublist(args.indexOf('-bits_per_raw_sample')).take(2), ['-bits_per_raw_sample', '24']);
    });

    // Runs the real ffmpeg where it is installed: a 20 kHz tone at 44.1 kHz made into a 48 kHz FLAC keeps its level
    // (mpv's and ffmpeg's default resampler lose about half a decibel there).
    test('keeps the top of the band', () async {
      final dir = await Directory.systemTemp.createTemp('riflay-flac-');
      addTearDown(() => dir.delete(recursive: true));
      final src = '${dir.path}/tone.wav', out = '${dir.path}/tone.flac';
      await Process.run('ffmpeg', [
        '-v',
        'error',
        '-y',
        '-f',
        'lavfi',
        '-i',
        'sine=f=20000:d=2:sample_rate=44100',
        src,
      ]);
      final soxr = await Ffmpeg.hasSoxr('ffmpeg');
      final r = await Process.run('ffmpeg', YoutubeImporter.flacArgs(src, out, FlacQuality.standard, soxr: soxr));
      expect(r.exitCode, 0, reason: '${r.stderr}');
      double rms(String path) {
        final s = Process.runSync('ffmpeg', ['-i', path, '-af', 'astats=measure_perchannel=none', '-f', 'null', '-']);
        return double.parse(RegExp(r'RMS level dB: (-?[\d.]+)').firstMatch('${s.stderr}')!.group(1)!);
      }

      expect((rms(out) - rms(src)).abs(), lessThan(soxr ? 0.05 : 0.2));
    }, skip: Process.runSync('which', ['ffmpeg']).exitCode != 0);
  });
}
