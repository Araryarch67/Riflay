import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/ui/widgets/native_video_surface.dart';

void main() {
  const channel = MethodChannel('riflay/video_window');
  final placements = <List<int>>[];

  setUp(() {
    placements.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'ensure') return 1;
      if (call.method == 'place') placements.add((call.arguments as List).cast<int>());
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('scrolling clips the native surface without shrinking its full video box', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final scroll = ScrollController();
    await NativeVideoWindow.ensure();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 120,
              height: 100,
              child: ListView(
                controller: scroll,
                padding: EdgeInsets.zero,
                children: const [
                  NativeVideoSurface(child: SizedBox(height: 200)),
                  SizedBox(height: 200),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(placements.last, [0, 0, 120, 100, 0, 0, 120, 200]);
    scroll.jumpTo(60);
    await tester.pump();
    expect(placements.last, [0, 0, 120, 100, 0, -60, 120, 140]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(placements.last, List.filled(8, 0));
    scroll.dispose();
  });

  testWidgets('a replacement player is placed even when its surface has not moved', (tester) async {
    await NativeVideoWindow.ensure();
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(width: 160, height: 90, child: NativeVideoSurface(child: SizedBox())),
        ),
      ),
    );
    final placed = placements.last;
    placements.clear();
    await NativeVideoWindow.ensure();
    await tester.pump();
    expect(placements.single, placed);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
