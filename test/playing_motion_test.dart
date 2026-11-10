import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/ui_beat.dart';
import 'package:riflay/ui/debug_switches.dart';
import 'package:riflay/ui/widgets/controls.dart';
import 'package:riflay/ui/widgets/flower_cover.dart';
import 'package:riflay/ui/widgets/playing_motion.dart';
import 'package:riflay/ui/widgets/wavy_seek_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Controller extends PlayerController {
  bool playing = true;

  @override
  bool get showsPlaying => playing;

  void setPlaying(bool v) {
    playing = v;
    notifyListeners();
  }
}

Widget _host(_Controller c, Widget child, {bool reduce = false}) => PlayerScope(
  controller: c,
  child: MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 300, height: 300, child: child)),
      ),
    ),
  ),
);

/// The clock the wavy seek bar paints its wave from (null: the still wave).
MotionClock? _waveClock(WidgetTester tester) {
  final slider = find.descendant(of: find.byType(SeekBar), matching: find.byType(Slider)).first;
  final theme = tester.widget<SliderTheme>(find.ancestor(of: slider, matching: find.byType(SliderTheme)).first);
  return (theme.data.trackShape! as WavySeekTrack).motion;
}

/// The clock the flower cover outline is drawn from.
MotionClock? _flowerClock(WidgetTester tester) {
  final clip = tester.widget<ClipPath>(find.descendant(of: find.byType(FlowerCover), matching: find.byType(ClipPath)));
  return (clip.clipper! as FlowerClipper).motion;
}

Future<void> _beats(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(UiBeat.period);
  }
}

void main() {
  late _Controller c;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LayoutPrefs.instance.reset();
    await LayoutPrefs.instance.setPerformance(PerformanceMode.heavy);
    c = _Controller();
  });
  tearDown(() async {
    await LayoutPrefs.instance.reset();
    c.dispose();
  });

  final flower = FlowerCover(animate: true, fit: true, child: const ColoredBox(color: Colors.white));

  group('wavy seek bar', () {
    testWidgets('phone wave keeps moving after track changes and returning to the app', (tester) async {
      await tester.pumpWidget(_host(c, const SeekBar(phonePlayer: true)));
      final motion = tester.widget<PlayingMotion>(find.byType(PlayingMotion));
      expect(motion.restWithVideo, isFalse, reason: 'a loaded background video must not flatten the seek bar');
      final clock = _waveClock(tester)!;
      for (var song = 0; song < 3; song++) {
        // Playback can briefly stop while the next song loads.
        c.setPlaying(false);
        await _beats(tester, 10);
        c.setPlaying(true);
        await _beats(tester, 60);
        expect(clock.eased, 1);
        final before = clock.time;
        await _beats(tester, 5);
        expect(clock.time, greaterThan(before));
      }

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await _beats(tester, 60);
      expect(clock.eased, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _beats(tester, 60);
      expect(clock.eased, 1);
      final before = clock.time;
      await _beats(tester, 5);
      expect(clock.time, greaterThan(before));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the wave travels while playing and flattens and stills when paused', (tester) async {
      await tester.pumpWidget(_host(c, const SeekBar(phonePlayer: true)));
      final clock = _waveClock(tester)!;
      expect(clock.eased, 1);
      final before = clock.time;
      await _beats(tester, 5);
      expect(clock.time, greaterThan(before), reason: 'the phase moves with the beat');
      c.setPlaying(false);
      await _beats(tester, 60);
      expect(clock.eased, 0, reason: 'a pause eases the wave to a straight line');
      final rest = clock.time;
      await _beats(tester, 10);
      expect(clock.time, rest);
      c.setPlaying(true);
      await _beats(tester, 10);
      expect(clock.eased, greaterThan(0));
      expect(clock.time, greaterThan(rest));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Balanced draws every third beat, Heavy every beat', (tester) async {
      await LayoutPrefs.instance.setPerformance(PerformanceMode.balanced);
      await tester.pumpWidget(_host(c, const SeekBar(phonePlayer: true)));
      final clock = _waveClock(tester)!;
      var ticks = 0;
      clock.addListener(() => ticks++);
      await _beats(tester, 12);
      expect(ticks, inInclusiveRange(3, 5));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Balanced on a computer draws every twelfth beat (5 fps)', (tester) async {
      DebugSwitches.fullBalanced = false;
      addTearDown(() => DebugSwitches.fullBalanced = true);
      await LayoutPrefs.instance.setPerformance(PerformanceMode.balanced);
      await tester.pumpWidget(_host(c, const SeekBar(phonePlayer: true)));
      final clock = _waveClock(tester)!;
      var ticks = 0;
      clock.addListener(() => ticks++);
      await _beats(tester, 24);
      expect(ticks, inInclusiveRange(1, 3));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Lightweight and reduced motion keep the still wave', (tester) async {
      await tester.pumpWidget(_host(c, const SeekBar(phonePlayer: true), reduce: true));
      expect(_waveClock(tester), isNull);
      await _beats(tester, 5);
      await LayoutPrefs.instance.setPerformance(PerformanceMode.lightweight);
      await tester.pumpWidget(_host(c, const SeekBar(phonePlayer: true)));
      await tester.pump();
      final shape = tester.widget<SliderTheme>(find.byType(SliderTheme).first).data.trackShape;
      expect(shape, isNot(isA<WavySeekTrack>()), reason: 'Lightweight has no wavy track at all, as before');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('flower cover', () {
    testWidgets('petals turn and ripple while playing, ease to rest when paused', (tester) async {
      await tester.pumpWidget(_host(c, flower));
      final clock = _flowerClock(tester)!;
      final geometry = FlowerContour.radius(100, 0.3, motion: clock);
      await _beats(tester, 20);
      expect(FlowerContour.radius(100, 0.3, motion: clock), isNot(geometry));
      c.setPlaying(false);
      await _beats(tester, 60);
      expect(clock.eased, 0);
      final rest = clock.time;
      final still = FlowerContour.radius(100, 0.3, motion: clock);
      await _beats(tester, 10);
      expect(clock.time, rest);
      expect(FlowerContour.radius(100, 0.3, motion: clock), still);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the flower at rest is exactly the plain flower', (tester) async {
      expect(FlowerContour.radius(100, 0.3, motion: MotionClock()), closeTo(FlowerContour.radius(100, 0.3), 1e-9));
    });

    testWidgets('Lightweight, reduced motion and a hidden page hold still', (tester) async {
      await tester.pumpWidget(_host(c, flower, reduce: true));
      expect(_flowerClock(tester), isNull);
      await _beats(tester, 5);
      await LayoutPrefs.instance.setPerformance(PerformanceMode.lightweight);
      await tester.pumpWidget(_host(c, flower));
      await tester.pump();
      expect(_flowerClock(tester), isNull);
      await LayoutPrefs.instance.setPerformance(PerformanceMode.heavy);
      await tester.pumpWidget(_host(c, TickerMode(enabled: false, child: flower)));
      await tester.pump();
      final clock = _flowerClock(tester);
      final time = clock?.time;
      await _beats(tester, 10);
      expect(clock?.time, time, reason: 'covered pages do not tick');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a paused song never starts the beat', (tester) async {
      c.setPlaying(false);
      await tester.pumpWidget(_host(c, flower));
      final clock = _flowerClock(tester)!;
      var ticks = 0;
      clock.addListener(() => ticks++);
      await _beats(tester, 10);
      expect(ticks, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
