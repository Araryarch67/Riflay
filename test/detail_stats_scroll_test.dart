import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
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
  testWidgets('scrolling stats holds live updates, then resumes after scrolling stops', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 700);
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
    expect(c.stats.reads, greaterThan(0));
    final list = find.byType(ListView);
    final scroll = tester.widget<ListView>(list).controller!;
    final gesture = await tester.startGesture(tester.getCenter(list));
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();
    expect(scroll.position.isScrollingNotifier.value, isTrue);
    final before = c.stats.reads;
    await tester.pump(const Duration(seconds: 3));
    c.notifyListeners();
    await tester.pump();
    expect(c.stats.reads, before, reason: 'polling pauses throughout an active scroll');
    expect(find.text('Output'), findsNothing, reason: 'offscreen cards are built lazily');
    await gesture.up();
    scroll.jumpTo(scroll.offset);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(c.stats.reads, greaterThan(before));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.pump(const Duration(seconds: 4));
  });
}
