// MpvPcm (libmpv decoding into a pipe, in place of an ffmpeg process) with the
// real libmpv of this platform. Needs nothing on the host: the test songs are
// written here.
//
//   flutter test integration_test/pcm_decoder_test.dart -d <linux|macos|emulator-5554|iPhone…>
//
// On a desktop, run it in a headless session with a throwaway app-data
// directory (see AGENT.md). Windows has no MpvPcm.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riflay/services/pcm_decoder.dart';

/// A 16-bit stereo WAV of noise, and its samples.
({Uint8List bytes, Int16List samples}) _wav(int rate, int frames, {int seed = 1}) {
  final rng = math.Random(seed);
  final samples = Int16List(frames * 2);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = (rng.nextInt(20000) - 10000);
  }
  final data = ByteData(44 + samples.length * 2);
  void tag(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  tag(8, 'WAVEfmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 2, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 4, Endian.little)
    ..setUint16(32, 4, Endian.little)
    ..setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return (bytes: data.buffer.asUint8List(), samples: samples);
}

/// One second of DSD64 stereo (a DSF file).
Uint8List _dsf() {
  const block = 4096;
  const perChannel = 2822400 ~/ 8;
  final blocks = (perChannel + block - 1) ~/ block;
  final dataBytes = blocks * block * 2;
  final d = ByteData(28 + 52 + 12 + dataBytes);
  void tag(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      d.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'DSD ');
  d.setUint64(4, 28, Endian.little);
  d.setUint64(12, d.lengthInBytes, Endian.little);
  tag(28, 'fmt ');
  d.setUint64(32, 52, Endian.little);
  d
    ..setUint32(40, 1, Endian.little) // version
    ..setUint32(44, 0, Endian.little) // DSD raw
    ..setUint32(48, 2, Endian.little) // stereo
    ..setUint32(52, 2, Endian.little)
    ..setUint32(56, 2822400, Endian.little)
    ..setUint32(60, 1, Endian.little) // LSB first
    ..setUint64(64, 2822400, Endian.little)
    ..setUint32(72, block, Endian.little);
  tag(80, 'data');
  d.setUint64(84, 12 + dataBytes, Endian.little);
  final bytes = d.buffer.asUint8List();
  // A mix of bit patterns, so it is not a flat line.
  for (var i = 92; i < bytes.length; i++) {
    bytes[i] = (i * 37) & 0xFF;
  }
  return bytes;
}

class _BytesSource extends StreamAudioSource {
  _BytesSource(this.bytes);
  final Uint8List bytes;
  int requests = 0;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    requests++;
    final from = start ?? 0, to = math.min(end ?? bytes.length, bytes.length);
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: to - from,
      offset: from,
      stream: Stream.value(Uint8List.sublistView(bytes, from, to)),
      contentType: 'audio/wav',
    );
  }
}

/// How many frames [got] begins from [at] (a sample index in [all]): the exact cut point is mpv's to round.
int _offsetOf(Int16List got, Int16List all, int at) {
  for (var d = -200; d <= 200; d++) {
    final from = at + d * 2;
    var same = true;
    for (var i = 0; i < 200 && same; i++) {
      same = got[i] == all[from + i];
    }
    if (same) return d;
  }
  return 9999;
}

