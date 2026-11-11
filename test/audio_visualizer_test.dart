import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/beta_features.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/player_presets.dart';
import 'package:riflay/ui/pages/layout_settings.dart';
import 'package:riflay/ui/widgets/audio_visualizer.dart';
import 'package:riflay/ui/widgets/flower_cover.dart';
import 'package:riflay/ui/widgets/audio_reactive_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final prefs = LayoutPrefs.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BetaFeatures.instance.reload();
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

  testWidgets('visualizer is off by default and offered under Beta features', (tester) async {
    expect(prefs.visualizer, isTrue);
    expect(prefs.visualizerEnabled, isFalse);
    expect(prefs.visualizerStyle, VisualizerStyle.pulse);
    await prefs.setVisualizer(false);
    await prefs.setVisualizerStyle(VisualizerStyle.orbit);
    await tester.pumpWidget(const MaterialApp(home: AudioVisualizer(child: SizedBox.square(dimension: 200))));
    expect(find.byType(VisualizerCanvas), findsNothing);
    expect(find.byType(FlowerCover), findsOneWidget);
    expect(find.byType(AudioReactiveView), findsNothing);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: BetaSettings())),
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

  testWidgets('Beta features owns the visualizer switch and its styles', (tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await prefs.setVisualizer(false);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: BetaSettings())),
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

  testWidgets('Bit-perfect greys out the switch and says why', (tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await prefs.setVisualizer(true);
    final c = PlayerController();
    c.audio.bitPerfect = true;
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: BetaSettings())),
        ),
      ),
    );
    final toggle = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Audio visualizer'));
    expect(toggle.value, isFalse, reason: 'nothing can show, so it does not read as on');
    expect(toggle.onChanged, isNull);
    expect(find.textContaining('Off while Bit-perfect is on'), findsOneWidget);
    expect(find.text('Visualizer style'), findsNothing);
    expect(prefs.visualizer, isTrue, reason: 'the choice comes back once Bit-perfect is off');
  });

  testWidgets('a Background cover offers only the styles it can show', (tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await prefs.setVisualizer(true);
    await prefs.setVisualizerStyle(VisualizerStyle.orbit);
    await prefs.setPlayerCover(PlayerCover.background);
    expect(prefs.visualizerStyle, VisualizerStyle.wave, reason: 'Orbit has no frame to ring');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: BetaSettings())),
      ),
    );
    await tester.ensureVisible(find.text('Wave'));
    await tester.tap(find.text('Wave'));
    await tester.pumpAndSettle();
    for (final style in VisualizerStyle.values) {
      expect(find.text(style.label), style.radial ? findsNothing : findsWidgets, reason: style.label);
    }
    expect(find.text('Radius movement'), findsNothing);
  });

  test('a preset with a Background cover leaves no radial style behind', () async {
    await prefs.setVisualizerStyle(VisualizerStyle.petals);
    await PlayerPreset.kawaii.apply(prefs);
    expect(prefs.playerCover, PlayerCover.background);
    expect(VisualizerStyle.fitting(prefs.playerCover), contains(prefs.visualizerStyle));
  });
}
