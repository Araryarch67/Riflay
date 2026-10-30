import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/ui/debug_switches.dart';
import 'package:riflay/ui/shell/first_frame_gate.dart';
import 'package:riflay/ui/theme.dart';

/// Counts its builds; marked as reading no colour.
class _Marked extends StatelessWidget implements ColorFreeSelf {
  const _Marked(this.builds);
  final List<int> builds;

  @override
  Widget build(BuildContext context) {
    builds.add(1);
    return const SizedBox(width: 10, height: 10);
  }
}

void main() {
  tearDown(() {
    DebugSwitches.restyleAll = false;
    DebugSwitches.noFirstFrameGate = false;
    FirstFrameGate.reset();
  });

  testWidgets('RIFLAY_RESTYLE_ALL rebuilds widgets marked colour-free too', (tester) async {
    final builds = <int>[];
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: _Marked(builds)));
    final root = tester.element(find.byType(Directionality));

    restyleTree(root);
    await tester.pump();
    expect(builds, hasLength(1), reason: 'skipped normally');

    DebugSwitches.restyleAll = true;
    restyleTree(root);
    await tester.pump();
    expect(builds, hasLength(2), reason: 'rebuilt with the switch on');
  });

  testWidgets('RIFLAY_NO_FIRST_FRAME_GATE shows the child in the first frame', (tester) async {
    Widget gate() => const Directionality(
      textDirection: TextDirection.ltr,
      child: FirstFrameGate(child: Text('content')),
    );
    await tester.pumpWidget(gate());
    expect(find.text('content'), findsNothing, reason: 'waits a frame normally');

    FirstFrameGate.reset();
    DebugSwitches.noFirstFrameGate = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(gate());
    expect(find.text('content'), findsOneWidget);
  });
}
