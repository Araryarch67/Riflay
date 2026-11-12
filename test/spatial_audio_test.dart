import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/ui/debug_switches.dart';
import 'package:riflay/ui/widgets/signal_path.dart';
import 'package:shared_preferences/shared_preferences.dart';

SignalPath _path({String codec = 'eac3', String? profile, int channels = 6, String out = 'float'}) => SignalPath(
  codec: codec,
  container: 'mov,mp4,m4a',
  inFormat: 'float',
  inRate: 48000,
  inChannels: channels,
  outFormat: out,
  outRate: 48000,
  outChannels: 2,
  output: 'null',
  device: 'test',
  filters: const [],
  volume: 100,
  leveling: false,
  bitrate: 768000,
  profile: profile,
);

/// The level difference between the ears, in dB, that the 7.1 HRIR's speaker [index] (FFmpeg's 7.1 order: FL FR
/// FC LFE BL BR SL SR) gives a 1 kHz tone.
double _irDifference(int index) {
  final bytes = File(AudioEngine.hrir71Asset).readAsBytesSync();
  final view = ByteData.sublistView(bytes);
  var at = 12;
  while (String.fromCharCodes(bytes.sublist(at, at + 4)) != 'data') {
    at += 8 + view.getUint32(at + 4, Endian.little);
  }
  final size = view.getUint32(at + 4, Endian.little);
  final frames = size ~/ (16 * 4);
  double gain(int channel) {
    var re = 0.0, im = 0.0;
    for (var n = 0; n < frames; n++) {
      final v = view.getFloat32(at + 8 + (n * 16 + channel) * 4, Endian.little);
      re += v * math.cos(2 * math.pi * 1000 * n / 48000);
      im -= v * math.sin(2 * math.pi * 1000 * n / 48000);
    }
    return math.sqrt(re * re + im * im);
  }

  return 20 * math.log(gain(2 * index) / gain(2 * index + 1)) / math.ln10;
}

