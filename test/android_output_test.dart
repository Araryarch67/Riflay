import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/android_output.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/widgets/stats_for_nerds.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StatsAudio extends AudioEngine {
  int reads = 0;
  @override
  Future<SignalPath?> signalPath() async {
    reads++;
    return const SignalPath(
      codec: 'flac',
      container: 'flac',
      inFormat: 's32',
      inRate: 48000,
      inChannels: 2,
      outFormat: 'float',
      outRate: 48000,
      outChannels: 2,
      output: 'null',
      device: 'test',
      filters: [],
      volume: 100,
      leveling: false,
      bitrate: 800000,
    );
  }

  @override
  Future<NerdStats> nerdStats() async => const NerdStats(buffered: 2);
}

class _StatsPlayer extends PlayerController {
  final stats = _StatsAudio();
  @override
  AudioEngine get audio => stats;
  @override
  Track get currentTrack => Track.youtube(videoId: 'teststats', title: 'Test song', artist: 'Test artist');

  @override
  void dispose() {
    super.audio.dispose();
    super.dispose();
  }
}

void main() {
  test('reads what the phone reports', () {
    final a = AndroidOutput.fromMap({
      'mixerRate': 48000,
      'framesPerBuffer': 144,
      'lowLatency': true,
      'pro': false,
      'spatial': 'off',
      'volume': 90,
      'maxVolume': 150,
      'deviceBits': 16,
    });
    expect(a.bufferMs, 3);
    expect(a.spatial, AndroidSpatial.off);
    expect((a.volume, a.maxVolume, a.deviceBits), (90, 150, 16));
    expect(AndroidOutput.fromMap({}).bufferMs, isNull);
  });

  testWidgets('Detail stats shows the phone\'s mixer, its audio features and the volume in its own steps', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    AndroidOutput.readOverride = () async => const AndroidOutput(
      mixerRate: 48000,
      framesPerBuffer: 144,
      lowLatency: true,
      spatial: AndroidSpatial.off,
      volume: 90,
      maxVolume: 150,
      deviceBits: 16,
    );
    addTearDown(() => AndroidOutput.readOverride = null);
    tester.view.physicalSize = const Size(400, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = _StatsPlayer();
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(onPressed: () => showDetailStats(context), child: const Text('Open')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    for (final (label, value) in const [
      ('Device sample rate', '48 kHz'),
      ('Device format', '16-bit'),
      ('Mixer buffer', '3.0 ms · 144 frames'),
      ('Low-latency audio', 'Supported'),
      ('Pro audio', 'Not supported'),
      ('Spatial audio', 'Off'),
      ('System volume', '90 / 150'),
    ]) {
      await tester.scrollUntilVisible(find.text(label), 200, scrollable: find.byType(Scrollable).last);
      expect(find.text(value), findsWidgets, reason: label);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.pump(const Duration(seconds: 4));
  });
}
