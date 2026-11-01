import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/player/desktop_player_bar.dart';
import 'package:riflay/ui/shell_scope.dart';
import 'package:riflay/ui/widgets/controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SongPlayer extends PlayerController {
  final song = Track(
    id: 'alignment',
    uri: Uri.parse('file:///alignment.mp3'),
    title: 'A long song title that must fit the available player space',
    artist: 'Artist with a long name',
  );
  @override
  Track get currentTrack => song;
  @override
  Duration get duration => const Duration(minutes: 2, seconds: 30);
  @override
  Stream<Duration> smoothPosition() => Stream.value(const Duration(minutes: 1, seconds: 4));
}

void main() {
  for (final style in DesktopBarStyle.values) {
    for (final width in [700.0, 1024.0, 1920.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${style.name} at $width and text scale $scale keeps metadata and time aligned', (tester) async {
          SharedPreferences.setMockInitialValues({'discord.enabled': false});
          await LayoutPrefs.instance.reset();
          await LayoutPrefs.instance.setDesktopBar(style);
          final c = _SongPlayer();
          await tester.runAsync(c.load);
          tester.view.physicalSize = Size(width, 400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            PlayerScope(
              controller: c,
              child: MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: ShellScope(
                  compact: false,
                  width: width,
                  open: (_, {location}) {},
                  openCollection: (_) {},
                  openQueue: () {},
                  openNowPlaying: () {},
                  openLyrics: () {},
                  openDownloads: () {},
                  importFromYoutube: () {},
                  addFiles: () {},
                  addFolder: null,
                  child: const Scaffold(
                    body: Align(
                      alignment: Alignment.bottomCenter,
                      child: DesktopPlayerBar(sidePanelOpen: false, onToggleSidePanel: null),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          if (style == DesktopBarStyle.compact || style == DesktopBarStyle.capsule) {
            final title = tester.getTopLeft(find.text(c.song.title).first).dx;
            final artist = tester.getTopLeft(find.text(c.song.artist).first).dx;
            final elapsed = tester.getTopLeft(find.text('1:04')).dx;
            final artwork = tester.getRect(find.byType(Artwork).first);
            expect(artist, closeTo(title, 0.1));
            expect(elapsed, closeTo(title, 0.1));
            expect(artwork.right, lessThan(title));
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async => c.dispose());
          await LayoutPrefs.instance.reset();
        });
      }
    }
  }
}
