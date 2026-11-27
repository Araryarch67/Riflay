import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/karaoke.dart';
import 'package:riflay/ui/widgets/karaoke_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

Float32List _sine(double hz, {int length = Karaoke.window, double level = 0.5}) =>
    Float32List.fromList([for (var i = 0; i < length; i++) level * math.sin(2 * math.pi * hz * i / Karaoke.rate)]);

void main() {
  test('the inverse STFT gives back what the STFT read, away from the edges each run drops', () {
    final left = _sine(440), right = _sine(1234.5, level: 0.3);
    final (l, r) = Karaoke.waves(Karaoke.spectrum(left, right));
    var worst = 0.0;
    for (var i = Karaoke.trim; i < Karaoke.window - Karaoke.trim; i++) {
      worst = math.max(worst, math.max((l[i] - left[i]).abs(), (r[i] - right[i]).abs()));
    }
    expect(worst, lessThan(1e-4));
  });

  test('the spectrum keeps left and right apart, each tone in its own bin', () {
    // Bin 100 of a 4096-point FFT at 44.1 kHz; the right side is silent.
    final spec = Karaoke.spectrum(_sine(100 * Karaoke.rate / Karaoke.nFft), Float32List(Karaoke.window));
    double magnitude(int channel, int bin) {
      const t = Karaoke.frames ~/ 2, plane = Karaoke.bins * Karaoke.frames;
      final re = spec[2 * channel * plane + bin * Karaoke.frames + t];
      final im = spec[(2 * channel + 1) * plane + bin * Karaoke.frames + t];
      return math.sqrt(re * re + im * im);
    }

    expect(magnitude(0, 100), greaterThan(100));
    expect(magnitude(0, 140), lessThan(1e-3));
    expect(magnitude(1, 100), lessThan(1e-3));
  });

  test('a song takes as many runs as its kept middles need', () {
    expect(Karaoke.runsFor(0), 0);
    expect(Karaoke.runsFor(1), 1);
    expect(Karaoke.runsFor(Karaoke.step), 1);
    expect(Karaoke.runsFor(Karaoke.step + 1), 2);
  });

  test('stems are the mix less the vocals, then the vocals, clipped to 16 bits', () {
    final mix = Int16List.fromList([16384, -16384, 32767, 0]);
    final out = Int16List.sublistView(
      Karaoke.stemFrames(mix, Float32List.fromList([0.25, -0.5]), Float32List.fromList([0, 0.25]), 0, 2),
    );
    expect(out, [8192, -16384, 8192, 0, 32767, -8192, -16384, 8192]);
  });

  test('a split runs over every sample, across the runs\' seams, into a 4-channel WAV', () async {
    final dir = await Directory.systemTemp.createTemp('karaoke');
    addTearDown(() => dir.delete(recursive: true));
    // Longer than one run, so a seam falls inside; a stand-in model that calls everything vocals.
    const samples = Karaoke.step + 5000;
    final tone = _sine(330, length: samples);
    final pcm = Int16List(samples * 2);
    for (var i = 0; i < samples; i++) {
      pcm[2 * i] = (tone[i] * 32767).round();
      pcm[2 * i + 1] = -(tone[i] * 32767).round();
    }
    final raw = File('${dir.path}/song.raw')..writeAsBytesSync(pcm.buffer.asUint8List());
    final out = '${dir.path}/song.wav';
    final progress = <double>[];
    await Karaoke.separateFile(raw.path, out, (spec) => spec, progress.add, compensate: 1);
    expect(progress, [0.5, 1.0]);
    final wav = File(out).readAsBytesSync();
    expect(wav.length, 44 + samples * 8);
    final header = ByteData.sublistView(wav, 0, 44);
    expect(header.getUint16(22, Endian.little), 4);
    expect(header.getUint32(24, Endian.little), Karaoke.rate);
    final frames = Int16List.sublistView(wav, 44);
    var worst = 0;
    // Not right at the tone's abrupt end: what that cut adds above the model's top bin (about 17.6 kHz) is dropped,
    // as UVR drops it, over half an STFT window either side.
    for (final i in [10, Karaoke.step - 1, Karaoke.step, Karaoke.step + 1, samples - Karaoke.nFft]) {
      // The music is what the model left: nothing. The vocals: the song itself.
      worst = math.max(worst, frames[4 * i].abs());
      worst = math.max(worst, (frames[4 * i + 2] - pcm[2 * i]).abs());
      worst = math.max(worst, (frames[4 * i + 3] - pcm[2 * i + 1]).abs());
    }
    expect(worst, lessThan(8));
  });

  test("stems are named for the song, its slice of a cue sheet and its file's state", () {
    Track song({Duration? start}) =>
        Track(id: 'a', uri: Uri.file('/music/a.flac'), title: 'A', artist: 'B', start: start);
    final key = Karaoke.keyOf(song(), size: 10, modified: DateTime(2026));
    expect(Karaoke.keyOf(song(), size: 10, modified: DateTime(2026)), key);
    expect(Karaoke.keyOf(song(), size: 11, modified: DateTime(2026)), isNot(key));
    expect(Karaoke.keyOf(song(start: const Duration(minutes: 3)), size: 10, modified: DateTime(2026)), isNot(key));
  });

  test('the engine mixes stems down first, only while Karaoke is on and a 4-channel song plays', () {
    final a = AudioEngine();
    addTearDown(a.dispose);
    a.sourceChannels = 4;
    expect(a.filterChain, isNot(contains('@karaoke')));
    a.karaokeLevels = (vocals: 0.25, music: 0.5);
    expect(a.filterChain, startsWith('@karaoke:lavfi=[pan=stereo|c0=0.500*c0+0.250*c2|c1=0.500*c1+0.250*c3]'));
    a.sourceChannels = 2;
    expect(a.filterChain, isNot(contains('@karaoke')));
  });

  testWidgets('the panel turns Karaoke on and sets the vocals and the music each', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final applied = <KaraokeLevels?>[];
    final k = Karaoke(current: () => null, input: (_) => null, reload: () async {}, applyLevels: applied.add);
    addTearDown(k.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: KaraokePanel(karaoke: k)),
      ),
    );
    expect(find.text('Karaoke'), findsOneWidget);
    // Off: the level waits, and the model's one download is said before it is turned on.
    expect(tester.widget<Slider>(find.byType(Slider).first).onChanged, isNull);
    expect(find.textContaining('MB'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(k.enabled, isTrue);
    expect(applied, [(vocals: 0.0, music: 1.0)]);

    await tester.drag(find.byType(Slider).first, const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(k.vocals, greaterThan(0));
    // The music down to the vocals alone.
    await tester.drag(find.byType(Slider).last, const Offset(-800, 0));
    await tester.pumpAndSettle();
    expect(k.music, 0);
    expect(applied.last, (vocals: k.vocals, music: 0.0));
  });
}
