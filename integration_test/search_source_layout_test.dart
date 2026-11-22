// Search's source filters in the real shell, on desktop and phone layouts.
// Run in headless Weston with a disposable XDG_DATA_HOME; SHOTS saves the current appearance.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:riflay/main.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/pages/search/search_box.dart';
import 'package:riflay/ui/pages/search/soundcloud_results.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('named source filters stay on the Search page below the field', (tester) async {
    JustAudioMediaKit.ensureInitialized(linux: true);
    SharedPreferences.setMockInitialValues({
      'discord.enabled': false,
      'search.source.v1': 'both',
      'sources.soundcloud.v1': true,
      'sources.monochrome.v1': true,
    });
    SearchSource.reset();
    final c = PlayerController();
    await tester.runAsync(c.load);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      SearchSource.reset();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> shot(String name) async {
      expect(tester.takeException(), isNull, reason: name);
      const shots = String.fromEnvironment('SHOTS');
      if (shots.isEmpty) return;
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(shots).createSync(recursive: true);
        File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (final width in [1280, 700]) {
      tester.view.physicalSize = Size(width.toDouble(), 800);
      await tester.pumpWidget(RepaintBoundary(child: RiflayApp(controller: c)));
      await settle();
      final box = find.byType(SearchBox);
      tester.widget<SearchBox>(box.first).onSubmitted('');
      await settle();
      // The source is picked from the search box's own menu.
      final sources = find.byKey(const ValueKey('search-source-menu'));
      expect(sources, findsWidgets);
      expect(SearchSource.current.value, SearchSource.youtubeMusic, reason: 'legacy both uses YouTube Music');
      await shot('desktop-$width-youtube');
      await tester.tap(find.byKey(const ValueKey('search-source-menu')).last);
      await settle();
      await tester.tap(find.byKey(const ValueKey('search-source-soundcloud')));
      await settle();
      expect(SearchSource.current.value, SearchSource.soundcloud);
      await shot('desktop-$width-soundcloud');
      await tester.tap(find.byKey(const ValueKey('search-source-menu')).last);
      await settle();
      await tester.tap(find.byKey(const ValueKey('search-source-youtubeMusic')));
      await settle();
    }

    for (final width in [412, 360]) {
      tester.view.physicalSize = Size(width.toDouble(), 800);
      await settle();
      await tester.tap(find.byTooltip('Search').last);
      await settle();
      final sources = find.byKey(const ValueKey('search-source-menu'));
      expect(sources, findsWidgets);
      expect(find.textContaining('your own music and YouTube Music'), findsOneWidget);
      await shot('phone-$width-youtube');
      await tester.tap(find.byKey(const ValueKey('search-source-menu')).last);
      await settle();
      await tester.tap(find.byKey(const ValueKey('search-source-soundcloud')));
      await settle();
      expect(SearchSource.current.value, SearchSource.soundcloud);
      expect(find.textContaining('your own music and SoundCloud'), findsOneWidget);
      await shot('phone-$width-soundcloud');
      await tester.tap(find.byKey(const ValueKey('search-source-menu')).last);
      await settle();
      await tester.tap(find.byKey(const ValueKey('search-source-youtubeMusic')));
      await settle();
    }
  });
}
