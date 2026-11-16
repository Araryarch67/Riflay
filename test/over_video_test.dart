import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/ui/widgets/over_video.dart';

void main() {
  tearDown(OverVideo.reset);

  const screen = Rect.fromLTWH(0, 0, 800, 600);

  Future<BuildContext> app(WidgetTester tester) async {
    tester.view.physicalSize = screen.size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [OverVideo.root],
        home: const Scaffold(body: SizedBox.expand(key: ValueKey('video'))),
      ),
    );
    return tester.element(find.byKey(const ValueKey('video')));
  }

  testWidgets('nothing open: the video keeps all of its room', (tester) async {
    await app(tester);
    expect(OverVideo.covering(screen), isNull);
  });

  testWidgets('a sheet takes the bottom; the video keeps what is above it, and all of it once closed', (tester) async {
    final context = await app(tester);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SizedBox(height: 200, width: double.infinity),
    );
    await tester.pumpAndSettle();
    final covered = OverVideo.covering(screen)!;
    expect(covered.top, closeTo(400, 50), reason: 'the sheet, not the dimmed barrier over the whole screen');
    final room = OverVideo.beside(screen, covered);
    expect(room.top, 0);
    expect(room.bottom, lessThanOrEqualTo(400));
    expect(room.width, screen.width);
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pumpAndSettle();
    expect(OverVideo.covering(screen), isNull);
  });

  testWidgets('a menu at the right leaves the video the left of the screen', (tester) async {
    final context = await app(tester);
    showMenu<void>(
      context: context,
      position: const RelativeRect.fromLTRB(650, 40, 0, 0),
      items: [for (var i = 0; i < 4; i++) PopupMenuItem(value: null, child: Text('Item $i'))],
    );
    await tester.pumpAndSettle();
    final covered = OverVideo.covering(screen)!;
    expect(covered.left, greaterThan(400));
    final room = OverVideo.beside(screen, covered);
    expect(room.left, 0);
    expect(room.height, screen.height);
  });
}
