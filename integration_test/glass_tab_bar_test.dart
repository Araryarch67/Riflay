// The phone's Liquid glass tab bar in the real app: at rest, shrunk by scrolling, on Search and while typing.
// A throwaway library of silent songs with their own covers; add SHOTS to save a picture of each state.
//
//   env -u DISPLAY WAYLAND_DISPLAY=om-test GDK_BACKEND=wayland XDG_DATA_HOME=/tmp/om-test-data \
//     flutter test integration_test/glass_tab_bar_test.dart -d linux --dart-define=SHOTS=/tmp/shots

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
import 'package:riflay/ui/player/mini_player.dart';
import 'package:riflay/ui/shell/phone_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const shots = String.fromEnvironment('SHOTS');

/// The phone's width: `--dart-define=WIDTH=360` for a small one.
const width = int.fromEnvironment('WIDTH', defaultValue: 412);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Liquid glass tab bar', (tester) async {
    JustAudioMediaKit.ensureInitialized(linux: true);
    if (shots.isNotEmpty) Directory(shots).createSync(recursive: true);

    final dir = Directory.systemTemp.createTempSync('om-glass');
    const colours = ['ff7043', '3949ab', '2e7d32', '8e24aa', 'c62828', '00838f', 'f9a825', '6d4c41'];
    final tracks = <Track>[];
    await tester.runAsync(() async {
      for (final (i, hex) in colours.indexed) {
        final base = '${dir.path}/Song $i';
        await Process.run('ffmpeg', [
          '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'color=c=0x$hex:s=300x300', '-frames:v', '1', '$base.png', //
        ]);
        await Process.run('ffmpeg', [
          '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo', '-i', '$base.png', //
          '-t', '240', '-map', '0:a', '-map', '1:v', '-c:a', 'flac', '-c:v', 'png', '-disposition:v', 'attached_pic',
          '-metadata', 'title=More Than Song $i', '-metadata', 'artist=Artist ${i % 3}', //
          '-metadata', 'album=Album ${i % 4}', '$base.flac',
        ]);
        tracks.add(
          Track(
            id: Uri.file('$base.flac').toString(),
            uri: Uri.file('$base.flac'),
            title: 'More Than Song $i',
            artist: 'Artist ${i % 3}',
            album: 'Album ${i % 4}',
            duration: const Duration(minutes: 4),
            addedAt: DateTime.now().millisecondsSinceEpoch - i * 1000,
          ),
        );
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
    await tester.runAsync(() => look.setTabBar(TabBarStyle.glass));

    tester.view.physicalSize = Size(width.toDouble(), 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(child: RiflayApp(controller: c)));

    Future<void> settle([int ms = 600]) async {
      for (var i = 0; i < ms ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> shot(String name) async {
      await settle(800);
      expect(tester.takeException(), isNull, reason: name);
      if (shots.isEmpty) return;
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$shots/$name-$width.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    final collapsed = find.byKey(PhoneBottomBar.tabsButtonKey);
    final field = find.byKey(PhoneBottomBar.searchFieldKey);
    final mini = find.byType(GlassMiniPlayer);

    try {
      await settle(1500);
      tester.runAsync(() => c.playList(tracks, 0, from: 'Glass')).ignore();
      await settle(1500);
      await tester.tap(find.byTooltip('Library').last);
      await settle(1000);

      expect(mini, findsOneWidget);
      expect(collapsed, findsNothing);
      expect(find.byTooltip('Next'), findsOneWidget);
      expect(tester.getRect(mini).bottom, lessThan(tester.getRect(find.byTooltip('Search').last).top));
      await shot('glass-1-rest');

      await tester.drag(find.byType(Scrollable).hitTestable().first, const Offset(0, -250));
      await settle(1000);
      expect(collapsed, findsOneWidget, reason: 'shrunk to one row');
      expect(find.byTooltip('Next'), findsNothing);
      expect(
        tester.getCenter(mini).dy,
        moreOrLessEquals(tester.getCenter(find.byTooltip('Search').last).dy),
        reason: 'the mini player in the middle of the one row',
      );
      await shot('glass-2-scrolled');

      await tester.tap(collapsed);
      await settle(1000);
      expect(collapsed, findsNothing, reason: 'the round tab button brings the tabs back');

      await tester.tap(find.byTooltip('Search').last);
      await settle(1000);
      expect(field, findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      await shot('glass-3-search');

      await tester.tap(field);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await settle(1000);
      await tester.enterText(field, 'more than');
      await settle(1000);
      expect(mini, findsNothing, reason: 'typing: the field alone with Close');
      expect(tester.getRect(field).bottom, lessThan(800 - 300));
      await shot('glass-4-typing');
      tester.view.resetViewInsets();
    } finally {
      JustAudioMediaKit.onPlayerCreated = apply;
      await tester.runAsync(look.reset);
      await tester.runAsync(c.player.stop);
      dir.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