Future<Uint8List> _all(PcmStream s) async {
  final b = BytesBuilder(copy: false);
  await for (final c in s.data) {
    b.add(c);
  }
  return b.takeBytes();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true, android: true, macOS: true, iOS: true);

  late Directory dir;
  setUpAll(() async {
    dir = ((await getTemporaryDirectory())..createSync(recursive: true)).createTempSync('om-pcm');
  });
  tearDownAll(() => dir.deleteSync(recursive: true));

  File save(String name, Uint8List bytes) => File('${dir.path}/$name')..writeAsBytesSync(bytes);

  List<String> fifos() => [
    for (final f in Directory(dir.parent.path).listSync())
      if (f.path.contains('riflay-pcm-')) f.path,
  ];

  test('a 16-bit file decodes bit for bit, and the pipe is gone afterwards', () async {
    if (!MpvPcm.supported) return markTestSkipped('MpvPcm is not used on this platform');
    final w = _wav(44100, 44100 * 3);
    final s = await MpvPcm.decode(PcmInput.file(save('a.wav', w.bytes).path), bits: 16);
    expect((s.rate, s.bits, s.channels), (44100, 16, 2));
    final got = await _all(s);
    await s.cancel();
    expect(got.length, w.samples.length * 2);
    expect(got.buffer.asInt16List(got.offsetInBytes, w.samples.length), w.samples);
    expect(fifos(), isEmpty);
  });

  test('32-bit output is the same samples, scaled', () async {
    if (!MpvPcm.supported) return markTestSkipped('MpvPcm is not used on this platform');
    final w = _wav(48000, 48000);
    final s = await MpvPcm.decode(PcmInput.file(save('b.wav', w.bytes).path), bits: 32);
    expect(s.bits, 32);
    final got = await _all(s);
    await s.cancel();
    final ints = got.buffer.asInt32List(got.offsetInBytes, got.length ~/ 4);
    expect(ints.length, w.samples.length);
    var wrong = 0;
    for (var i = 0; i < ints.length; i++) {
      if ((ints[i] >> 16) != w.samples[i]) wrong++;
    }
    expect(wrong, 0);
  });

  test('a start and end cut the song; a given rate resamples', () async {
    if (!MpvPcm.supported) return markTestSkipped('MpvPcm is not used on this platform');
    final w = _wav(44100, 44100 * 5);
    final path = save('c.wav', w.bytes).path;
    final slice = await MpvPcm.decode(
      PcmInput.file(path),
      bits: 16,
      start: const Duration(seconds: 1),
      end: const Duration(seconds: 3),
    );
    final got = await _all(slice);
    await slice.cancel();
    expect(got.length / 4, closeTo(2 * 44100, 2000));
    // It is the right part: the samples at 1 s on.
    final ints = got.buffer.asInt16List(got.offsetInBytes, 2000);
    expect(_offsetOf(ints, w.samples, 44100 * 2), inInclusiveRange(-100, 100), reason: 'starts at 1 s (in frames)');

    final up = await MpvPcm.decode(PcmInput.file(path), bits: 16, rate: 48000);
    expect(up.rate, 48000);
    final resampled = await _all(up);
    await up.cancel();
    expect(resampled.length / 4, closeTo(5 * 48000, 4000));
  });

  test('maxRate brings high rates down and leaves the others alone', () async {
    if (!MpvPcm.supported) return markTestSkipped('MpvPcm is not used on this platform');
    Future<int> rateOf(String name, int rate, int maxRate) async {
      final path = save(name, _wav(rate, rate ~/ 2).bytes).path;
      final s = await MpvPcm.decode(PcmInput.file(path), bits: 32, maxRate: maxRate);
      final seconds = (await _all(s)).length / 8 / s.rate;
      await s.cancel();
      expect(seconds, closeTo(0.5, 0.05), reason: '$name keeps its length');
      return s.rate;
    }

    expect(await rateOf('r384.wav', 384000, 192000), 192000);
    expect(await rateOf('r352.wav', 352800, 176400), 176400);
    expect(await rateOf('r96.wav', 96000, 192000), 96000);
    expect(await rateOf('r44.wav', 44100, 192000), 44100);
    expect(await rateOf('r882.wav', 88200, 176400), 88200);
  });

  test('DSD comes out as PCM at most maxRate', () async {
    if (!MpvPcm.supported) return markTestSkipped('MpvPcm is not used on this platform');
    final s = await MpvPcm.decode(PcmInput.file(save('d.dsf', _dsf()).path), bits: 32, maxRate: 176400);
    expect(s.rate, 176400);
    final got = await _all(s);
    await s.cancel();
    expect(got.length / 8 / s.rate, closeTo(1.0, 0.1));
  });

  test('cancelling in the middle of a song returns, and frees the pipe', () async {
    if (!MpvPcm.supported) return markTestSkipped('MpvPcm is not used on this platform');
    // 40 s at 384 kHz: far more than the pipe holds, so mpv is blocked writing when we stop.
    final path = save('long.wav', _wav(384000, 384000 * 40).bytes).path;
    final s = await MpvPcm.decode(PcmInput.file(path), bits: 16);
    var bytes = 0;
    await for (final c in s.data) {
      bytes += c.length;
      if (bytes > 1 << 20) break; // cancelling the subscription stops the decode
    }
    final watch = Stopwatch()..start();
    await s.cancel().timeout(const Duration(seconds: 15));
    expect(watch.elapsed, lessThan(const Duration(seconds: 12)));
    expect(fifos(), isEmpty);

    // And with the stream never listened to.
    final idle = await MpvPcm.decode(PcmInput.file(path), bits: 16);
    await idle.cancel().timeout(const Duration(seconds: 15));
    expect(fifos(), isEmpty);
  });

  test('a file that is not there fails cleanly', () async {
    if (!MpvPcm.supported) return markTestSkipped('MpvPcm is not used on this platform');
    final watch = Stopwatch()..start();
    await expectLater(
      MpvPcm.decode(PcmInput.file('${dir.path}/missing.flac'), bits: 16, openTimeout: const Duration(seconds: 8)),
      throwsA(anything),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 12)));
    expect(fifos(), isEmpty);
    // Not audio at all.
    await expectLater(
      MpvPcm.decode(
        PcmInput.file(save('junk.wav', Uint8List.fromList(List.filled(5000, 7))).path),
        bits: 16,
        openTimeout: const Duration(seconds: 8),
      ),
      throwsA(anything),
    );
    expect(fifos(), isEmpty);
  });

  test('a byte source goes through the loopback server, from an offset', () async {
    if (!MpvPcm.supported) return markTestSkipped('MpvPcm is not used on this platform');
    final w = _wav(44100, 44100 * 4);
    final source = _BytesSource(w.bytes);
    final s = await MpvPcm.decode(PcmInput.stream(source), bits: 16, start: const Duration(seconds: 2));
    expect(s.rate, 44100);
    final got = await _all(s);
    await s.cancel();
    expect(got.length / 4, closeTo(2 * 44100, 2000));
    final ints = got.buffer.asInt16List(got.offsetInBytes, 2000);
    expect(_offsetOf(ints, w.samples, 44100 * 4), inInclusiveRange(-100, 100), reason: 'starts at 2 s (in frames)');
    expect(source.requests, greaterThan(1), reason: 'ranges, not one whole read');
  });
}
