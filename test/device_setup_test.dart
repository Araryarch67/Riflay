import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/device_setup.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/ui/pages/device_setup_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _gb = 1 << 30;

void main() {
  group('recommend', () {
    test('Lightweight for weak computers, Balanced for laptops and mid-range, Heavy for strong desktops', () {
      PerformanceMode pick(int threads, {int? gb = 32, bool? battery = false}) => DeviceSetup.recommend(
        DeviceSpecs(threads: threads, memoryBytes: gb == null ? null : gb * _gb, battery: battery),
      );
      expect(pick(4), PerformanceMode.lightweight);
      expect(pick(6, battery: true), PerformanceMode.lightweight);
      expect(pick(64, gb: 6), PerformanceMode.lightweight);
      expect(pick(8), PerformanceMode.balanced);
      expect(pick(12, gb: 16), PerformanceMode.balanced);
      // A Core Ultra 9 275HX laptop: strong, but on a battery.
      expect(pick(24, gb: 31, battery: true), PerformanceMode.balanced);
      expect(pick(16, gb: 8), PerformanceMode.balanced);
      expect(pick(16, gb: 16), PerformanceMode.heavy);
      expect(pick(24, gb: 32), PerformanceMode.heavy);
      // Unknown memory or battery goes by the threads.
      expect(pick(16, gb: null, battery: null), PerformanceMode.heavy);
      expect(pick(16, battery: null), PerformanceMode.heavy);
    });

    test('memory is rounded as the system shows it', () {
      expect(const DeviceSpecs(threads: 16, memoryBytes: 16297000 * 1024).memoryGb, 16);
    });
  });

  testWidgets('the page shows the computer, picks the recommendation, and Continue applies it once', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await LayoutPrefs.instance.setPerformance(PerformanceMode.lightweight);
    addTearDown(() => LayoutPrefs.instance.setPerformance(PerformanceMode.balanced));
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const specs = DeviceSpecs(
      threads: 16,
      memoryBytes: 16 * _gb,
      battery: true,
      cpu: 'AMD Ryzen 7 7840HS w/ Radeon 780M Graphics',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => DeviceSetupPage(specs: Future.value(specs)))),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('AMD Ryzen 7 7840HS w/ Radeon 780M Graphics'), findsOneWidget);
    expect(find.text('16 processor threads'), findsOneWidget);
    expect(find.text('16 GB of memory'), findsOneWidget);
    expect(find.text('Laptop, runs on battery'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    // Lightweight on 16 threads: 3% of one thread is 0.19% of all of them.
    expect(find.text('About 0.19% of the processor while a song plays'), findsOneWidget);
    // A 16-thread laptop gets Balanced.
    expect(
      find.descendant(
        of: find.ancestor(of: find.text('Recommended'), matching: find.byType(Row)).first,
        matching: find.text('Balanced'),
      ),
      findsOneWidget,
    );

    final shots = Platform.environment['SHOTS'];
    if (shots != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      final image = await tester.runAsync(() => boundary.toImage());
      final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
      File('$shots/device_setup.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(LayoutPrefs.instance.performance, PerformanceMode.balanced);
    expect(DeviceSetup.instance.due, isFalse);
    expect((await SharedPreferences.getInstance()).getBool('deviceSetup.v1'), isTrue);
  });

  testWidgets('"Keep my settings" changes nothing but is remembered', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await LayoutPrefs.instance.setPerformance(PerformanceMode.heavy);
    addTearDown(() => LayoutPrefs.instance.setPerformance(PerformanceMode.balanced));
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: DeviceSetupPage(specs: Future.value(const DeviceSpecs(threads: 4)))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Balanced'));
    await tester.pump();
    await tester.tap(find.text('Keep my settings'));
    await tester.pump();
    expect(LayoutPrefs.instance.performance, PerformanceMode.heavy);
    expect((await SharedPreferences.getInstance()).getBool('deviceSetup.v1'), isTrue);
  });
}
