import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/ui_beat.dart';

void main() {
  testWidgets('views on the beat update together, slower ones on every other beat', (tester) async {
    final fast = <Duration>[];
    final slow = <Duration>[];
    final a = UiBeat.listen(const Duration(microseconds: 16667), fast.add);
    final b = UiBeat.listen(const Duration(microseconds: 33333), slow.add);
    for (var i = 0; i < 6; i++) {
      await tester.pump(UiBeat.period);
    }
    expect(fast, hasLength(6));
    expect(slow, hasLength(3));
    expect(slow.first, UiBeat.period * 2);
    a.cancel();
    b.cancel();
    // The clock stops with nothing listening: a pending timer would fail the test here.
  });

  testWidgets('slower views fire on the same beats, so they draw in the same frames', (tester) async {
    final beats = <String>[];
    var tick = 0;
    final a = UiBeat.listen(const Duration(milliseconds: 50), (_) => beats.add('a$tick'));
    await tester.pump(UiBeat.period); // the second view starts a beat later
    tick++;
    final b = UiBeat.listen(const Duration(milliseconds: 50), (_) => beats.add('b$tick'));
    final c = UiBeat.listen(const Duration(milliseconds: 150), (_) => beats.add('c$tick'));
    for (var i = 0; i < 17; i++) {
      await tester.pump(UiBeat.period);
      tick++;
    }
    expect(
      UiBeat.beatsFor(const Duration(milliseconds: 125)),
      6,
      reason: 'a seek bar at 8 a second, on the 20 fps beats',
    );
    final frames = {for (final s in beats) s.substring(1)};
    final aFrames = {for (final s in beats.where((s) => s.startsWith('a'))) s.substring(1)};
    expect(frames, aFrames, reason: 'b and c draw only on beats a draws on too');
    a.cancel();
    b.cancel();
    c.cancel();
  });
}
