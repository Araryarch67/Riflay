import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/lyrics.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/pages/lyrics_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Player extends PlayerController {
  final song = Track.youtube(videoId: 'playback-ui', title: 'Song', artist: 'Artist');
  Track? selected;

  @override
  Track get currentTrack => song;
  @override
  Track get currentAudioTrack => selected ?? song;
}

void main() {
  testWidgets('lyrics change with the actual audio while the queue song stays the same', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('riflay-playback-lyrics-');
    UserLyrics.dirOverride = dir;
    final c = _Player();
    final local = Track.fromUri(File('${dir.path}/local.flac').uri);
    await tester.runAsync(() async {
      await UserLyrics.save(c.song, '[00:12.00]YouTube timing');
      await UserLyrics.save(local, '[00:10.00]Local timing');
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        c.dispose();
        UserLyrics.dirOverride = null;
        await dir.delete(recursive: true);
      });
    });
    c.selected = local;
    await tester.pumpWidget(
      PlayerScope(
        controller: c,
        child: MaterialApp(
          home: Scaffold(body: LyricsView(track: c.song)),
        ),
      ),
    );
    Future<void> waitFor(String line) async {
      for (var i = 0; i < 20 && find.text(line).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await tester.pump();
      }
      expect(find.text(line), findsOneWidget);
    }

    await waitFor('Local timing');
    expect(find.text('YouTube timing'), findsNothing);
    c.selected = null;
    c.notifyListeners();
    await tester.pump();
    await waitFor('YouTube timing');
    expect(find.text('Local timing'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
