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
}
