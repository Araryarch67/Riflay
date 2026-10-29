// Pictures of the Layout options, offline: a throwaway library of silent files with
// their own cover art and lyrics. Does nothing without SHOTS.
//
//   env -u DISPLAY WAYLAND_DISPLAY=om-layout GDK_BACKEND=wayland XDG_DATA_HOME=/tmp/x PIPEWIRE_REMOTE=om-none \
//     PULSE_SERVER=unix:/nonexistent dbus-run-session -- flutter test integration_test/layout_screenshots_test.dart \
//     -d linux --dart-define=SHOTS=/tmp/shots

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:riflay/main.dart';
import 'package:riflay/models/track.dart';
import 'package:riflay/services/layout_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/ui/player_panels.dart';
import 'package:shared_preferences/shared_preferences.dart';

const shots = String.fromEnvironment('SHOTS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Layout screenshots', (tester) async {
    if (shots.isEmpty) return;
    JustAudioMediaKit.ensureInitialized(linux: true);
    Directory(shots).createSync(recursive: true);

    final dir = Directory.systemTemp.createTempSync('om-layout');
    const albums = [
      ('Codfish', 'Boots', 'ff7043'),
      ('Jairo', 'Paradise', '3949ab'),
      ('D-low', 'Poison Dagger', '2e7d32'),
      ('Osis', 'Rise', '8e24aa'),
      ('Codfish', 'Echo', 'c62828'),
      ('Jairo', 'Tide', '00838f'),
    ];
    final tracks = <Track>[];
    await tester.runAsync(() async {
      for (final (i, (artist, album, hex)) in albums.indexed) {
        for (var n = 1; n <= 2; n++) {
          final title = '$album ${n == 1 ? 'Intro' : 'Main'}';
          final base = '${dir.path}/$artist - $title';
          await Process.run('ffmpeg', [
            '-loglevel',
            'error',
            '-y',
            '-f',
            'lavfi',
            '-i',
            'color=c=0x$hex:s=300x300',
            '-frames:v',
            '1',
            '$base.png', //
          ]);
          await Process.run('ffmpeg', [
            '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo', '-i', '$base.png', //
            '-t',
            '240',
            '-map',
            '0:a',
            '-map',
            '1:v',
            '-c:a',
            'flac',
            '-c:v',
            'png',
            '-disposition:v',
            'attached_pic', //
            '-metadata', 'title=$title', '-metadata', 'artist=$artist', '-metadata', 'album=$album', '$base.flac',
          ]);
          File('$base.lrc').writeAsStringSync(
            '[00:00.00]Lights come up on the water\n[00:08.00]Every sound is a small town\n[00:16.00]Count me in when it starts\n'
            '[00:24.00]I will carry the low end\n[00:32.00]Hold the line, hold the line\n[00:40.00]Then the whole room answers\n',
          );
          tracks.add(
            Track(
              id: Uri.file('$base.flac').toString(),
              uri: Uri.file('$base.flac'),
              title: title,
              artist: artist,
              album: album,
              duration: const Duration(minutes: 4),
              trackNumber: n,
              addedAt: DateTime.now().millisecondsSinceEpoch - i * 1000 - n,
            ),
          );
        }
      }
    });
    SharedPreferences.setMockInitialValues({
      'discord.enabled': false,
      'library.v1': jsonEncode([for (final t in tracks) t.toJson()]),
    });

    final c = PlayerController();
    final apply = JustAudioMediaKit.onPlayerCreated!;
    JustAudioMediaKit.onPlayerCreated = (p) async {
      await (p.platform as NativePlayer).setProperty('ao', 'null');
      apply(p);
    };
    await tester.runAsync(c.load);
    final look = LayoutPrefs.instance;

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(child: RiflayApp(controller: c)));

    Future<void> settle([int ms = 600]) async {
      for (var i = 0; i < ms ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> shot(String name) async {
      await settle(1200);
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    Future<void> set(Future<void> Function() change) async {
      await tester.runAsync(change);
      await settle(200);
    }

    Future<void> popRoute() async {
      Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
      await settle();
    }

    try {
      await settle(1500);
      tester.runAsync(() => c.playList(tracks, 3, from: 'Codfish')).ignore();
      await settle(1500);
      await shot('desktop-home-default');

      await set(() => look.setCorners(CornerStyle.square));
      await set(() => look.setDensity(Density.compact));
      await set(() => look.setCoverSize(CoverSize.large));
      await set(() => look.setPlayButton(PlayButtonShape.roundedSquare));
      await set(() => look.setProgressBar(ProgressBarStyle.thick));
      await shot('desktop-home-compact-square-large');

      await set(() => look.setCorners(CornerStyle.extraRound));
      await set(() => look.setCoverSize(CoverSize.small));
      await set(() => look.setDensity(Density.comfortable));
      await shot('desktop-home-extra-round-small');

      await set(() => look.setHomeSectionShown(HomeSection.recentlyPlayed, false));
      await set(() => look.moveHomeSection(HomeSection.values.length - 1, 1));
      await shot('desktop-home-reordered');
      await set(look.reset);

      await tester.tap(find.byTooltip('Lyrics').first);
      await settle(1500);
      await shot('desktop-lyrics-default');
      await set(() => look.setLyricsSize(LyricsSize.large));
      await set(() => look.setLyricsAlign(LyricsAlign.centre));
      await shot('desktop-lyrics-large-centred');
      await set(look.reset);

      await tester.tap(find.byTooltip('More').first);
      await settle();
      await tester.tap(find.text('Settings').first);
      await settle();
      await tester.tap(find.text('Look & feel'));
      await settle();
      await tester.tap(find.text('Layout'));
      await settle();
      tester.view.physicalSize = const Size(1280, 1500);
      await shot('desktop-settings-layout');
      tester.view.physicalSize = const Size(1280, 800);

      tester.view.physicalSize = const Size(400, 860);
      await settle(1000);
      await shot('phone-home-default');
      await tester.tap(find.byType(MiniPlayer));
      await settle(1000);
      await shot('phone-nowplaying-default');
      await popRoute();

      await set(() => look.setPhoneCover(PhoneCoverSize.large));
      await set(() => look.setPlayButton(PlayButtonShape.roundedSquare));
      await set(() => look.setProgressBar(ProgressBarStyle.thick));
      await tester.tap(find.byType(MiniPlayer));
      await settle(1000);
      await shot('phone-nowplaying-large-thick-square');
      await popRoute();

      await set(() => look.setShowQualityBadge(false));
      await set(() => look.setPhoneCover(PhoneCoverSize.normal));
      await tester.tap(find.byType(MiniPlayer));
      await settle(1000);
      await shot('phone-nowplaying-no-badge');
      await popRoute();
      await set(look.reset);

      await set(() => look.setCorners(CornerStyle.square));
      await set(() => look.setDensity(Density.compact));
      await set(() => look.setCoverSize(CoverSize.large));
      await shot('phone-home-compact-square-large');
    } finally {
      JustAudioMediaKit.onPlayerCreated = apply;
      await tester.runAsync(look.reset);
      await tester.runAsync(c.player.stop);
      dir.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
