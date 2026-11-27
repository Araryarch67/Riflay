import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/audio_engine.dart';
import 'package:riflay/services/eq_level_match.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/pages/equalizer_page.dart';

const _bass = [EqBand(60, 6), EqBand(120, 4)];

void main() {
  test('a flat curve changes nothing', () {
    expect(eqLoudnessChange(const [], 0), 0);
    expect(eqLoudnessChange(const [EqBand(1000, 0)], 0), 0);
    expect(eqBypassTrim(const [], 0), 0);
  });

  test('a boost is louder than its peak headroom hides: trim is below 0 only when it is louder', () {
    final peak = AudioEngine.peakGain(_bass);
    // With the headroom the equalizer applies, the curve is quieter than flat, so no gain is needed on the
    // bypassed side beyond turning it down by that difference.
    final change = eqLoudnessChange(_bass, -peak);
    expect(change, lessThan(0));
    expect(eqBypassTrim(_bass, -peak), change);
    // Without headroom a bass boost is louder than flat: the bypassed side is never raised (it could clip).
    expect(eqLoudnessChange(_bass, 0), greaterThan(0));
    expect(eqBypassTrim(_bass, 0), 0);
  });

  test('cuts only make the equalized side quieter, in proportion', () {
    const cut = [EqBand(1000, -6, q: 0.5)];
    final a = eqLoudnessChange(cut, 0);
    expect(a, lessThan(0));
    expect(eqLoudnessChange(const [EqBand(1000, -12, q: 0.5)], 0), lessThan(a));
  });

  test('B bypasses the equalizer with the matching trim, and any change to the curve ends it', () async {
    final a = AudioEngine()
      ..eqEnabled = true
      ..bands = _bass;
    await a.setAbBypass(true);
    expect(a.abBypass, isTrue);
    expect(a.eqActive, isFalse);
    expect(a.abTrim, closeTo(eqBypassTrim(_bass, -AudioEngine.peakGain(_bass)), 1e-9));
    expect(a.filterChain, contains('@abtrim'));
    await a.setAbBypass(false);
    expect(a.abTrim, 0);
    expect(a.filterChain, isNot(contains('@abtrim')));
    await a.setAbBypass(true);
    await a.applyPreset('Flat');
    expect(a.abBypass, isFalse);
  });

  testWidgets('the equalizer page toggles A and B', (tester) async {
    final c = PlayerController();
    final audio = c.audio
      ..eqEnabled = true
      ..bands = _bass;
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: EqualizerPanel())),
        ),
      ),
    );
    expect(find.text('A · EQ on'), findsOneWidget);
    await tester.tap(find.text('B · EQ off'));
    await tester.pump();
    expect(audio.abBypass, isTrue);
    expect(find.textContaining('turned down'), findsOneWidget);
    await tester.tap(find.text('A · EQ on'));
    await tester.pump();
    expect(audio.abBypass, isFalse);
    expect(find.textContaining('turned down'), findsNothing);
    // The engine's debounced chain sync.
    await tester.pump(const Duration(seconds: 2));
  });
}
