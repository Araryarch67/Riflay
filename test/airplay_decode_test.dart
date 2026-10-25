// AirPlay's own decoding (libmpv into a pipe, ffmpeg where that can't be) against a
// minimal RAOP receiver written here, so it needs no shairport-sync.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:media_kit/media_kit.dart';
import 'package:riflay/services/airplay.dart';
import 'package:riflay/services/pcm_decoder.dart';

/// A speaker that answers RTSP and keeps the RTP audio packets it is sent.
class _Speaker {
  late final ServerSocket _rtsp;
  late final RawDatagramSocket _audio, _control, _timing;
  final packets = <int, Uint8List>{}; // by RTP sequence number

  Future<_Speaker> start() async {
    _rtsp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _audio = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    _control = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0)
      ..listen((_) => _control.receive());
    _timing = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0)
      ..listen((_) => _timing.receive());
    _audio.listen((e) {
      final d = _audio.receive();
      if (d == null || d.data.length <= 12) return;
      packets[ByteData.sublistView(d.data).getUint16(2)] = Uint8List.sublistView(d.data, 12);
    });
    _rtsp.listen((s) {
      final buffer = BytesBuilder();
      s.listen((data) {
        buffer.add(data);
        while (true) {
          final bytes = buffer.toBytes();
          final text = latin1.decode(bytes);
          final end = text.indexOf('\r\n\r\n');
          if (end < 0) return;
          final head = text.substring(0, end);
          final length =
              int.tryParse(RegExp('Content-Length: (\\d+)', caseSensitive: false).firstMatch(head)?[1] ?? '') ?? 0;
          if (bytes.length < end + 4 + length) return;
          buffer
            ..clear()
            ..add(bytes.sublist(end + 4 + length));
          final cseq = RegExp('CSeq: (\\d+)').firstMatch(head)![1];
          final setup = head.startsWith('SETUP');
          s.add(
            ascii.encode(
              'RTSP/1.0 200 OK\r\nCSeq: $cseq\r\nAudio-Latency: 2205\r\n'
              '${setup ? 'Session: 1\r\nTransport: RTP/AVP/UDP;unicast;mode=record;server_port=${_audio.port};'
                        'control_port=${_control.port};timing_port=${_timing.port}\r\n' : ''}\r\n',
            ),
          );
        }
      });
    });
    return this;
  }

  AirPlayDevice get device =>
      AirPlayDevice(name: 'Fake Speaker', host: InternetAddress.loopbackIPv4, port: _rtsp.port, encryptions: {0});

  /// The 16-bit stereo samples received, in order (uncompressed ALAC frames).
  Int16List get samples {
    final out = <int>[];
    for (final seq in packets.keys.toList()..sort()) {
      final p = packets[seq]!;
      // 55 header bits, then 16-bit samples, not byte aligned.
      for (var i = 0; i < 352 * 2; i++) {
        final bit = 55 + i * 16;
        final byte = bit >> 3, shift = bit & 7;
        final v = (p[byte] << 16 | p[byte + 1] << 8 | p[byte + 2]) >> (8 - shift);
        out.add(((v & 0xFFFF) ^ 0x8000) - 0x8000);
      }
    }
    return Int16List.fromList(out);
  }

  Future<void> close() async {
    await _rtsp.close();
    _audio.close();
    _control.close();
    _timing.close();
  }
}

Uint8List _wav(Int16List samples, int rate) {
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
  return data.buffer.asUint8List();
}

class _BytesSource extends StreamAudioSource {
  _BytesSource(this.bytes);
  final Uint8List bytes;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
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

void main() {
  setUpAll(MediaKit.ensureInitialized);

  const rate = 44100;
  final rng = math.Random(5);
  // 2.5 s of noise (never silent, so the start of the audio can be found).
  final song = Int16List.fromList(List.generate(rate * 5, (_) => rng.nextInt(16000) - 8000 + 1));
  late Directory dir;
  late _Speaker speaker;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('airplay-decode');
    speaker = await _Speaker().start();
  });
  tearDown(() async {
    await speaker.close();
    dir.deleteSync(recursive: true);
  });

  /// Plays [source] to its end and returns what the speaker got.
  Future<Int16List> play(AirPlaySource source, Duration duration) async {
    final ended = Completer<void>();
    final errors = <String>[];
    final session = AirPlaySession(speaker.device, onEnded: ended.complete, onError: errors.add, latencyFrames: 4410);
    await session.connect();
    await session.load(source, duration: duration);
    await ended.future.timeout(const Duration(seconds: 20));
    await session.close();
    expect(errors, isEmpty);
    return speaker.samples;
  }

  test('a file is decoded and sent sample for sample', () async {
    if (!MpvPcm.supported) return markTestSkipped('this platform decodes with ffmpeg');
    final path = (File('${dir.path}/s.wav')..writeAsBytesSync(_wav(song, rate))).path;
    final got = await play(AirPlaySource(path: path), const Duration(seconds: 2, milliseconds: 500));
    expect(got.length, closeTo(song.length, 352 * 2 * 2));
    expect(got.sublist(0, song.length - 704), song.sublist(0, song.length - 704));
  });

  test('bytes from a source start where asked', () async {
    if (!MpvPcm.supported) return markTestSkipped('this platform decodes with ffmpeg');
    final got = await play(
      AirPlaySource(source: _BytesSource(_wav(song, rate)), start: const Duration(seconds: 1)),
      const Duration(seconds: 1, milliseconds: 500),
    );
    expect(got.length, closeTo(song.length - rate * 2, 352 * 2 * 2));
    // mpv rounds the cut point by a few frames: find where in the song the speaker's audio begins.
    var shift = 9999;
    for (var d = -300; d <= 300 && shift == 9999; d++) {
      var same = true;
      for (var i = 0; i < 200 && same; i++) {
        same = got[i] == song[rate * 2 + d * 2 + i];
      }
      if (same) shift = d;
    }
    expect(shift, inInclusiveRange(-300, 300), reason: 'starts about 1 s in');
  });

  test('seeking stops the decoder and starts again from the new place', () async {
    if (!MpvPcm.supported) return markTestSkipped('this platform decodes with ffmpeg');
    final path = (File('${dir.path}/s.wav')..writeAsBytesSync(_wav(song, rate))).path;
    final ended = Completer<void>();
    final session = AirPlaySession(speaker.device, onEnded: ended.complete, latencyFrames: 4410);
    await session.connect();
    await session.load(AirPlaySource(path: path), duration: const Duration(seconds: 2, milliseconds: 500));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await session.seek(const Duration(seconds: 2));
    await ended.future.timeout(const Duration(seconds: 20));
    await session.close();
    // 0.5 s before the seek and 0.5 s after it, not the whole 2.5 s.
    expect(speaker.samples.length / 2 / rate, closeTo(1.0, 0.3));
    expect(speaker.samples.where((s) => s != 0).length, greaterThan(rate));
  });
}
