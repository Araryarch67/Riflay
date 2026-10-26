// Real downloads of one short Creative Commons YouTube video in each format and
// quality step, plus screenshots of the downloads screens. Does nothing
// without DL (a folder to write into) set:
//
//   env -u DISPLAY WAYLAND_DISPLAY=om-dl GDK_BACKEND=wayland XDG_DATA_HOME=<scratch>/xdg-data \
//     PIPEWIRE_REMOTE=om-none PULSE_SERVER=unix:/nonexistent dbus-run-session -- \
//     flutter test integration_test/downloads_flow_test.dart -d linux --dart-define=DL=<scratch>/dl
//
// Then check what was saved:  ffprobe -hide_banner <scratch>/dl/out/*
//
// Uses AM3DIzTpcw4 (149 s) and JESx2qFyupM (175 s), both marked "Creative
// Commons Attribution license (reuse allowed)" on YouTube.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:riflay/main.dart';
import 'package:riflay/services/download_prefs.dart';
import 'package:riflay/services/player_controller.dart';
import 'package:riflay/services/youtube_importer.dart';
import 'package:riflay/ui/download_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

const dl = String.fromEnvironment('DL');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real downloads and screenshots', (tester) async {
    if (dl.isEmpty) return;
    final out = Directory('$dl/out')..createSync(recursive: true);
    final shots = Directory('$dl/shots')..createSync(recursive: true);
    SharedPreferences.setMockInitialValues({'discord.enabled': false});
    await DownloadPrefs.instance.setFolder('$dl/library');

    final c = PlayerController();
    await c.load();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(child: RiflayApp(controller: c)));

    Future<void> settle([int ms = 600]) async {
      for (var i = 0; i < ms ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> shot(String name) async {
      await settle(1500);
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('${shots.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    Future<DownloadJob> download(String id, DownloadChoice choice) async {
      final preview = await tester.runAsync(() => c.youtube.resolve('https://www.youtube.com/watch?v=$id'));
      final video = (preview! as VideoPreview).video;
      c.youtube.enqueue([video], choice: choice);
      final job = c.youtube.jobFor(id)!;
      for (var i = 0; i < 1200 && job.isActive; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      expect(job.status, DownloadStatus.done, reason: '${job.error}');
      return job;
    }

    for (final (format, quality) in [
      (DownloadFormat.opus, DownloadQuality.best),
      (DownloadFormat.m4a, DownloadQuality.best),
      (DownloadFormat.opus, DownloadQuality.smallest),
      (DownloadFormat.m4a, DownloadQuality.smaller),
    ]) {
      final job = await download('AM3DIzTpcw4', DownloadChoice(format, quality));
      final file = File(job.track!.path!);
      file.copySync('${out.path}/${format.name}-${quality.name}${file.path.substring(file.path.lastIndexOf('.'))}');
      // ignore: avoid_print
      print('DOWNLOADED ${format.name}/${quality.name}: ${job.quality} -> ${file.lengthSync()} bytes');
      c.youtube.clearFinished();
    }
    // Two rows for the list picture: one in each format.
    await download('AM3DIzTpcw4', const DownloadChoice(DownloadFormat.opus, DownloadQuality.best));
    await download('JESx2qFyupM', const DownloadChoice(DownloadFormat.m4a, DownloadQuality.best));
    await settle(1000);

    // Desktop: Downloads in the sidebar, then its page.
    await shot('desktop-sidebar-home');
    await tester.tap(find.text('Downloads').first);
    await settle();
    await shot('desktop-downloads-list');

    // The edit sheet for the m4a.
    final m4a = c.allSongs.tracks.firstWhere((t) => t.path!.endsWith('JESx2qFyupM.m4a'));
    final ctx = tester.element(find.text('Downloads').first);
    showDownloadEditor(ctx, m4a, compact: false).ignore();
    await settle();
    await shot('desktop-edit-sheet');
    await tester.tap(find.text('Cancel'));
    await settle();

    // Settings › Downloads.
    await tester.tap(find.byTooltip('More'));
    await settle();
    await tester.tap(find.text('Settings').last);
    await settle();
    await tester.tap(find.text('Downloads').last);
    await settle();
    await shot('desktop-settings-downloads');

    // A phone: the four tabs, and the Downloads tab.
    tester.view.physicalSize = const Size(400, 860);
    await settle(800);
    await shot('phone-home-tabs');
    await tester.tap(find.text('Downloads').last);
    await settle();
    await shot('phone-downloads-tab');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
