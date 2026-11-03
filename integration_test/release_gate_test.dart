// The release gate on a real desktop: the real app (your settings, library and account) plays a song, and
// walks Home, the expanded player, its lyrics, the Lyrics page and an album, a while on each. It drives the
// app from inside, so it needs no mouse or focus; the window must stay visible (not minimized).
//
// The app's CPU and memory are measured from outside, as Task Manager shows them: the test writes the phase
// it is in to `<temp>/riflay_gate.phase` ("done" at the end) for the measuring script to follow.
//   flutter drive --profile -d windows --driver=test_driver/integration_test.dart \
//     --target=integration_test/release_gate_test.dart
// GATE_SONG (part of a title) picks the song; by default the first Recently played song with "Official" in it
// (a music video), else the first one.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:riflay/main.dart' as app;
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/player/full_screen_player.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/page_scaffold.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final phaseFile = File('${Directory.systemTemp.path}${Platform.pathSeparator}riflay_gate.phase');
  const seconds = int.fromEnvironment('GATE_SECONDS', defaultValue: 25);

  testWidgets('release gate', (tester) async {
    phaseFile.writeAsStringSync('setup');
    await app.main();
    // Frames come when the app asks for them, as outside a test.
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    Future<void> wait(Duration d) => Future<void>.delayed(d);
    for (var i = 0; i < 300 && find.byType(PageScaffold).evaluate().isEmpty; i++) {
      await wait(const Duration(milliseconds: 100));
    }
    final context = tester.element(find.byType(PageScaffold).first);
    final c = PlayerScope.read(context);
    final shell = ShellScope.of(context);

    final want = Platform.environment['GATE_SONG']?.toLowerCase();
    final recent = c.recentlyPlayed;
    final song = recent.firstWhere(
      (t) => t.title.toLowerCase().contains(want ?? 'official'),
      orElse: () => recent.first,
    );
    await c.playList([song], 0);
    for (var i = 0; i < 200 && !c.isPlaying; i++) {
      await wait(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print('GATE playing ${song.title}');
    // Streams start, the video is looked up and the caches fill.
    await wait(const Duration(seconds: 8));

    Future<void> phase(String name, [Future<void> Function()? during]) async {
      phaseFile.writeAsStringSync(name);
      final end = DateTime.now().add(const Duration(seconds: seconds));
      if (during != null) await during();
      final left = end.difference(DateTime.now());
      if (!left.isNegative) await wait(left);
    }

    await phase('home_playing');
    await showExpandedPlayer(true);
    await wait(const Duration(seconds: 2));
    await phase('now_playing');
    toggleExpandedPanel(ExpandedPanel.lyrics);
    await phase('lyrics_expanded');
    await showExpandedPlayer(false);
    await wait(const Duration(seconds: 1));
    shell.openLyrics();
    await phase('lyrics_page');
    shell.openCollection(c.albums.firstWhere((a) => a.tracks.length > 5, orElse: () => c.albums.first));
    await phase('album_scroll', () async {
      await wait(const Duration(seconds: 2));
      final list = find.byType(Scrollable).last;
      for (var i = 0; i < 6; i++) {
        await tester.fling(list, Offset(0, i.isEven ? -600 : 600), 1500);
        await wait(const Duration(seconds: 2));
      }
    });
    await tester.tap(find.byTooltip('Home'));
    await phase('home_again');
    phaseFile.writeAsStringSync('done');
    await c.pause();
  }, timeout: Timeout.none);
}
