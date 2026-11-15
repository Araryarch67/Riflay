import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/sources/music_sources.dart';
import 'package:riflay/services/spotiflac.dart';
import 'package:riflay/ui/ytmusic_edit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a failed alternate-source lookup never starts an unrequested YouTube download', (tester) async {
    SharedPreferences.setMockInitialValues({'sources.monochrome.v1': true, 'library.v1': jsonEncode([])});
    final player = PlayerController();
    await tester.runAsync(() async {
      await MusicSources.instance.load();
      await Spotiflac.instance.load();
      await player.load();
    });
    final origin = Track.youtube(videoId: 'abcdefghijk', title: 'Song', artist: 'Artist');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerScope(
            controller: player,
            child: DownloadButton(track: origin),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(IconButton));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Download source'), findsOneWidget);
    await tester.tap(find.text('Monochrome'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Find a match on Monochrome'), findsOneWidget);
    expect(find.text("Couldn't search this source. Try again or choose another source."), findsOneWidget);
    expect(player.youtube.jobs, isEmpty);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
  });
}
