import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/collection_hero.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final width in [360.0, 393.0, 600.0]) {
    testWidgets('an artist\'s hero keeps Play whole at $width px, the rest behind More', (tester) async {
      SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(<Object>[])});
      await LayoutPrefs.instance.reset();
      final c = PlayerController();
      await tester.runAsync(c.load);
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final songs = [
        for (var i = 0; i < 3; i++) Track.youtube(videoId: 'v$i', title: 'Song $i', artist: 'Houshou Marine'),
      ];
      await tester.pumpWidget(
        PlayerScope(
          controller: c,
          child: MaterialApp(
            home: ShellScope(
              compact: true,
              width: width,
              open: (_, {location}) {},
              openCollection: (_) {},
              openQueue: () {},
              openNowPlaying: () {},
              openLyrics: () {},
              openDownloads: () {},
              importFromYoutube: ({url}) {},
              addFiles: () {},
              addFolder: null,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: CollectionHero(
                    collection: Collection(
                      kind: CollectionKind.remote,
                      title: 'Houshou Marine',
                      subtitle: 'Artist',
                      tracks: songs,
                    ),
                    // Stands in for Follow: the page's own button.
                    actions: const [SizedBox.square(key: ValueKey('follow'), dimension: 48)],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'no overflow');
      final play = tester.getRect(find.byTooltip('Play'));
      expect(play.width, greaterThanOrEqualTo(132), reason: 'Play stays whole');
      expect(find.byKey(const ValueKey('follow')), findsOneWidget, reason: 'the page\'s own buttons stay');
      if (width < 500) {
        expect(find.byTooltip('More'), findsOneWidget);
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        expect(find.text('Download all for offline'), findsOneWidget, reason: 'what didn\'t fit is in the menu');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async => c.dispose());
    });
  }
}
