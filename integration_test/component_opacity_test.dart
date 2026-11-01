import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:riflay/main.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true, macOS: true);

  testWidgets('native desktop composites the whole frame and dialogs with alpha', (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await windowManager.ensureInitialized();
      await windowManager.setBackgroundColor(Colors.transparent);
      final look = Appearance.instance;
      await look.reset();
      final c = PlayerController();
      final capture = GlobalKey();
      try {
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: RiflayApp(controller: c),
          ),
        );
        await tester.pump();
        final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
        navigator.push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              body: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.music_note_rounded, size: 100),
                        Text('Desktop component opacity', style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 24),
                        const Text('Cards, artwork, text, buttons and overlays fade together'),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => const AlertDialog(
                              title: Text('Transparent dialog'),
                              content: Text('Overlays share the same opacity as the entire app.'),
                            ),
                          ),
                          child: const Text('Open dialog'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await look.setComponentOpacity(0.55);
        await tester.pump();
        await tester.tap(find.text('Open dialog'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
        var maxAlpha = 0;
        for (var i = 3; i < rgba.length; i += 4) {
          if (rgba[i] > maxAlpha) maxAlpha = rgba[i];
        }
        expect(maxAlpha, inInclusiveRange(139, 141));
        const shots = String.fromEnvironment('SHOTS');
        if (shots.isNotEmpty) {
          await Directory(shots).create(recursive: true);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$shots/desktop-component-opacity.png').writeAsBytes(png!.buffer.asUint8List());
        }
        image.dispose();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await look.reset();
        c.dispose();
      }
    });
  }, skip: !Appearance.hasComponentOpacity);
}