AudioEngine _speakers() => AudioEngine()
  ..hrirPath = p.absolute(AudioEngine.hrirAsset)
  ..hrir71Path = p.absolute(AudioEngine.hrir71Asset)
  ..virtualSpeakers = true;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Dolby Atmos', () {
    test('E-AC-3 JOC and TrueHD Atmos are told apart from plain Dolby by their profile', () {
      expect(_path(profile: 'Dolby Digital Plus + Dolby Atmos').isAtmos, isTrue);
      expect(_path(codec: 'truehd', profile: 'Dolby TrueHD + Dolby Atmos').isAtmos, isTrue);
      expect(_path().isAtmos, isFalse);
      expect(_path(codec: 'aac', profile: 'LC', channels: 2).isAtmos, isFalse);
      expect(qualityTier(_path(profile: 'Dolby Digital Plus + Dolby Atmos')).$1, 'Dolby Atmos');
    });

    test('a song sent to a receiver shows as passthrough', () {
      expect(_path(out: 'spdif-eac3').isPassthrough, isTrue);
      expect(_path().isPassthrough, isFalse);
    });

    test('passthrough stays off where no receiver can be reached', () {
      final a = AudioEngine()..passthrough = true;
      expect(a.passthroughActive, isTrue);
      expect(AudioEngine.passthroughCodecs.split(','), containsAll(['eac3', 'truehd']));
    });
  });

  group('Virtual speakers room', () {
    tearDown(() => DebugSwitches.stereoVirtualSpeakers = false);

    test('stereo songs keep two speakers; more channels, or the upmix, get the 7.1 room', () {
      final a = _speakers();
      expect(a.virtualRoom, VirtualRoom.stereo);
      expect(a.filterChain, isNot(contains('hrir_kemar_71')));
      a.sourceChannels = 6;
      expect(a.virtualRoom, VirtualRoom.surround);
      expect(a.filterChain, allOf(contains('hrir_kemar_71'), contains('channels=7.1'), isNot(contains('@upmix'))));
      a
        ..sourceChannels = 2
        ..surroundUpmix = true;
      expect(a.virtualRoom, VirtualRoom.upmix);
      expect(a.filterChain, allOf(contains('@upmix:'), contains('hrir_kemar_71')));
      DebugSwitches.stereoVirtualSpeakers = true;
      a.sourceChannels = 6;
      expect(a.virtualRoom, VirtualRoom.stereo, reason: 'the off switch mixes down to two speakers, as before');
    });

    test('settings keep the upmix and passthrough', () async {
      final a = AudioEngine();
      await a.setSurroundUpmix(true);
      await a.setPassthrough(true);
      final b = AudioEngine();
      await b.load();
      expect(b.surroundUpmix, isTrue);
      expect(b.passthrough, isTrue);
    });

    test('through mpv: each channel of a 5.1 song keeps its place, and stereo sounds as loud in both rooms', () async {
      final dir = Directory.systemTemp.createTempSync('spatial');
      addTearDown(() => dir.deleteSync(recursive: true));
      Future<String?> make(String name, String expr, String layout) async {
        final out = '${dir.path}/$name.wav';
        final r = await Process.run('ffmpeg', [
          '-loglevel', 'error', '-f', 'lavfi', '-i', "aevalsrc='$expr':s=48000:d=2:c=$layout", out, //
        ]);
        return r.exitCode == 0 ? out : null;
      }

      const tone = '0.4*sin(2*PI*1000*t)';
      final centre = await make('centre', '$tone|$tone', 'stereo');
      if (centre == null) return markTestSkipped('ffmpeg not available');
      final hardLeft = (await make('left', '$tone|0', 'stereo'))!;
      final front51 = (await make('front51', '$tone|0|0|0|0|0', '5.1(side)'))!;
      final side51 = (await make('side51', '0|0|0|0|$tone|0', '5.1(side)'))!;

      /// Per-channel RMS in dB.
      Future<List<double>> measure(String chain, String input) async {
        final out = '${dir.path}/out.wav';
        final r = await Process.run('mpv', [
          '--no-config', '--ao=pcm', '--ao-pcm-file=$out', '--audio-format=s16', '--af=$chain', input, //
        ]);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        final bytes = File(out).readAsBytesSync();
        final view = ByteData.sublistView(bytes);
        expect(view.getUint16(22, Endian.little), 2, reason: 'headphones get two channels');
        var at = 12;
        while (String.fromCharCodes(bytes.sublist(at, at + 4)) != 'data') {
          at += 8 + view.getUint32(at + 4, Endian.little);
        }
        final pcm = ByteData.sublistView(bytes, at + 8);
        final sum = [0.0, 0.0];
        var n = 0;
        for (var i = 48000 * 2; i + 3 < pcm.lengthInBytes; i += 4, n++) {
          for (final c in [0, 1]) {
            final v = pcm.getInt16(i + 2 * c, Endian.little).toDouble();
            sum[c] += v * v;
          }
        }
        return [for (final s in sum) 20 * math.log(math.sqrt(s / n) / 32768) / math.ln10];
      }

      final stereoRoom = _speakers();
      final upmix = _speakers()..surroundUpmix = true;
      final surround = _speakers()..sourceChannels = 6;

      // What both sides share cancels in the upmix: the voice stays where it was, as loud.
      final c2 = await measure(stereoRoom.filterChain, centre);
      final cUp = await measure(upmix.filterChain, centre);
      for (final ch in [0, 1]) {
        expect(cUp[ch], closeTo(c2[ch], 0.2), reason: 'a centred sound is untouched by the upmix');
      }
      // What is only on one side also reaches the side and back speakers.
      final l2 = await measure(stereoRoom.filterChain, hardLeft);
      final lUp = await measure(upmix.filterChain, hardLeft);
      expect((lUp[1] - l2[1]).abs() + (lUp[0] - l2[0]).abs(), greaterThan(0.5));

      // The front-left channel of a 5.1 song plays as the stereo room's left speaker.
      final f51 = await measure(surround.filterChain, front51);
      final fStereo = await measure(stereoRoom.filterChain, hardLeft);
      for (final ch in [0, 1]) {
        expect(f51[ch], closeTo(fStereo[ch], 0.2), reason: 'both rooms share one head and one gain');
      }
      // The side-left channel is heard through the side speaker's responses (±90°), not mixed into the front: the
      // difference between the ears is what the 7.1 HRIR's side pair gives a 1 kHz tone.
      final s51 = await measure(surround.filterChain, side51);
      expect(s51[0] - s51[1], closeTo(_irDifference(6), 0.3));
      expect(f51[0] - f51[1], closeTo(_irDifference(0), 0.3));
      expect((s51[0] - s51[1] - (f51[0] - f51[1])).abs(), greaterThan(1));
    });
  });
}
