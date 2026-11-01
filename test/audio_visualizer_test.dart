import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/ui/pages/layout_settings.dart';
import 'package:riflay/ui/widgets/audio_visualizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final prefs = LayoutPrefs.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await prefs.reset();
  });
  tearDown(prefs.reset);

  testWidgets('off preserves the cover size without requiring any audio player', (tester) async {
    const cover = SizedBox(key: ValueKey('art'), width: 200, height: 200);
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: AudioVisualizer(child: cover)),
      ),
    );
    expect(tester.getSize(find.byKey(const ValueKey('art'))), const Size(200, 200));
    expect(find.descendant(of: find.byType(AudioVisualizer), matching: find.byType(CustomPaint)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion suppresses visualizer even when enabled', (tester) async {
    await prefs.setVisualizer(true);
    await prefs.setMotion(Motion.reduced);
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: AudioVisualizer(child: SizedBox(width: 200, height: 200))),
      ),
    );
    expect(find.descendant(of: find.byType(AudioVisualizer), matching: find.byType(CustomPaint)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings exposes style choices only after enabling the visualizer', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: LayoutSettings())),
      ),
    );
    expect(find.text('Visualizer style'), findsNothing);
    final toggle = find.widgetWithText(SwitchListTile, 'Audio visualizer');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(prefs.visualizer, isTrue);
    expect(find.text('Visualizer style'), findsOneWidget);
    await tester.ensureVisible(find.text('Wave'));
    await tester.tap(find.text('Wave'));
    await tester.pumpAndSettle();
    for (final style in VisualizerStyle.values) {
      expect(find.text(style.label), findsWidgets);
    }
    await tester.tap(find.text('Bars'));
    await tester.pumpAndSettle();
    expect(prefs.visualizerStyle, VisualizerStyle.bars);
  });
}
