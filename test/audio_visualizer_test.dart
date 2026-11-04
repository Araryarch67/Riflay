import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/ui/pages/layout_settings.dart';
import 'package:riflay/ui/widgets/audio_visualizer.dart';
import 'package:riflay/ui/widgets/flower_cover.dart';
import 'package:riflay/ui/widgets/audio_reactive_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final prefs = LayoutPrefs.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await prefs.reset();
  });
  tearDown(prefs.reset);

  testWidgets('off preserves the cover with a minimal glow without requiring an audio player', (tester) async {
    await prefs.setVisualizer(false);
    const cover = SizedBox(key: ValueKey('art'), width: 200, height: 200);
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: AudioVisualizer(child: cover)),
      ),
    );
    expect(tester.getSize(find.byKey(const ValueKey('art'))), const Size(200, 200));
    expect(find.byType(FlowerCover), findsOneWidget);
    expect(find.byType(AudioReactiveView), findsNothing);
    expect(find.descendant(of: find.byType(AudioVisualizer), matching: find.byType(CustomPaint)), findsOneWidget);
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
    expect(find.descendant(of: find.byType(AudioVisualizer), matching: find.byType(CustomPaint)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('linear cover previews keep a minimal glow without requiring an audio player', (tester) async {
    await prefs.setVisualizer(true);
    for (final style in VisualizerStyle.values.where((style) => !style.radial)) {
      await prefs.setVisualizerStyle(style);
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: AudioVisualizer(child: SizedBox(key: ValueKey('art'), width: 200, height: 200)),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(const ValueKey('art'))), const Size(200, 200));
      expect(find.byType(FlowerCover), findsOneWidget);
      expect(find.byType(AudioReactiveView), findsNothing);
      expect(find.descendant(of: find.byType(AudioVisualizer), matching: find.byType(CustomPaint)), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the visualizer is a normal setting in Layout, on (Pulse) by default', (tester) async {
    expect(prefs.visualizer, isTrue);
    expect(prefs.visualizerStyle, VisualizerStyle.pulse);
    await prefs.setVisualizer(false);
    await prefs.setVisualizerStyle(VisualizerStyle.orbit);
    await tester.pumpWidget(const MaterialApp(home: AudioVisualizer(child: SizedBox.square(dimension: 200))));
    expect(find.byType(VisualizerCanvas), findsNothing);
    expect(find.byType(FlowerCover), findsOneWidget);
    expect(find.byType(AudioReactiveView), findsNothing);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: LayoutSettings())),
      ),
    );
    expect(find.text('Audio visualizer'), findsWidgets);
    expect(find.text('Visualizer style'), findsNothing, reason: 'the styles show once it is on');
  });

  testWidgets('Cover: Square is a plain rounded card, no flower, no glow, no motion', (tester) async {
    await prefs.setVisualizer(false);
    await prefs.setPlayerCover(PlayerCover.square);
    expect(prefs.visualizerCoverShape, VisualizerCoverShape.square);
    expect(prefs.visualizerEnabled, isFalse);
    await tester.pumpWidget(const MaterialApp(home: AudioVisualizer(child: SizedBox.square(dimension: 200))));
    expect(find.byType(FlowerCover), findsNothing);
    expect(find.descendant(of: find.byType(AudioVisualizer), matching: find.byType(ClipRRect)), findsOneWidget);
    expect(find.byType(AudioReactiveView), findsNothing);
    await prefs.setPlayerCover(PlayerCover.flower);
    await tester.pumpWidget(const MaterialApp(home: AudioVisualizer(child: SizedBox.square(dimension: 200))));
    expect(tester.widget<FlowerCover>(find.byType(FlowerCover)).shape, VisualizerCoverShape.flower);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Layout owns the visualizer switch and its styles', (tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await prefs.setVisualizer(false);
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
    expect(find.text('Radius movement'), findsOneWidget);
    expect(find.text('Line thickness'), findsOneWidget);
    await tester.ensureVisible(find.text('Pulse'));
    await tester.tap(find.text('Pulse'));
    await tester.pumpAndSettle();
    for (final style in VisualizerStyle.values) {
      expect(find.text(style.label), findsWidgets);
    }
    await tester.tap(find.text('Wave'));
    await tester.pumpAndSettle();
    expect(prefs.visualizerStyle, VisualizerStyle.wave);
  });
}
