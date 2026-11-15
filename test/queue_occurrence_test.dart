import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/track_row.dart';
import 'package:riflay/ui/widgets/controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

final song = Track(id: 'same', uri: Uri.file('/music/song.flac'), title: 'First Love', artist: 'Kobo Kanaeru');

class _QueuePlayer extends PlayerController {
  @override
  Track? get currentTrack => song;
}

void main() {
  testWidgets('upcoming duplicate has no current indicator and clicking it does not pause the current occurrence', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final player = _QueuePlayer();
    var nextClicked = false;
    await tester.pumpWidget(
      PlayerScope(
        controller: player,
        child: MaterialApp(
          home: ShellScope(
            compact: false,
            width: 900,
            open: (_, {location}) {},
            openCollection: (_) {},
            openQueue: () {},
            openNowPlaying: () {},
            openLyrics: () {},
            openDownloads: () {},
            importFromYoutube: () {},
            addFiles: () {},
            addFolder: null,
            child: Scaffold(
              body: Column(
                children: [
                  TrackRow(track: song, showArtwork: false, index: 1, currentOccurrence: true, onTap: () {}),
                  TrackRow(
                    key: const ValueKey('upcoming'),
                    showArtwork: false,
                    track: song,
                    index: 2,
                    currentOccurrence: false,
                    onTap: () {
                      nextClicked = true;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(EqualizerIcon), findsOneWidget);
    final upcoming = find.byKey(const ValueKey('upcoming'));
    expect(find.descendant(of: upcoming, matching: find.byType(EqualizerIcon)), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(upcoming));
    await tester.pump();
    await mouse.down(tester.getCenter(upcoming));
    await mouse.up();
    await tester.pump();
    expect(nextClicked, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
  });
}
