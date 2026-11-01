import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/services/appearance.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/ui/widgets/player_backdrop.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final look = Appearance.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await look.reset();
    await LayoutPrefs.instance.reset();
  });
  tearDown(look.reset);

  testWidgets('simple is the default and needs no audio player or decorative paint', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PlayerBackdrop(coverColor: Colors.pink)));
    expect(look.nowPlaying, NowPlayingBackground.color);
    expect(look.reactiveBackground, isFalse);
    expect(find.descendant(of: find.byType(PlayerBackdrop), matching: find.byType(CustomPaint)), findsNothing);
  });

  testWidgets('all abstract styles render distinct static backgrounds without an audio source', (tester) async {
    final hashes = <String>{};
    for (final style in NowPlayingBackground.values.where((v) => v.isAbstract)) {
      await look.setNowPlaying(style);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: const SizedBox(width: 320, height: 480, child: PlayerBackdrop(coverColor: Color(0xffb64d7b))),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final hash = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final hash = sha256.convert(bytes!.buffer.asUint8List()).toString();
        image.dispose();
        return hash;
      });
      hashes.add(hash!);
      expect(tester.takeException(), isNull);
    }
    expect(hashes.length, 4, reason: 'the choices must produce different compositions');
  });

  test('background and reactive setting persist; reset restores Simple', () async {
    await look.setNowPlaying(NowPlayingBackground.silk);
    await look.setReactiveBackground(true);
    await look.load();
    expect(look.nowPlaying, NowPlayingBackground.silk);
    expect(look.reactiveBackground, isTrue);
    await look.reset();
    expect(look.nowPlaying, NowPlayingBackground.color);
    expect(look.reactiveBackground, isFalse);
  });
}
