import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/lyrics.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/pages/equalizer_page.dart';
import 'package:riflay/ui/pages/lyrics_page.dart';
import 'package:riflay/ui/player/full_screen_player.dart';
import 'package:riflay/ui/player/now_playing_page.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SongPlayer extends PlayerController {
  final track = Track(
    id: 'panel-test',
    uri: Uri.parse('file:///panel-test.mp3'),
    title: 'Panel test',
    artist: 'Artist',
  );
  @override
  Track get currentTrack => track;
}

Future<_SongPlayer> _show(WidgetTester tester, Widget page, Size size, {required bool compact}) async {
  SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(<Object>[])});
  final c = _SongPlayer();
  await tester.runAsync(c.load);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    PlayerScope(
      controller: c,
      child: MaterialApp(
        home: ShellScope(
          compact: compact,
          width: size.width,
          open: (_, {location}) {},
          openCollection: (_) {},
          openQueue: () {},
          openNowPlaying: () {},
          openLyrics: () {},
          openDownloads: () {},
          importFromYoutube: ({url}) {},
          addFiles: () {},
          addFolder: null,
          child: page,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return c;
}

void main() {
  tearDown(() => expandedPlayerPanel.value = ExpandedPanel.none);

  testWidgets('expanded player: Lyrics and Equalizer toggle the same side panel', (tester) async {
    final dir = Directory.systemTemp.createTempSync('riflay-panel-test');
    UserLyrics.dirOverride = dir;
    addTearDown(() {
      UserLyrics.dirOverride = null;
      dir.deleteSync(recursive: true);
    });
    SharedPreferences.setMockInitialValues({'library.v1': jsonEncode(<Object>[])});
    final player = _SongPlayer();
    await tester.runAsync(() => UserLyrics.save(player.track, '[00:00.00]Some words'));
    final c = await _show(tester, const Scaffold(body: FullScreenPlayer()), const Size(1200, 800), compact: false);
    // Mounting the cover in this bare harness reports a setState during build that has nothing to do with the panels.
    tester.takeException();
    expect(find.byType(LyricsView), findsNothing);
    expect(find.byType(EqualizerPanel), findsNothing);

    await tester.tap(find.byTooltip('Lyrics'));
    await tester.pump();
    expect(expandedPlayerPanel.value, ExpandedPanel.lyrics);
    expect(tester.takeException(), isNull, reason: 'after lyrics');
    expect(find.byType(LyricsView), findsOneWidget);
    expect(find.byTooltip('Hide lyrics'), findsOneWidget);

    // The other button swaps the panel in the same place.
    await tester.tap(find.byTooltip('Equalizer'));
    await tester.pump();
    expect(expandedPlayerPanel.value, ExpandedPanel.equalizer);
    expect(find.byType(LyricsView), findsNothing);
    expect(find.byType(EqualizerPanel), findsOneWidget);
    expect(find.byTooltip('Lyrics'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'after eq');
    expect(find.byTooltip('Hide equalizer'), findsOneWidget);
    expect(find.text('Flat'), findsOneWidget, reason: 'the presets are there');

    // The lit button closes it again.
    await tester.tap(find.byTooltip('Hide equalizer'));
    await tester.pump();
    expect(expandedPlayerPanel.value, ExpandedPanel.none);
    expect(find.byType(EqualizerPanel), findsNothing);

    // Narrow window: the panel replaces the cover instead of sitting beside it.
    await tester.tap(find.byTooltip('Equalizer'));
    await tester.pump();
    tester.view.physicalSize = const Size(700, 500);
    await tester.pump();
    expect(find.byType(EqualizerPanel), findsOneWidget);
    expect(find.text('Panel test'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => c.dispose());
  });

  testWidgets('phone Now Playing: the volume slider sets the player volume', (tester) async {
    final c = await _show(tester, const NowPlayingPage(), const Size(360, 640), compact: true);
    await tester.runAsync(() => c.setVolume(0.5));
    await tester.pump();
    expect(find.byIcon(Icons.volume_down_rounded), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    final volume = find.ancestor(of: find.byIcon(Icons.volume_up_rounded), matching: find.byType(Row)).first;
    final bar = find.descendant(of: volume, matching: find.byType(Slider));
    expect(bar, findsOneWidget);
    expect(tester.widget<Slider>(bar).value, 0.5);

    // Dragging from the middle to the far right turns it up all the way.
    final rect = tester.getRect(bar);
    await tester.dragFrom(rect.center, Offset(rect.width, 0));
    await tester.pump();
    expect(c.volumeLevel.value, 1.0);
    expect(tester.widget<Slider>(bar).value, 1.0);

    await tester.tap(find.byTooltip('Quieter'));
    await tester.pump();
    expect(c.volumeLevel.value, closeTo(0.95, 0.001));
    expect(tester.takeException(), isNull, reason: 'fits a 360x640 phone');

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => c.dispose());
  });
}
